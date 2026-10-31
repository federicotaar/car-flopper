import Foundation
import SceneKit
import UIKit
import simd

// MARK: - First-person hand rig (camera-space view model)
//
// A skinned-mesh right hand + continuous forearm parented to the camera node, animated
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
    private let tipRef = SCNNode() // marker node at the active tool's physical working end
    private let forearmExt = SCNNode() // steered forearm tube (child of root, camera space)
    // toolAnchor-local positions of each tool's working end (wrench jaw
    // center, screwdriver bit end, welder nozzle end); the diagnostics pad
    // has no tip and skips tip correction
    private let tipLocal: [String: SCNVector3] = [
        "wrench": SCNVector3(0, 0.010, -0.172),
        "screwdriver": SCNVector3(0, 0.012, -0.160),
        "welder": SCNVector3(0, 0.012, -0.1495),
    ]
    private let toolAnchor = SCNNode()

    private var toolNodes: [String: SCNNode] = [:]
    private var handRelax: SCNNode?
    private var handGrip: SCNNode?
    private var narrowGripGeometry: SCNGeometry?
    private var narrowSqueezeGeometry: SCNGeometry?
    private var roundGripGeometry: SCNGeometry?
    private var roundSqueezeGeometry: SCNGeometry?
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
    private var workNormalWorld: SCNVector3?

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
    private let restPos = SCNVector3(0.150, -0.075, -0.360)
    private let restRot = SCNVector3(-1.571, -0.20, -0.45) // euler

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

                skin.isDoubleSided = true
        sleeveMat.isDoubleSided = true


        // mesh hand (CC0 human-hand, two baked poses) replaces the capsule
        // palm/fingers/thumb. relax = open hand; grip = closed fist around
        // the tool anchor. Mesh coords: fingers +y, palm -z, thumb -x;
        // rotated so fingers point forward (-z), palm down (-y).
        let handRelax = HandMeshAsset.node("relax", material: skin)
        let handGrip = HandMeshAsset.node("grip", material: skin)
        for h in [handRelax, handGrip] {
            h.eulerAngles.x = -.pi / 2
            h.scale = SCNVector3(1.0, 1.0, 1.0)
            h.position = SCNVector3(0, 0.0045, -0.006)
            wrist.addChildNode(h)
        }

        // A single loft replaces the old bent sleeve and separate extension.
        // Its first ring overlaps the measured skin wrist cross-section;
        // later rings follow a curved path out of the camera view.
        forearmExt.geometry = nil
        forearmExt.name = "continuous-forearm"
        root.addChildNode(forearmExt)
        forearmMaterial = sleeveMat
        // real finger flex: grip and relax share topology (8120 verts), so a
        // morpher blends them - the fingers visibly squeeze while working.
        // morpher is a property of the NODE (SCNNode.morpher), verified
        // against Apple's SceneKit docs (var morpher: SCNMorpher?)
        if let relaxGeo = HandMeshAsset.node("squeeze", material: skin).geometry {
            let m = SCNMorpher()
            m.targets = [relaxGeo]
            handGrip.morpher = m
        }
        narrowGripGeometry = handGrip.geometry
        narrowSqueezeGeometry = HandMeshAsset.node("squeeze", material: skin).geometry
        roundGripGeometry = HandMeshAsset.node("roundGrip", material: skin).geometry
        roundSqueezeGeometry = HandMeshAsset.node("roundSqueeze", material: skin).geometry
        handGrip.isHidden = true
        self.handRelax = handRelax
        self.handGrip = handGrip

        toolAnchor.position = SCNVector3(-0.030, 0.018, -0.090) // retained-grip channel, offline sample checked
        // tool presentation is per-state (see toolRot targets in update):
        // a forearm-axis tool is foreshortened to invisibility from the
        // first-person camera, so each state angles the shaft to read as a
        // diagonal without clipping the curled fingers
        toolAnchor.eulerAngles = toolRot
        wrist.addChildNode(toolAnchor)
        toolAnchor.addChildNode(tipRef)

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
        // the pad is gripped by its lower-left edge in the fist, screen to
        // camera (camera-space replica fit, variant f): it sits at the grip
        // anchor offset rather than on a separate wrist mount
        if let d = toolNodes["diagnostics"] {
            d.removeFromParentNode()
            wrist.addChildNode(d)
            d.position = SCNVector3(-0.030, 0.030, -0.1825)
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
            let head = SCNNode(geometry: SCNBox(width: 0.037, height: 0.011, length: 0.025, chamferRadius: 0.005))
            head.geometry?.firstMaterial = HandRig.toolChrome
            head.position = SCNVector3(0, 0.01, -0.146)
            n.addChildNode(head)
            // open-end jaw: two flat prongs angled apart, U gap between them
            for side: Float in [-1.0, 1.0] {
                let prong = SCNNode(geometry: SCNBox(width: 0.009, height: 0.010, length: 0.028, chamferRadius: 0.004))
                prong.geometry?.firstMaterial = HandRig.toolChrome
                prong.position = SCNVector3(0.014 * side, 0.01, -0.172)
                prong.eulerAngles.y = -0.12 * side
                n.addChildNode(prong)
            }
        case "screwdriver":
            let grip = SCNNode(geometry: SCNCapsule(capRadius: 0.0125, height: 0.092))
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
            let body = SCNNode(geometry: SCNCapsule(capRadius: 0.0125, height: 0.092))
            body.geometry?.firstMaterial = Mat.flat(0.10, 0.10, 0.11, rough: 0.7)
            body.eulerAngles.x = .pi / 2
            body.position = SCNVector3(0, 0.012, 0.0)
            n.addChildNode(body)
            let nozzle = SCNNode(geometry: SCNCylinder(radius: 0.007, height: 0.095))
            nozzle.geometry?.firstMaterial = Mat.flat(0.75, 0.45, 0.20, rough: 0.35, metal: 0.8)
            nozzle.eulerAngles.x = .pi / 2
            nozzle.position = SCNVector3(0, 0.012, -0.102)
            n.addChildNode(nozzle)
        case "diagnostics":
            // Rugged tablet carry handle. Its round crossbar shares the
            // finger channel; side struts clear both sides of the hand.
            let bar = SCNNode(geometry: SCNCylinder(radius: 0.006, height: 0.15))
            bar.eulerAngles.z = .pi / 2
            bar.position = SCNVector3(0, 0.0925, 0)
            bar.geometry?.firstMaterial = HandRig.toolSteelDark
            n.addChildNode(bar)
            for x: Float in [-0.070, 0.070] {
                let strut = SCNNode(geometry: SCNBox(width: 0.012, height: 0.050, length: 0.012, chamferRadius: 0.004))
                strut.position = SCNVector3(x, 0.0675, 0)
                strut.geometry?.firstMaterial = HandRig.toolSteelDark
                n.addChildNode(strut)
            }
            let pad = SCNNode(geometry: SCNBox(width: 0.150, height: 0.105, length: 0.011, chamferRadius: 0.006))
            pad.geometry?.firstMaterial = Mat.flat(0.09, 0.09, 0.10, rough: 0.4)
            pad.position = SCNVector3(0, 0, 0)
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

    func updateWorkTarget(_ p: SCNVector3, normal: SCNVector3?) {
        workTargetWorld = p
        workNormalWorld = normal
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

        let reachable: Bool = {
            guard let target = workTargetWorld, let cam = root.parent else { return false }
            let p = cam.convertPosition(target, from: nil)
            return sqrtf(p.x*p.x+p.y*p.y+p.z*p.z) <= 0.86
        }()

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
            var out = equipLocalTarget ?? SCNVector3(0.0, -0.09, -0.44)
            // Keep the grasp visible; the old dip buried the hand below the
            // screen exactly when the station tool switched into it.
            out.y = max(-0.09,min(0.08,out.y))
            out.z = min(-0.36,out.z)
            let k: Float = p < 0.4 ? (p / 0.4) : (1 - (p - 0.4) / 0.6)
            let e = k * k * (3 - 2 * k) // smoothstep
            target = SCNVector3(restPos.x + (out.x - restPos.x) * e,
                                restPos.y + (out.y - restPos.y) * e,
                                restPos.z + (out.z - restPos.z) * e)
            targetRot = SCNVector3(restRot.x - 0.15 * e, restRot.y, restRot.z + 0.10 * e)
            if p >= 0.45, let tool = _equipTool { showTool(tool) }
            if p >= 1 { mode = .idle }
        case .working:
            workTime += dt
            // The working end follows the live transformed surface point.
            var aim: SCNVector3? = nil
            if let w = workTargetWorld, let cam = root.parent {
                aim = cam.convertPosition(w, from: nil)
            }
            switch workTool {
            case "wrench":
                // sword grip: shaft along the fist bore, jaws land on the
                // aim (the part's marker ring, hugging the part). The wrist
                // pivots about the wrist->tip axis; the tip solve after smoothing corrects its current transformed point.
                if var a = aim { a.x += 0.141; a.y += 0.018; a.z += 0.196; aim = a }
                target = aim ?? SCNVector3(0.14, -0.03, -0.20)
                targetRot = SCNVector3(-1.571, -0.20, -0.45)
                targetToolRot = SCNVector3(0, Float.pi / 2, 0)
                setWorkPivot(tool: workTool, angle: sinf(workTime * 4.0) * 0.55)
            case "screwdriver":
                // Normal approach: shaft along the retained finger channel, bit on screw.
                // A small axial wrist turn reads as screw-turning; the closed-loop correction keeps the bit
                // tracking the ring on the panel.
                if var a = aim { a.x += 0.132; a.y += 0.012; a.z += 0.173; aim = a }
                target = aim ?? SCNVector3(0.13, -0.04, -0.22)
                targetRot = SCNVector3(-1.571, -0.20, -0.45)
                targetToolRot = SCNVector3(0, Float.pi / 2, 0)
                setWorkPivot(tool: workTool, angle: sinf(workTime * 3.5) * 0.35)
            case "welder":
                // torch points steeply down-forward: body visible on the fist
                // (contrast against skin, not navy sleeve), nozzle on the
                // seam. Small tip stir (6mm) + wrist tremor = live weld pool.
                if var a = aim { a.x += 0.069 + 0.006 * sinf(workTime * 2.3); a.y += 0.090 + 0.006 * cosf(workTime * 1.9); a.z += 0.128; aim = a }
                target = aim ?? SCNVector3(0.07, 0.04, -0.27)
                targetRot = SCNVector3(-1.571, -0.20, -0.45)
                targetToolRot = SCNVector3(0, Float.pi / 2, 0)
                setWorkPivot(tool: workTool, angle: sinf(workTime * 7.0) * 0.18)
                updateArc(on: true, t: workTime)
            case "diagnostics":
                target = SCNVector3(0.12, -0.03, -0.40)
                targetRot = SCNVector3(-1.571, -0.20, -0.45)
                targetToolRot = toolRotIdle
                wrist.eulerAngles = SCNVector3(sinf(workTime * 1.8) * 0.10, sinf(workTime * 1.1) * 0.06, 0)
                screenMat?.emission.intensity = 0.7 + 0.4 * CGFloat(abs(sinf(workTime * 3)))
            default:
                break
            }

        }
        if mode == .working, let g = handGrip?.morpher {
            // 0 = full grip; small relax pulse = visible finger squeeze,
            // two retained-grip poses, rather than the old open-hand target
            g.setWeight(CGFloat(max(0, 1.0 * (0.5 + 0.5 * sinf(workTime * 3.5)))), forTargetAt: 0)
        } else {
            handGrip?.morpher?.setWeight(0, forTargetAt: 0)
        }
        if mode != .working || workTool != "welder" { updateArc(on: false, t: 0) }
        if mode != .working || workTool != "diagnostics" { screenMat?.emission.intensity = 0.9 }

        // Never grow a distant work pose while the stance is settling.
        if mode == .working, workTool != "diagnostics", !reachable {
            target = restPos; targetRot = restRot
        }
        // smooth toward target pose
        let f = min(1, dt * 9)
        pose.position = SCNVector3(
            pose.position.x + (target.x - pose.position.x) * f,
            pose.position.y + (target.y - pose.position.y) * f,
            pose.position.z + (target.z - pose.position.z) * f)
        if mode == .working, reachable, workTool != "diagnostics", let normal = workNormalWorld,
           let parent = pose.parent {
            let n = parent.convertVector(normal, from: nil)
            let outward = simd_normalize(SIMD3<Float>(n.x,n.y,n.z))
            var x: SIMD3<Float>, y: SIMD3<Float>, z: SIMD3<Float>
            if workTool == "wrench" {
                var shaft = SIMD3<Float>(-0.35,0.85,0)
                shaft -= outward * simd_dot(shaft,outward)
                shaft = simd_normalize(shaft)
                x = -shaft; y = outward
                z = simd_normalize(simd_cross(x,y)); x = simd_cross(y,z)
            } else {
                var inward = -outward
                if workTool == "welder" {
                    var tangent = SIMD3<Float>(0.8,0,-0.25)
                    tangent -= outward * simd_dot(tangent,outward)
                    tangent = simd_normalize(tangent)
                    inward = simd_normalize(inward * 0.82 + tangent * 0.57)
                }
                x = -inward; z = SIMD3<Float>(0.55,-0.35,0.25)
                z -= x * simd_dot(z,x)
                if simd_length(z) < 0.01 { z = SIMD3<Float>(0,0,1) }
                z = simd_normalize(z); y = simd_normalize(simd_cross(z,x))
            }
            let frame = simd_quatf(simd_float3x3(columns:(x,y,z)))
            let roll: Float = 0
            let desired = frame * simd_quatf(angle:roll,axis:SIMD3<Float>(1,0,0))
            pose.simdOrientation = simd_slerp(pose.simdOrientation, desired, f)
        } else {
            pose.eulerAngles = SCNVector3(
                pose.eulerAngles.x + (targetRot.x - pose.eulerAngles.x) * f,
                pose.eulerAngles.y + (targetRot.y - pose.eulerAngles.y) * f,
                pose.eulerAngles.z + (targetRot.z - pose.eulerAngles.z) * f)
        }
        let ntrx = toolRot.x + (targetToolRot.x - toolRot.x) * f
        let ntry_ = toolRot.y + (targetToolRot.y - toolRot.y) * f
        let ntrz = toolRot.z + (targetToolRot.z - toolRot.z) * f
        toolRot = SCNVector3(ntrx, ntry_, ntrz)
        toolAnchor.eulerAngles = toolRot
        // relax the work-motion pivot when not repairing
        if mode != .working {
            wrist.eulerAngles = SCNVector3(wrist.eulerAngles.x * (1 - f), wrist.eulerAngles.y * (1 - f), wrist.eulerAngles.z * (1 - f))
        }
        // Solve the current transformed physical tip after pose/tool smoothing.
        // This deliberately does not project distant targets onto a camera-space
        // reach sphere. Engine pixels must validate visual reach and contact.
        if mode == .working, reachable, workTool != "diagnostics", let w = workTargetWorld,
           let parent = pose.parent {
            let goal = parent.convertPosition(w, from: nil)
            let tip = tipRef.convertPosition(SCNVector3Zero, to: parent)
            pose.position = SCNVector3(pose.position.x + goal.x - tip.x,
                                       pose.position.y + goal.y - tip.y,
                                       pose.position.z + goal.z - tip.z)
        }
        updateForearmExt()
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
        let round = tool == "screwdriver" || tool == "welder"
        if currentTool != tool, let h = handGrip {
            h.geometry = round ? roundGripGeometry : narrowGripGeometry
            let morph = SCNMorpher()
            if let target = round ? roundSqueezeGeometry : narrowSqueezeGeometry { morph.targets = [target] }
            h.morpher = morph
        }
        toolAnchor.position = round ? SCNVector3(-0.030, 0.01241956, -0.08849529) : SCNVector3(-0.030,0.018,-0.090)
        tipRef.position = tipLocal[tool] ?? SCNVector3Zero
        currentTool = tool
        _equipTool = tool
        handRelax?.isHidden = true
        handGrip?.isHidden = false
    }

    private var forearmMaterial: SCNMaterial?
    private func setWorkPivot(tool: String, angle: Float) {
        guard tipLocal[tool] != nil else { return }
        // Work motion turns about the actual shaft direction. The separate
        // physical-tip solve translates its end back onto the live surface.
        let d = tool == "wrench" ? SCNVector3(0,1,0) : toolAnchor.convertVector(SCNVector3(0,0,-1), to: wrist)
        let v = simd_normalize(SIMD3<Float>(d.x,d.y,d.z))
        wrist.rotation = SCNVector4(v.x,v.y,v.z,angle)
    }
    private func updateForearmExt() {
        let nr = 28, ns = 40
        let cuff = SCNVector3(-0.022, 0.048, -0.037)
        let c = wrist.convertPosition(cuff, to: root)
        let c0 = SIMD3<Float>(c.x,c.y,c.z)
        let vz = wrist.convertVector(SCNVector3(0,0,1), to: root)
        let tangent = simd_normalize(SIMD3<Float>(vz.x,vz.y,vz.z))
        // Solve an elbow from upper-arm/forearm lengths and a body-side
        // shoulder, then connect both segments. Never terminate a tube in view.
        let shoulder = SIMD3<Float>(0.20,-0.20,0.14)
        let delta = shoulder-c0
        let distance = max(0.031,min(0.565,simd_length(delta)))
        let axis = simd_normalize(delta)
        let along = (0.27*0.27-0.30*0.30+distance*distance)/(2*distance)
        let height = sqrtf(max(0.0001,0.27*0.27-along*along))
        var bend = SIMD3<Float>(0.8,-1,0.1)
        bend -= axis * simd_dot(bend,axis)
        bend = simd_normalize(bend)
        let elbow = c0+axis*along+bend*height
        let c1 = c0+tangent*0.055
        let c2 = elbow-(elbow-c0)*0.18
        let vx = wrist.convertVector(SCNVector3(1,0,0), to: root)
        let vy = wrist.convertVector(SCNVector3(0,1,0), to: root)
        let ux = SIMD3<Float>(vx.x,vx.y,vx.z)
        let uy = SIMD3<Float>(vy.x,vy.y,vy.z)
        var vertices = [SCNVector3](), normals = [SCNVector3](), indices = [Int32]()
        for j in 0...ns {
            let t = Float(j) / Float(ns)
            let center: SIMD3<Float>, der: SIMD3<Float>
            if t <= 0.62 {
                let u = t/0.62, b = 1-u
                center = c0*(b*b*b)+c1*(3*b*b*u)+c2*(3*b*u*u)+elbow*(u*u*u)
                der = (c1-c0)*(3*b*b)+(c2-c1)*(6*b*u)+(elbow-c2)*(3*u*u)
            } else {
                let u = (t-0.62)/0.38, b = 1-u
                let ua = elbow+(elbow-c2)*0.5, ub = shoulder+(elbow-shoulder)*0.20
                center = elbow*(b*b*b)+ua*(3*b*b*u)+ub*(3*b*u*u)+shoulder*(u*u*u)
                der = (ua-elbow)*(3*b*b)+(ub-ua)*(6*b*u)+(shoulder-ub)*(3*u*u)
            }
            let q = simd_quatf(from: tangent, to: simd_normalize(der))
            let keys: [Float] = [0,0.08,0.25,0.5,0.62,0.75,1]
            let sizes: [Float] = [1,1.02,1.18,1.32,1.25,1.50,1.8]
            let k = min(keys.count-2, (0..<(keys.count-1)).first { t <= keys[$0+1] } ?? keys.count-2)
            let blend = (t-keys[k])/(keys[k+1]-keys[k])
            let scale = sizes[k] + (sizes[k+1]-sizes[k])*blend
            for i in 0..<nr {
                let ang = Float(i) * 2 * Float.pi / Float(nr)
                let radial = q.act(ux * (0.035*cosf(ang)) + uy * (0.021*sinf(ang)))
                let fold = (0.035*sinf(t*35+ang*2) + 0.02*sinf(t*61-ang*3))*sinf(Float.pi*t)
                let v = center + radial * (scale+fold)
                let n = simd_normalize(radial)
                vertices.append(SCNVector3(v.x,v.y,v.z)); normals.append(SCNVector3(n.x,n.y,n.z))
                if j > 0 {
                    let a = Int32((j-1)*nr+i), b = Int32((j-1)*nr+(i+1)%nr)
                    let c = Int32(j*nr+(i+1)%nr), d = Int32(j*nr+i)
                    indices += [a,b,c,a,c,d]
                }
            }
        }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                              elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        if let m = forearmMaterial { geo.materials = [m] }
        forearmExt.geometry = geo
    }

    // welder arc: small flickering light at the nozzle while welding
    private func updateArc(on: Bool, t: Float) {
        if on {
            if arcNode == nil {
                let an = SCNNode()
                let l = SCNLight()
                l.type = .omni
                l.color = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1)
                l.attenuationStartDistance = 0.02
                l.attenuationEndDistance = 0.9
                an.light = l
                let pool = SCNSphere(radius:0.008)
                pool.segmentCount = 12
                let glow = SCNMaterial()
                glow.lightingModel = .constant
                glow.diffuse.contents = UIColor(red:0.70,green:0.87,blue:1,alpha:1)
                glow.emission.contents = UIColor(red:0.45,green:0.72,blue:1,alpha:1)
                glow.emission.intensity = 2.5
                pool.firstMaterial = glow
                an.geometry = pool
                // Pool follows the physical surface, offset outward along its
                // current world normal. It is not attached behind the nozzle cap.
                an.position = SCNVector3Zero
                for i in 0..<5 {
                    let spark = SCNNode(geometry:SCNSphere(radius:0.0012))
                    spark.geometry?.firstMaterial = glow
                    let a = Float(i) * 2 * Float.pi / 5
                    spark.position = SCNVector3(cosf(a)*0.010,sinf(a)*0.010,0.004)
                    an.addChildNode(spark)
                }
                root.addChildNode(an)
                arcNode = an
                arcLight = l
            }
            if let point = workTargetWorld, let normal = workNormalWorld {
                let n = simd_normalize(SIMD3<Float>(normal.x,normal.y,normal.z))
                let exposed = SCNVector3(point.x+n.x*0.008,point.y+n.y*0.008,point.z+n.z*0.008)
                arcNode?.position = root.convertPosition(exposed, from:nil)
                let localNormal = root.convertVector(normal, from:nil)
                let axis = simd_normalize(SIMD3<Float>(localNormal.x,localNormal.y,localNormal.z))
                arcNode?.simdOrientation = simd_quatf(from:SIMD3<Float>(0,0,1),to:axis)
            }
            arcNode?.isHidden = false
            let pulse = 0.8 + 0.25 * abs(sinf(t * 31))
            arcNode?.scale = SCNVector3(pulse,pulse,pulse)
            arcLight?.intensity = CGFloat(500 + 450 * abs(sinf(t * 31)) + 150 * abs(sinf(t * 47)))
        } else {
            arcLight?.intensity = 0
            arcNode?.isHidden = true
        }
    }
}
