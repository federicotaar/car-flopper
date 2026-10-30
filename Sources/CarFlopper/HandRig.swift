import Foundation
import SceneKit
import UIKit

// MARK: - First-person hand rig (camera-space view model)
//
// A procedural right hand + forearm parented to the camera node, animated
// per frame from the renderer callback (the only place scene mutations are
// race-free in this app). Drives three behaviours Fred asked for:
//   - a moving hand: walk bob + look sway, always alive
//   - visible tool pickup: reach-out-and-grab animation on equip
//   - repair animations: per-tool working motion while fixing
// All state arrives as plain vars (one-frame lag is fine); update() runs on
// the render queue.

final class HandRig {
    let root = SCNNode()          // attach to the camera node
    private let sway = SCNNode()  // bob + look sway (position offsets)
    private let pose = SCNNode()  // mode-driven base transform
    private let wrist = SCNNode() // oscillation pivot for work motions
    private let toolAnchor = SCNNode()

    private var toolNodes: [String: SCNNode] = [:]
    private var handRelax: SCNNode?
    private var handGrip: SCNNode?
    private var currentTool: String? = nil
    private var screenMat: SCNMaterial?
    private var arcLight: SCNLight?
    private var arcNode: SCNNode?

    // cross-thread requests (main -> render), consumed in update
    private let reqLock = NSLock()
    private var pendingEquip: String?
    private var pendingEquipWorld: SCNVector3?
    private var pendingWorking: (on: Bool, tool: String?, atWorld: SCNVector3?)?
    private var workTargetWorld: SCNVector3?

    private enum Mode { case idle, equip, working }
    private var mode: Mode = .idle
    private var equipT: Float = 0
    private var workTool: String = ""
    private var phase: Float = 0       // bob phase
    private var bobAmp: Float = 0      // ramped walk amount
    private var swayX: Float = 0
    private var swayY: Float = 0
    private var workTime: Float = 0
    //ADLOG private var logT: Float = 0

    // camera-space rest pose: lower right, forearm entering off-screen
    private let restPos = SCNVector3(0.150, -0.115, -0.360)
    private let restRot = SCNVector3(-0.28, -0.38, 0.10) // euler

    // per-state tool presentation (smoothed in update like the pose):
    // idle lifts the shaft up-forward so a held tool stays in frame at rest;
    // work poses tip the working end down toward the part surface
    private let toolRotIdle = SCNVector3(0, Float.pi / 2, 0) // base spin: tool -z shaft -> -x working end (thumb side)
    private var toolRot = SCNVector3(0, Float.pi / 2, 0)

    init() {
        build()
    }

