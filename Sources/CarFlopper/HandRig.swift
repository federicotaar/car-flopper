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
    private let fingers = SCNNode()
    private let toolAnchor = SCNNode()

    private var toolNodes: [String: SCNNode] = [:]
    private var currentTool: String? = nil
    private var screenMat: SCNMaterial?
    private var arcLight: SCNLight?
    private var arcNode: SCNNode?

    // cross-thread requests (main -> render), consumed in update
    private let reqLock = NSLock()
    private var pendingEquip: String?
    private var pendingWorking: (on: Bool, tool: String?)?

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

    init() {
        build()
    }

    private func build() {
        root.addChildNode(sway)
        sway.addChildNode(pose)
        pose.addChildNode(wrist)

        let skin = Mat.flat(0.87, 0.63, 0.50, rough: 0.6)
        let skinDark = Mat.flat(0.78, 0.54, 0.42, rough: 0.65)
        let sleeveMat = Mat.flat(0.16, 0.19, 0.26, rough: 0.95)

        // forearm receding to the lower-right edge of the frame
        let forearm = SCNNode(geometry: SCNCapsule(capRadius: 0.027, height: 0.24))
        forearm.geometry?.firstMaterial = skin
        forearm.position = SCNVector3(0.055, -0.085, 0.105)
        forearm.eulerAngles = SCNVector3(-1.05, 0.22, -0.30)
        wrist.addChildNode(forearm)
        let sleeve = SCNNode(geometry: SCNCapsule(capRadius: 0.033, height: 0.13))
        sleeve.geometry?.firstMaterial = sleeveMat
        sleeve.position = SCNVector3(0.095, -0.155, 0.185)
        sleeve.eulerAngles = SCNVector3(-1.05, 0.22, -0.30)
        wrist.addChildNode(sleeve)

        // palm
        let palmGeo = SCNBox(width: 0.082, height: 0.030, length: 0.095, chamferRadius: 0.013)
        palmGeo.firstMaterial = skin
        let palm = SCNNode(geometry: palmGeo)
        wrist.addChildNode(palm)

        // fingers: 4 two-segment capsules along the front edge, curled for a grip
        fingers.position = SCNVector3(0, -0.002, -0.046)
        wrist.addChildNode(fingers)
        let fx: [Float] = [-0.030, -0.010, 0.010, 0.030]
        for i in 0..<4 {
            let base = SCNNode()
            base.position = SCNVector3(fx[i], 0, 0)
            base.eulerAngles.x = -0.55 // curl toward grip
            let prox = SCNNode(geometry: SCNCapsule(capRadius: 0.0092, height: 0.030))
            prox.geometry?.firstMaterial = skin
            prox.eulerAngles.x = .pi / 2
            prox.position = SCNVector3(0, 0, -0.012)
            base.addChildNode(prox)
            let tipNode = SCNNode()
            tipNode.position = SCNVector3(0, -0.024, -0.010)
            tipNode.eulerAngles.x = -0.85
            let tip = SCNNode(geometry: SCNCapsule(capRadius: 0.0084, height: 0.026))
            tip.geometry?.firstMaterial = skinDark
            tip.eulerAngles.x = .pi / 2
            tip.position = SCNVector3(0, 0, -0.010)
            tipNode.addChildNode(tip)
            base.addChildNode(tipNode)
            fingers.addChildNode(base)
        }
        // thumb opposing the grip
        let thumb = SCNNode(geometry: SCNCapsule(capRadius: 0.0098, height: 0.036))
        thumb.geometry?.firstMaterial = skin
        thumb.position = SCNVector3(-0.046, -0.010, -0.018)
        thumb.eulerAngles = SCNVector3(-0.5, 0.0, 0.9)
        wrist.addChildNode(thumb)

        toolAnchor.position = SCNVector3(0, -0.016, -0.055)
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
            let shaft = SCNNode(geometry: SCNCylinder(radius: 0.0065, height: 0.150))
            shaft.geometry?.firstMaterial = HandRig.toolChrome
            shaft.eulerAngles.x = .pi / 2
            shaft.position = SCNVector3(0, 0.01, -0.045)
            n.addChildNode(shaft)
            let head = SCNNode(geometry: SCNBox(width: 0.030, height: 0.011, length: 0.046, chamferRadius: 0.005))
            head.geometry?.firstMaterial = HandRig.toolChrome
            head.position = SCNVector3(0, 0.01, -0.125)
            n.addChildNode(head)
            let jaw = SCNNode(geometry: SCNTorus(ringRadius: 0.016, pipeRadius: 0.006))
            jaw.geometry?.firstMaterial = HandRig.toolChrome
            jaw.position = SCNVector3(0, 0.01, -0.146)
            n.addChildNode(jaw)
        case "screwdriver":
            let grip = SCNNode(geometry: SCNCapsule(capRadius: 0.011, height: 0.075))
            grip.geometry?.firstMaterial = Mat.flat(0.80, 0.18, 0.12, rough: 0.5)
            grip.eulerAngles.x = .pi / 2
            grip.position = SCNVector3(0, 0.012, 0.005)
            n.addChildNode(grip)
            let shaft = SCNNode(geometry: SCNCylinder(radius: 0.0038, height: 0.095))
            shaft.geometry?.firstMaterial = HandRig.toolChrome
            shaft.eulerAngles.x = .pi / 2
            shaft.position = SCNVector3(0, 0.012, -0.075)
            n.addChildNode(shaft)
            let tip = SCNNode(geometry: SCNCone(topRadius: 0.001, bottomRadius: 0.0042, height: 0.014))
            tip.geometry?.firstMaterial = HandRig.toolSteelDark
            tip.eulerAngles.x = -.pi / 2
            tip.position = SCNVector3(0, 0.012, -0.128)
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

    func requestEquip(_ tool: String) {
        reqLock.lock(); pendingEquip = tool; reqLock.unlock()
    }
    func setWorking(_ on: Bool, tool: String?) {
        reqLock.lock(); pendingWorking = (on, tool); reqLock.unlock()
    }

    // MARK: - per-frame update (render queue only)

    func update(dt: Float, move: Float, yawVel: Float, pitchVel: Float) {
        guard dt > 0 else { return }
        // clamp hitches (sim capture frames run 300-500ms): rejecting a slow
        // frame freezes the rig dead, a clamped step keeps it alive
        let dt = min(dt, 0.2)

        reqLock.lock()
        let eq = pendingEquip; pendingEquip = nil
        let wk = pendingWorking; pendingWorking = nil
        reqLock.unlock()

        if let tool = eq {
            _equipTool = tool
            mode = .equip
            equipT = 0
        }
        if let w = wk {
            if w.on, let t = w.tool {
                if mode != .working { workTime = 0 }
                mode = .working
                workTool = t
                showTool(t)
            } else if mode == .working {
                mode = .idle
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
        switch mode {
        case .idle:
            wrist.eulerAngles = SCNVector3(0, 0, 0)
        case .equip:
            equipT += dt
            let T: Float = 0.85
            let p = min(1, equipT / T)
            // out-down toward the station, then back with the tool
            let out = SCNVector3(0.0, -0.24, -0.40)
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
            switch workTool {
            case "wrench":
                target = SCNVector3(0.03, -0.05, -0.33)
                targetRot = SCNVector3(-0.10, -0.18, 0.05)
                wrist.eulerAngles = SCNVector3(sinf(workTime * 6.5) * 0.42, 0, sinf(workTime * 6.5) * 0.10)
            case "screwdriver":
                target = SCNVector3(0.02, -0.03, -0.31)
                targetRot = SCNVector3(-0.08, -0.35, 0.0)
                wrist.eulerAngles = SCNVector3(sinf(workTime * 11) * 0.06, sinf(workTime * 11) * 0.30, 0)
            case "welder":
                target = SCNVector3(0.02, -0.06, -0.40)
                targetRot = SCNVector3(-0.05, -0.25, 0.0)
                wrist.eulerAngles = SCNVector3(sinf(workTime * 23) * 0.022, sinf(workTime * 19) * 0.018, 0)
                updateArc(on: true, t: workTime)
            case "diagnostics":
                target = SCNVector3(0.0, -0.07, -0.33)
                targetRot = SCNVector3(0.10, -0.10, 0.0)
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

    private func showTool(_ tool: String) {
        for (id, n) in toolNodes { n.isHidden = (id != tool) }
        currentTool = tool
        _equipTool = tool
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
