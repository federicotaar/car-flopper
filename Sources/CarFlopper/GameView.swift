import SwiftUI
import SceneKit
import simd

// MARK: - In-game view: SceneKit canvas + joystick + repair button + HUD.

struct GameView: View {
    @ObservedObject var vm: GameViewModel
    var onLeave: () -> Void

    private func autoDriveGame() {
        #if AUTODRIVE
        let adArgs = ProcessInfo.processInfo.arguments
        guard adArgs.contains("-CFAutoDrive") else { return }
        // -CFAutoDriveDebug adds the on-screen overlay; keep preview captures clean
        let adDebug = adArgs.contains("-CFAutoDriveDebug")
        NSLog("[CFAUTODRIVE] garage appeared")
        if adArgs.contains("-CFAutoDriveRepair") {
            // freeze-regression mode: exercise BOTH loops Fred reported -
            // a diagnostics-tablet fix (engine) and an ordinary tool fix -
            // each: equip at the station, hold fix, assert progress flows and
            // the part completes. A 1s heartbeat makes a wedged renderer or
            // main thread visible as missing beats.
            var hb = 0
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                hb += 1
                NSLog("[CFREPAIR] heartbeat %d", hb)
            }
            // round state: 0 idle, 1 walking to station, 2 holding fix, 3 done
            var round = 0
            var targetPart: String? = nil
            var roundLabel = ""
            var roundIndex = 0
            let plan: [(stationTool: String, partId: String, label: String)] = [
                ("diagnostics", "engine", "diagnostics round"),
                ("wrench", "", "repair round"),   // part resolved at hold time
                ("screwdriver", "", "screwdriver round"),
            ]
            // camera convention: view dir is (-sin yaw, 0, -cos yaw), so facing
            // (dx,dz) needs yaw = atan2(-dx,-dz) - the old atan2(dx,dz) pointed
            // the capture exactly AWAY from the part, at the garage walls
            func faceTarget(_ tx: Float, _ tz: Float, from fx: Float, _ fz: Float, pitch: Float?) {
                vm.sceneCtrl.cameraYaw = atan2f(fx - tx, fz - tz)
                vm.sceneCtrl.cameraPitchOverride = pitch
            }
            func startRound(_ i: Int) {
                guard i < plan.count else { return }
                let r = plan[i]
                roundLabel = r.label
                round = 1
                guard let st = GameContent.toolStations.first(where: { $0.tool == r.stationTool }) ?? GameContent.toolStations.first(where: { $0.tool != plan[0].stationTool }) else { NSLog("[CFREPAIR] FAIL no station for \(r.stationTool)"); return }
                NSLog("[CFREPAIR] \(roundLabel): stepping into \(r.stationTool) station")
                // stand back toward the garage center (still inside pickup
                // reach) facing the station, so the equip reach is on camera
                let sl = max(0.001, hypotf(st.x, st.z))
                let spx = st.x - st.x / sl * 0.85
                let spz = st.z - st.z / sl * 0.85
                vm.sceneCtrl.localPosition = SCNVector3(spx, 0, spz)
                faceTarget(st.x, st.z, from: spx, spz, pitch: -0.30)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    // stations sit within pickup reach of each other on the
                    // bench, so accept whichever tool the proximity tick
                    // equipped; the round exercises a non-diagnostics repair
                    guard let tool = vm.heldTool else { NSLog("[CFREPAIR] FAIL no tool equipped for \(roundLabel)"); return }
                    let defs = vm.sceneCtrl.car?.def.parts ?? []
                    let part = r.partId.isEmpty ? defs.first(where: { $0.tool == tool && (vm.parts[$0.id]?.progress ?? 0) < 1 }) : defs.first(where: { $0.id == r.partId })
                    guard let part else { NSLog("[CFREPAIR] FAIL no part for \(roundLabel)"); return }
                    targetPart = part.id
                    round = 2
                    // stand OUTSIDE the car relative to the part: +0.5,+0.5 can
                    // land nearer a different broken part (exhaust vs wheelRR)
                    // and the wrong-tool flash then silently blocks the hold
                    let away: Float = 1.0
                    let len = max(0.001, hypotf(part.x, part.z))
                    let px = part.x + part.x / len * away
                    let pz = part.z + part.z / len * away
                    vm.sceneCtrl.localPosition = SCNVector3(px, 0, pz)
                    // face the part and pitch down to its hotspot height so the
                    // hold shows the hand working on the part in view
                    faceTarget(part.x, part.z, from: px, pz, pitch: -atan2f(1.32 - part.y, away + 0.35))
                    NSLog("[CFREPAIR] \(roundLabel): holding fix on \(part.id)")
                    vm.setRepairing(true)
                }
            }
            var progressSeen = false
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
                if !progressSeen, let id = targetPart, (vm.parts[id]?.progress ?? 0) > 0 {
                    progressSeen = true
                    NSLog("[CFREPAIR] \(roundLabel): progress flowing")
                }
                if round == 2, let id = targetPart, (vm.parts[id]?.progress ?? 0) >= 1 {
                    vm.setRepairing(false)
                    NSLog("[CFREPAIR] \(roundLabel) OK")
                    targetPart = nil
                    progressSeen = false
                    round = 3
                    vm.sceneCtrl.cameraPitchOverride = nil
                    roundIndex += 1
                    if roundIndex < plan.count {
                        startRound(roundIndex)
                    } else {
                        NSLog("[CFREPAIR] all rounds OK")
                        t.invalidate()
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { startRound(0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 115.0) {
                NSLog("[CFREPAIR] TIMEOUT FAIL round=\(round) part=\(targetPart ?? "-")")
            }
            return
        }
        // showcase orbit: closed-loop strafe around the car through the normal
        // joystick movement pipeline (moveLocal clamps, heading, network sync),
        // facing the car the whole time. Player position changes continuously
        // across every capture: real walking, not just a camera pan.
        // phase 0: closed-loop orbit (walking proof). phases 1/2/3: park at
        // front-left, front-right and rear so captures cover the whole car.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            NSLog("[CFAUTODRIVE] orbit start")
            var phase = 0
            var lastP = vm.sceneCtrl.localPosition
            var stuckTicks = 0
            var tick = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { phase = 1; NSLog("[CFAUTODRIVE] park front-left") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 50.0) { phase = 2; NSLog("[CFAUTODRIVE] park front-right") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 70.0) { phase = 3; NSLog("[CFAUTODRIVE] park rear") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 82.0) { phase = 4; NSLog("[CFAUTODRIVE] swing around right side") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 94.0) { phase = 5; NSLog("[CFAUTODRIVE] bay close-up") }
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let p = vm.sceneCtrl.localPosition
                tick += 1
                if tick % 30 == 0 { NSLog("[CFAUTODRIVE] tick %d pos %.2f %.2f phase %d", tick, p.x, p.z, phase) }
                if adDebug && tick % 10 == 0 {
                    vm.autodriveDebug = String(format: "AD t%.0fs pos(%.2f,%.2f) ph%d", Double(tick)/10.0, p.x, p.z, phase)
                }
                let moved = hypotf(p.x - lastP.x, p.z - lastP.z)
                let pushing = vm.sceneCtrl.joystickVector.dx != 0 || vm.sceneCtrl.joystickVector.dy != 0
                if pushing && moved < 0.01 { stuckTicks += 1 } else { stuckTicks = 0 }
                lastP = p
                if stuckTicks > 5 {
                    // grinding an obstacle (collision stops translation while the
                    // stick keeps pushing): back straight off, then resume
                    let back = CGVector(dx: 0, dy: 0.85)
                    if vm.sceneCtrl.joystickVector != back { vm.sceneCtrl.joystickVector = back }
                    if stuckTicks > 12 { stuckTicks = 0 }
                    return
                }
                if phase == 0 {
                    // face the car center: camera forward is (-sin yaw, -cos yaw)
                    vm.sceneCtrl.cameraYaw = atan2f(p.x, p.z)
                    // keep orbit radius in [2.9, 3.4] so we never grind the car or the walls
                    let r = hypotf(p.x, p.z)
                    let inward: Float = r > 3.4 ? 0.35 : (r < 2.9 ? -0.35 : 0.0)
                    let nj = CGVector(dx: 0.7, dy: Double(-inward))
                    // write-on-change: constant @Published churn at 10 Hz forces
                    // SwiftUI re-evaluation around the SCNView every tick
                    if vm.sceneCtrl.joystickVector != nj { vm.sceneCtrl.joystickVector = nj }
                } else {
                    let t: (Float, Float) = phase == 1 ? (-1.7, 3.1) : (phase == 2 ? (1.7, 3.1) : (phase == 3 ? (0, -3.4) : (phase == 4 ? (2.6, -1.5) : (1.30, 2.20))))
                    let dx = t.0 - p.x, dz = t.1 - p.z
                    let d = hypotf(dx, dz)
                    if d > 0.18 {
                        // walk toward the parking spot (camera-relative movement)
                        vm.sceneCtrl.cameraYaw = atan2f(-dx, -dz)
                        let fwd = CGVector(dx: 0, dy: -0.55)
                        if vm.sceneCtrl.joystickVector != fwd { vm.sceneCtrl.joystickVector = fwd }
                    } else {
                        // parked: face the car
                        if vm.sceneCtrl.joystickVector != .zero { vm.sceneCtrl.joystickVector = .zero }
                        if phase == 5 {
                            // engine-bay close-up: standing at the right fender (a pose any
                            // player reaches with the stick), looking down into the bay
                            vm.sceneCtrl.cameraYaw = atan2f(p.x - 0, p.z - 1.30)
                            vm.sceneCtrl.cameraPitchOverride = -0.48
                        } else {
                            vm.sceneCtrl.cameraYaw = atan2f(p.x, p.z)
                        }
                    }
                }
            }
        }
        #endif
    }

    var body: some View {
        ZStack {
            SceneViewBridge(controller: vm.sceneCtrl)
                .ignoresSafeArea()
                .onAppear { autoDriveGame() }

            VStack {
                hud
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(spacing: 6) {
                        JoystickView { v in vm.sceneCtrl.joystickVector = v }
                            .frame(width: 130, height: 130)
                        toolChip
                    }
                    .padding(.leading, 24)
                    Spacer()
                    repairButton
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 34)
            }

            // first-person crosshair
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 5, height: 5)
                .shadow(color: .black.opacity(0.6), radius: 2)

            if let toast = vm.toolToast {
                VStack {
                    Spacer()
                    Text(toast.uppercased())
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
            }

            if vm.phase == "complete" {
                completionOverlay
            }

            #if AUTODRIVE
            if !vm.autodriveDebug.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Text(vm.autodriveDebug)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.65))
                        Spacer()
                    }
                }
                .padding(.bottom, 4).padding(.leading, 6)
                .allowsHitTesting(false)
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.25), value: vm.toolToast)
        .background(Color.black)
    }

    private var hud: some View {
        VStack(spacing: 6) {
            HStack {
                Text(vm.roomCode)
                    .font(.system(.headline, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                Spacer()
                Text(vm.carName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
                Spacer()
                Button(action: onLeave) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(10)
                        .background(.black.opacity(0.6), in: Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ProgressView(value: vm.totalProgress)
                .tint(.green)
                .padding(.horizontal, 40)

            Text("\(vm.fixedCount)/\(vm.totalCount) parts fixed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var toolChip: some View {
        if let held = vm.heldTool, let td = GameContent.tools[held] {
            Label(td.label, systemImage: td.symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(uiColor: td.color).opacity(0.85), in: Capsule())
        } else {
            Label("Hands - find a tool", systemImage: "hand.raised.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.gray.opacity(0.6), in: Capsule())
        }
    }

    @ViewBuilder
    private var repairButton: some View {
        if let part = vm.activePart {
            let td = GameContent.tools[part.tool]
            let hasTool = vm.heldTool == part.tool
            VStack(spacing: 8) {
                Text(part.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background((hasTool ? Color.orange : Color.gray).opacity(0.85), in: Capsule())
                ProgressView(value: vm.activePartProgress)
                    .tint(.orange)
                    .frame(width: 90)
                Text(vm.isRepairing ? "FIXING..." : (hasTool ? "HOLD TO FIX" : "NEED \(td?.label.uppercased() ?? "TOOL")"))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(vm.wrongToolFlash ? Color.red : Color.white.opacity(0.9))
                Image(systemName: td?.symbol ?? "wrench.and.screwdriver.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                    .background(vm.isRepairing ? Color.green : (hasTool ? Color.orange : Color.gray), in: Circle())
                    .shadow(radius: 8)
                    .scaleEffect(vm.wrongToolFlash ? 0.92 : 1.0)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in vm.setRepairing(true) }
                            .onEnded { _ in vm.setRepairing(false) }
                    )
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    private var completionOverlay: some View {
        VStack(spacing: 16) {
            Text("CAR FIXED!")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.green)
            Text(vm.carName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            if vm.nextCarLocked {
                Text("All cars restored - you own the garage!")
                    .foregroundStyle(.yellow)
            } else {
                Text("Unlocked: \(vm.nextCarName)")
                    .foregroundStyle(.yellow)
            }
            if vm.isHost {
                if !vm.nextCarLocked {
                    Button("NEXT CAR") { vm.advanceCar() }
                        .font(.headline.weight(.heavy))
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(.green, in: Capsule())
                        .foregroundStyle(.black)
                }
            } else {
                Text("waiting for host...")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(28)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - SceneKit bridge with camera + render loop

struct SceneViewBridge: UIViewRepresentable {
    let controller: GameSceneController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = controller.scene
        v.backgroundColor = .black
#if targetEnvironment(simulator)
        // simulator renders in software: keep the scene content identical but
        // lower the throughput cost so CI can capture real frames. AA off:
        // multisampling is the top software-rasterizer cost and a stalled
        // renderer freezes the whole showcase
        v.antialiasingMode = .none
        v.preferredFramesPerSecond = 30
#else
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
#endif
        v.delegate = context.coordinator
        v.isPlaying = true

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 68
        cam.camera?.zNear = 0.05
        cam.camera?.zFar = 60
        // filmic-ish response: HDR + gentle bloom + vignette
        cam.camera?.wantsHDR = true
        cam.camera?.wantsExposureAdaptation = true
        cam.camera?.bloomThreshold = 0.85
        cam.camera?.bloomIntensity = 0.7
        cam.camera?.bloomBlurRadius = 8
        cam.camera?.saturation = 1.08
        cam.camera?.contrast = 1.06
        cam.camera?.vignettingPower = 1.1
        cam.camera?.vignettingIntensity = 0.4
        v.pointOfView = cam
        context.coordinator.camNode = cam
        controller.attachHandIfNeeded(to: cam)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        // one finger steers the camera; the other thumb keeps the joystick
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    final class Coordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
        let controller: GameSceneController
        weak var camNode: SCNNode?
        private var lastTime: TimeInterval = 0
        private var tickPending = false
        private let tickLock = NSLock()

        init(controller: GameSceneController) {
            self.controller = controller
        }

        // the look pan must live alongside the SwiftUI joystick drag: default
        // recognizer mediation would let only one of them track at a time
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        var pitch: Float = 0
        private var lastYaw: Float = 0
        private var lastPitch: Float = 0

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            controller.cameraYaw -= Float(t.x) * 0.006
            pitch = max(-1.1, min(1.1, pitch - Float(t.y) * 0.006))
            g.setTranslation(.zero, in: g.view)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime == 0 ? 0 : Float(time - lastTime)
            lastTime = time
            // scene mutations from the network apply here, on the render side,
            // never racing SceneKit's draw from the main thread
            controller.applyPendingSnapshot()
            guard dt > 0 else { return }
            // game logic hops to main, at most one queued hop: a stalled main
            // thread must drop frames, not accumulate per-frame work forever
            tickLock.lock()
            let hopQueued = tickPending
            if !tickPending { tickPending = true }
            tickLock.unlock()
            if !hopQueued {
                DispatchQueue.main.async { [weak self] in
                    NotificationCenter.default.post(name: .gameTick, object: nil, userInfo: ["dt": dt])
                    self?.tickLock.lock()
                    self?.tickPending = false
                    self?.tickLock.unlock()
                }
            }

            // first-person camera: at the player's head, yaw + pitch from the drag
            let yaw = controller.cameraYaw
            let effPitch = controller.cameraPitchOverride ?? pitch
            camNode?.position = SCNVector3(controller.localPosition.x, 1.32, controller.localPosition.z)
            // yaw about world Y, then pitch about the yawed X axis (FPS convention)
            let q = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: effPitch, axis: SIMD3<Float>(1, 0, 0))
            camNode?.orientation = SCNQuaternion(q.vector.x, q.vector.y, q.vector.z, q.vector.w)

            // first-person hand: walk bob from the stick, look sway from how
            // fast the camera is turning (wrapped + clamped for pan spikes)
            if dt > 0 {
                var dyaw = yaw - lastYaw
                if dyaw > .pi { dyaw -= 2 * .pi } else if dyaw < -.pi { dyaw += 2 * .pi }
                let yawVel = max(-8, min(8, dyaw / dt))
                let pitchVel = max(-8, min(8, (effPitch - lastPitch) / dt))
                let jv = controller.joystickVector
                let moveAmt = min(1, hypotf(Float(jv.dx), Float(jv.dy)))
                controller.updateHand(dt: dt, move: moveAmt, yawVel: yawVel, pitchVel: pitchVel)
            }
            lastYaw = yaw
            lastPitch = effPitch
        }
    }
}

extension Notification.Name {
    static let gameTick = Notification.Name("carflopper.gameTick")
}

// MARK: - Virtual joystick

struct JoystickView: View {
    // reports into the scene controller (plain var): no SwiftUI state churn
    // at drag-event rate, so this gesture never rebuilds the view tree
    var onChange: (CGVector) -> Void
    @State private var knob: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.12))
            Circle().stroke(.white.opacity(0.35), lineWidth: 2)
            Circle()
                .fill(.white.opacity(0.75))
                .frame(width: 52, height: 52)
                .offset(knob)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let maxR: CGFloat = 44
                            var t = g.translation
                            let len = hypot(t.width, t.height)
                            if len > maxR {
                                t.width = t.width / len * maxR
                                t.height = t.height / len * maxR
                            }
                            knob = t
                            onChange(CGVector(dx: t.width / maxR, dy: t.height / maxR))
                        }
                        .onEnded { _ in
                            knob = .zero
                            onChange(.zero)
                        }
                )
        }
    }
}