    private func build() {
        root.addChildNode(sway)
        sway.addChildNode(pose)
        pose.addChildNode(wrist)

        let skin = Mat.flat(0.87, 0.63, 0.50, rough: 0.6)
        let sleeveMat = Mat.flat(0.16, 0.19, 0.26, rough: 0.95)

        // forearm + rolled sleeve are part of the mesh asset itself
        // ("sleeve" entry: cuff extruded over the wrist shell, sleeve tint)
        skin.isDoubleSided = true
        sleeveMat.isDoubleSided = true
        let handSleeve = HandMeshAsset.node("sleeve", material: sleeveMat)

        // mesh hand (CC0 human-hand, two baked poses) replaces the capsule
        // palm/fingers/thumb. relax = open hand; grip = closed fist around
        // the tool anchor. Mesh coords: fingers +y, palm -z, thumb -x;
        // rotated so fingers point forward (-z), palm down (-y).
        let handRelax = HandMeshAsset.node("relax", material: skin)
        let handGrip = HandMeshAsset.node("grip", material: skin)
        for h in [handRelax, handGrip, handSleeve] {
            h.eulerAngles.x = -.pi / 2
            h.scale = SCNVector3(0.9, 0.9, 0.9)
            h.position = SCNVector3(0, 0.0045, -0.006)
            wrist.addChildNode(h)
        }
        handGrip.isHidden = true
        self.handRelax = handRelax
        self.handGrip = handGrip

        toolAnchor.position = SCNVector3(-0.033, 0.038, -0.077) // inside the curled fist
        // tool presentation is per-state (see toolRot targets in update):
        // a forearm-axis tool is foreshortened to invisibility from the
        // first-person camera, so each state angles the shaft to read as a
        // diagonal without clipping the curled fingers
        toolAnchor.eulerAngles = toolRot
        wrist.addChildNode(toolAnchor)

        pose.position = restPos
        pose.eulerAngles = restRot

        // matte response for the whole hand: under the game's HDR + bloom the
        // PBR skin read as a blown-white blob; lambert stays lit but readable
        root.enumerateHierarchy { node, _ in
            guard let mats = node.geometry?.materials else { return }
            for m in mats {
                if let sm = screenMat, m === sm { continue }
                m.lightingModel = .lambert
            }
        }

        for t in ["wrench", "screwdriver", "welder", "diagnostics"] {
            let n = HandRig.buildTool(t, screenMat: &screenMat)
            n.isHidden = true
            toolAnchor.addChildNode(n)
            toolNodes[t] = n
        }
        // the pad rides the relax palm, not the grip anchor
        if let d = toolNodes["diagnostics"] {
            d.removeFromParentNode()
            wrist.addChildNode(d)
            d.position = SCNVector3(-0.036, -0.054, -0.144)
            d.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        }
    }

    // hand-local tool materials: PBR + env + bloom blew the shared chrome out
    // to white at camera distance; matte copies keep tools readable (and the
    // garage's shared chrome untouched)
    private static let toolChrome = Mat.flat(0.72, 0.73, 0.77, rough: 0.45, metal: 0.0)
    private static let toolSteelDark = Mat.flat(0.20, 0.21, 0.24, rough: 0.55, metal: 0.0)

