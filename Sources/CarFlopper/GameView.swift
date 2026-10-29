import SwiftUI
import SceneKit
import simd

// MARK: - In-game view: SceneKit canvas + joystick + repair button + HUD.

struct GameView: View {
    @ObservedObject var vm: GameViewModel
    var onLeave: () -> Void

    private func autoDriveGame() {
        #if AUTODRIVE
        guard ProcessInfo.processInfo.arguments.contains("-CFAutoDrive") else { return }
        print("[CFAUTODRIVE] garage appeared")
        // showcase orbit: closed-loop strafe around the car through the normal
        // joystick movement pipeline (moveLocal clamps, heading, network sync),
        // facing the car the whole time. Player position changes continuously
        // across every capture: real walking, not just a camera pan.
        // phase 0: closed-loop orbit (walking proof). phases 1/2/3: park at
        // front-left, front-right and rear so captures cover the whole car.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            print("[CFAUTODRIVE] orbit start")
            var phase = 0
            var lastP = vm.sceneCtrl.localPosition
            var stuckTicks = 0
            var tick = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { phase = 1; print("[CFAUTODRIVE] park front-left") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 50.0) { phase = 2; print("[CFAUTODRIVE] park front-right") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 70.0) { phase = 3; print("[CFAUTODRIVE] park rear") }
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                let p = vm.sceneCtrl.localPosition
                tick += 1
                if tick % 50 == 0 { print("[CFAUTODRIVE] tick \(tick) pos \(p.x) \(p.z) phase \(phase)") }
                let moved = hypotf(p.x - lastP.x, p.z - lastP.z)
                let pushing = vm.joystick.dx != 0 || vm.joystick.dy != 0
                if pushing && moved < 0.01 { stuckTicks += 1 } else { stuckTicks = 0 }
                lastP = p
                if stuckTicks > 5 {
                    // grinding an obstacle (collision stops translation while the
                    // stick keeps pushing): back straight off, then resume
                    vm.joystick = CGVector(dx: 0, dy: 0.85)
                    if stuckTicks > 12 { stuckTicks = 0 }
                    return
                }
                if phase == 0 {
                    // face the car center: camera forward is (-sin yaw, -cos yaw)
                    vm.sceneCtrl.cameraYaw = atan2f(p.x, p.z)
                    // keep orbit radius in [2.9, 3.4] so we never grind the car or the walls
                    let r = hypotf(p.x, p.z)
                    let inward: Float = r > 3.4 ? 0.35 : (r < 2.9 ? -0.35 : 0.0)
                    vm.joystick = CGVector(dx: 0.7, dy: Double(-inward))
                } else {
                    let t: (Float, Float) = phase == 1 ? (-1.7, 3.1) : (phase == 2 ? (1.7, 3.1) : (0, -3.4))
                    let dx = t.0 - p.x, dz = t.1 - p.z
                    let d = hypotf(dx, dz)
                    if d > 0.18 {
                        // walk toward the parking spot (camera-relative movement)
                        vm.sceneCtrl.cameraYaw = atan2f(-dx, -dz)
                        vm.joystick = CGVector(dx: 0, dy: -0.55)
                    } else {
                        // parked: face the car
                        vm.joystick = .zero
                        vm.sceneCtrl.cameraYaw = atan2f(p.x, p.z)
                    }
                }
            }
        }
        #endif
    }

    var body: some View {
        ZStack {
            SceneViewBridge(controller: vm.sceneCtrl, cameraYaw: $vm.cameraYaw)
                .ignoresSafeArea()
                .onAppear { autoDriveGame() }

            VStack {
                hud
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(spacing: 6) {
                        JoystickView(vector: $vm.joystick)
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
    @Binding var cameraYaw: Float

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, cameraYaw: $cameraYaw) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = controller.scene
        v.backgroundColor = .black
#if targetEnvironment(simulator)
        // simulator renders in software: keep the scene content identical but
        // lower the throughput cost so CI can capture real frames
        v.antialiasingMode = .multisampling2X
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

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let controller: GameSceneController
        var cameraYaw: Binding<Float>
        weak var camNode: SCNNode?
        private var lastTime: TimeInterval = 0

        init(controller: GameSceneController, cameraYaw: Binding<Float>) {
            self.controller = controller
            self.cameraYaw = cameraYaw
        }

        var pitch: Float = 0

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            cameraYaw.wrappedValue = controller.cameraYaw
            controller.cameraYaw -= Float(t.x) * 0.006
            pitch = max(-1.1, min(1.1, pitch - Float(t.y) * 0.006))
            g.setTranslation(.zero, in: g.view)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime == 0 ? 0 : Float(time - lastTime)
            lastTime = time
            guard dt > 0 else { return }
            NotificationCenter.default.post(name: .gameTick, object: nil, userInfo: ["dt": dt])

            // first-person camera: at the player's head, yaw + pitch from the drag
            let yaw = controller.cameraYaw
            camNode?.position = SCNVector3(controller.localPosition.x, 1.32, controller.localPosition.z)
            // yaw about world Y, then pitch about the yawed X axis (FPS convention)
            let q = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
            camNode?.orientation = SCNQuaternion(q.vector.x, q.vector.y, q.vector.z, q.vector.w)
        }
    }
}

extension Notification.Name {
    static let gameTick = Notification.Name("carflopper.gameTick")
}

// MARK: - Virtual joystick

struct JoystickView: View {
    @Binding var vector: CGVector
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
                            vector = CGVector(dx: t.width / maxR, dy: t.height / maxR)
                        }
                        .onEnded { _ in
                            knob = .zero
                            vector = .zero
                        }
                )
        }
    }
}