    private static func buildTool(_ id: String, screenMat: inout SCNMaterial?) -> SCNNode {
        let n = SCNNode()
        switch id {
        case "wrench":
            let shaft = SCNNode(geometry: SCNCylinder(radius: 0.0065, height: 0.170))
            shaft.geometry?.firstMaterial = HandRig.toolChrome
            shaft.eulerAngles.x = .pi / 2
            shaft.position = SCNVector3(0, 0.01, -0.055)
            n.addChildNode(shaft)
            let head = SCNNode(geometry: SCNBox(width: 0.030, height: 0.011, length: 0.046, chamferRadius: 0.005))
            head.geometry?.firstMaterial = HandRig.toolChrome
            head.position = SCNVector3(0, 0.01, -0.150)
            n.addChildNode(head)
            // open-end jaw: two flat prongs angled apart, U gap between them
            for side: Float in [-1.0, 1.0] {
                let prong = SCNNode(geometry: SCNBox(width: 0.011, height: 0.010, length: 0.026, chamferRadius: 0.004))
                prong.geometry?.firstMaterial = HandRig.toolChrome
                prong.position = SCNVector3(0.010 * side, 0.01, -0.172)
                prong.eulerAngles.y = -0.38 * side
                n.addChildNode(prong)
            }
        case "screwdriver":
            let grip = SCNNode(geometry: SCNCapsule(capRadius: 0.011, height: 0.075))
            grip.geometry?.firstMaterial = Mat.flat(0.80, 0.18, 0.12, rough: 0.5)
            grip.eulerAngles.x = .pi / 2
            grip.position = SCNVector3(0, 0.012, 0.005)
            n.addChildNode(grip)
            let shaft = SCNNode(geometry: SCNCylinder(radius: 0.0056, height: 0.115))
            shaft.geometry?.firstMaterial = HandRig.toolChrome
            shaft.eulerAngles.x = .pi / 2
            shaft.position = SCNVector3(0, 0.012, -0.088)
            n.addChildNode(shaft)
            let tip = SCNNode(geometry: SCNCone(topRadius: 0.0015, bottomRadius: 0.0058, height: 0.016))
            tip.geometry?.firstMaterial = HandRig.toolChrome
            tip.eulerAngles.x = -.pi / 2
            tip.position = SCNVector3(0, 0.012, -0.152)
            n.addChildNode(tip)
        case "welder":
            let body = SCNNode(geometry: SCNBox(width: 0.024, height: 0.030, length: 0.085, chamferRadius: 0.007))
            body.geometry?.firstMaterial = Mat.flat(0.10, 0.10, 0.11, rough: 0.7)
            body.position = SCNVector3(0, 0.016, -0.020)
            n.addChildNode(body)
            let nozzle = SCNNode(geometry: SCNCylinder(radius: 0.007, height: 0.055))
            nozzle.geometry?.firstMaterial = Mat.flat(0.75, 0.45, 0.20, rough: 0.35, metal: 0.8)
            nozzle.eulerAngles.x = .pi / 2
            nozzle.position = SCNVector3(0, 0.016, -0.082)
            n.addChildNode(nozzle)
        case "diagnostics":
            let pad = SCNNode(geometry: SCNBox(width: 0.150, height: 0.105, length: 0.011, chamferRadius: 0.006))
            pad.geometry?.firstMaterial = Mat.flat(0.09, 0.09, 0.10, rough: 0.4)
            pad.position = SCNVector3(0, 0.075, -0.055)
            pad.eulerAngles.x = -0.5
            n.addChildNode(pad)
            let sm = SCNMaterial()
            sm.diffuse.contents = UIColor(red: 0.05, green: 0.10, blue: 0.07, alpha: 1)
            sm.emission.contents = UIColor(red: 0.30, green: 0.95, blue: 0.45, alpha: 1)
            sm.emission.intensity = 0.9
            screenMat = sm
            let screen = SCNNode(geometry: SCNPlane(width: 0.132, height: 0.088))
            screen.geometry?.firstMaterial = sm
            screen.position = SCNVector3(0, 0.002, 0.0062)
            pad.addChildNode(screen)
        default:
            break
        }
        return n
    }

    // MARK: - requests (any thread)

    func requestEquip(_ tool: String, fromWorld: SCNVector3? = nil) {
        reqLock.lock(); pendingEquip = tool; pendingEquipWorld = fromWorld; reqLock.unlock()
    }
    func setWorking(_ on: Bool, tool: String?, atWorld: SCNVector3? = nil) {
        reqLock.lock(); pendingWorking = (on, tool, atWorld); reqLock.unlock()
    }

    // MARK: - per-frame update (render queue only)

    func update(dt: Float, move: Float, yawVel: Float, pitchVel: Float) {
        guard dt > 0 else { return }
        // clamp hitches (sim capture frames run 300-500ms): rejecting a slow
        // frame freezes the rig dead, a clamped step keeps it alive
        let dt = min(dt, 0.2)

        reqLock.lock()
        let eq = pendingEquip; pendingEquip = nil
        let eqWorld = pendingEquipWorld; pendingEquipWorld = nil
        let wk = pendingWorking; pendingWorking = nil
        reqLock.unlock()

        if let tool = eq {
            _equipTool = tool
            mode = .equip
            equipT = 0
            // pickup reach aims at the actual station tool when the caller
            // knows where it is, clamped to arm's length in camera space
            if let w = eqWorld, let cam = root.parent {
                var t = cam.convertPosition(w, from: nil)
                let L = sqrtf(t.x * t.x + t.y * t.y + t.z * t.z)
                if L > 0.55 { let s = 0.55 / L; t = SCNVector3(t.x * s, t.y * s, t.z * s) }
                equipLocalTarget = t
            } else { equipLocalTarget = nil }
        }
        if let w = wk {
            if w.on, let t = w.tool {
                if mode != .working { workTime = 0 }
                mode = .working
                workTool = t
                workTargetWorld = w.atWorld
                showTool(t)
            } else if mode == .working {
                mode = .idle
                workTargetWorld = nil
            }
        }

        // walk bob (ramped) + idle breath
        let targetAmp: Float = min(1, move)
        bobAmp += (targetAmp - bobAmp) * min(1, dt * 7)
        phase += dt * (2.2 + bobAmp * 7.5)

        // look sway: hand lags camera rotation
        let sx = max(-0.055, min(0.055, -yawVel * 0.050))
        let sy = max(-0.045, min(0.045, pitchVel * 0.038))
        let sm = min(1, dt * 9)
        swayX += (sx - swayX) * sm
        swayY += (sy - swayY) * sm

        sway.position = SCNVector3(
            cosf(phase * 0.5) * 0.007 * bobAmp + swayX,
            sinf(phase) * 0.010 * bobAmp + sinf(phase * 0.31) * 0.0025 + swayY,
            0)

        // mode behaviour
        var target = restPos
        var targetRot = restRot
        var targetToolRot = toolRotIdle
        switch mode {
        case .idle:
            wrist.eulerAngles = SCNVector3(0, 0, 0)
        case .equip:
            equipT += dt
            let T: Float = 0.85
            let p = min(1, equipT / T)
            // out-down toward the station, then back with the tool
            let out = equipLocalTarget ?? SCNVector3(0.0, -0.24, -0.40)
            let k: Float = p < 0.4 ? (p / 0.4) : (1 - (p - 0.4) / 0.6)
            let e = k * k * (3 - 2 * k) // smoothstep
            target = SCNVector3(restPos.x + (out.x - restPos.x) * e,
                                restPos.y + (out.y - restPos.y) * e,
                                restPos.z + (out.z - restPos.z) * e)
            targetRot = SCNVector3(restRot.x - 0.5 * e, restRot.y, restRot.z + 0.25 * e)
            if p >= 0.45, let tool = _equipTool { showTool(tool) }
            if p >= 1 { mode = .idle }
        case .working:
            workTime += dt
            // aim the hand at the actual part hotspot when the caller passed
            // its world position, clamped to a natural reach envelope so the
            // tool lands ON the part (wheel, door) instead of a fixed pose
            var aim: SCNVector3? = nil
            if let w = workTargetWorld, let cam = root.parent {
                var t = cam.convertPosition(w, from: nil)
                let L = sqrtf(t.x * t.x + t.y * t.y + t.z * t.z)
                let maxR: Float = 0.40
                if L > maxR { let sc = maxR / L; t = SCNVector3(t.x * sc, t.y * sc, t.z * sc) }
                if t.z > -0.20 { t.z = -0.20 }
                aim = t
            }
            switch workTool {
            case "wrench":
                target = aim ?? SCNVector3(0.03, -0.05, -0.33)
                targetRot = SCNVector3(-0.10, -0.18, 0.05)
                targetToolRot = toolRotIdle
                wrist.eulerAngles = SCNVector3(sinf(workTime * 6.5) * 0.42, 0, sinf(workTime * 6.5) * 0.10)
            case "screwdriver":
                // land the tilted TIP on the part, not the fist: with the
                // -0.75 tilt the tip sits ~0.10 below and ~0.12 beyond the
                // grip, so aim the grip above-and-closer than the hotspot
                if var a = aim { a.y += 0.10; a.z += 0.12; aim = a }
                target = aim ?? SCNVector3(0.02, -0.03, -0.31)
                targetRot = SCNVector3(-0.08, -0.35, 0.0)
                // shaft angled down-left so the tip meets the panel below
                // the fist and the chrome shaft reads against the paint
                targetToolRot = toolRotIdle
                wrist.eulerAngles = SCNVector3(sinf(workTime * 11) * 0.06, sinf(workTime * 11) * 0.30, 0)
            case "welder":
                target = aim ?? SCNVector3(0.02, -0.06, -0.40)
                targetRot = SCNVector3(-0.05, -0.25, 0.0)
                targetToolRot = toolRotIdle
                wrist.eulerAngles = SCNVector3(sinf(workTime * 23) * 0.022, sinf(workTime * 19) * 0.018, 0)
                updateArc(on: true, t: workTime)
            case "diagnostics":
                target = aim ?? SCNVector3(0.0, -0.07, -0.33)
                targetRot = SCNVector3(0.10, -0.10, 0.0)
                targetToolRot = toolRotIdle
                wrist.eulerAngles = SCNVector3(sinf(workTime * 1.8) * 0.03, 0, 0)
                screenMat?.emission.intensity = 0.7 + 0.4 * CGFloat(abs(sinf(workTime * 3)))
            default:
                break
            }
        }
        if mode != .working || workTool != "welder" { updateArc(on: false, t: 0) }
        if mode != .working || workTool != "diagnostics" { screenMat?.emission.intensity = 0.9 }

        // smooth toward target pose
        let f = min(1, dt * 9)
        pose.position = SCNVector3(
            pose.position.x + (target.x - pose.position.x) * f,
            pose.position.y + (target.y - pose.position.y) * f,
            pose.position.z + (target.z - pose.position.z) * f)
        pose.eulerAngles = SCNVector3(
            pose.eulerAngles.x + (targetRot.x - pose.eulerAngles.x) * f,
            pose.eulerAngles.y + (targetRot.y - pose.eulerAngles.y) * f,
            pose.eulerAngles.z + (targetRot.z - pose.eulerAngles.z) * f)
        let ntrx = toolRot.x + (targetToolRot.x - toolRot.x) * f
        let ntry_ = toolRot.y + (targetToolRot.y - toolRot.y) * f
        let ntrz = toolRot.z + (targetToolRot.z - toolRot.z) * f
        toolRot = SCNVector3(ntrx, ntry_, ntrz)
        toolAnchor.eulerAngles = toolRot
        //ADLOG logT += dt
        //ADLOG if logT >= 1 {
        //ADLOG     logT = 0
        //ADLOG     let m = mode == .idle ? 0 : (mode == .equip ? 1 : 2)
        //ADLOG     NSLog("[CFAUTODRIVE][CFHAND] mode=%ld tool=%@ pose=(%.3f,%.3f,%.3f) attached=%ld", m, currentTool ?? "-", Double(pose.position.x), Double(pose.position.y), Double(pose.position.z), root.parent == nil ? 0 : 1)
        //ADLOG }
    }

    // the equip request carries the tool id; stashed so the timeline can
    // reveal it mid-animation (hand closed -> tool appears)
    private var _equipTool: String?
    private var equipLocalTarget: SCNVector3?

    private func showTool(_ tool: String) {
        for (id, n) in toolNodes { n.isHidden = (id != tool) }
        currentTool = tool
        _equipTool = tool
        handRelax?.isHidden = true
        handGrip?.isHidden = false
    }

    // welder arc: small flickering light at the nozzle while welding
    private func updateArc(on: Bool, t: Float) {
        if on {
            if arcNode == nil, let welder = toolNodes["welder"] {
                let an = SCNNode()
                let l = SCNLight()
                l.type = .omni
                l.color = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1)
                l.attenuationStartDistance = 0.02
                l.attenuationEndDistance = 0.9
                an.light = l
                an.position = SCNVector3(0, 0.016, -0.115)
                welder.addChildNode(an)
                arcNode = an
                arcLight = l
            }
            arcLight?.intensity = CGFloat(500 + 450 * abs(sinf(t * 31)) + 150 * abs(sinf(t * 47)))
        } else {
            arcLight?.intensity = 0
        }
    }
}
