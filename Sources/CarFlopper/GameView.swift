import SwiftUI
import SceneKit

// MARK: - In-game view: SceneKit canvas + joystick + repair button + HUD.

struct GameView: View {
    @ObservedObject var vm: GameViewModel
    var onLeave: () -> Void

    private func autoDriveGame() {
        #if AUTODRIVE
        guard ProcessInfo.processInfo.arguments.contains("-CFAutoDrive") else { return }
        print("[CFAUTODRIVE] garage appeared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { vm.joystick = CGVector(dx: 0, dy: 1); print("[CFAUTODRIVE] walk toward car") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { vm.joystick = CGVector(dx: 0.6, dy: 0.6); print("[CFAUTODRIVE] walk diagonal") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 11.0) { vm.joystick = .zero; print("[CFAUTODRIVE] walk stop") }
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
                    JoystickView(vector: $vm.joystick)
                        .frame(width: 130, height: 130)
                        .padding(.leading, 24)
                    Spacer()
                    repairButton
                        .padding(.trailing, 24)
                }
                .padding(.bottom, 34)
            }

            if vm.phase == "complete" {
                completionOverlay
            }
        }
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
    private var repairButton: some View {
        if let part = vm.activePart {
            VStack(spacing: 8) {
                Text(part.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.orange.opacity(0.85), in: Capsule())
                ProgressView(value: vm.activePartProgress)
                    .tint(.orange)
                    .frame(width: 90)
                Text(vm.isRepairing ? "FIXING..." : "HOLD TO FIX")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.9))
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                    .background(vm.isRepairing ? Color.green : Color.orange, in: Circle())
                    .shadow(radius: 8)
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
        v.antialiasingMode = .multisampling2X
        v.delegate = context.coordinator
        v.isPlaying = true
        v.preferredFramesPerSecond = 60

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 62
        cam.camera?.zNear = 0.05
        cam.camera?.zFar = 60
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

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            cameraYaw.wrappedValue = controller.cameraYaw
            controller.cameraYaw -= Float(t.x) * 0.008
            g.setTranslation(.zero, in: g.view)
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime == 0 ? 0 : Float(time - lastTime)
            lastTime = time
            guard dt > 0 else { return }
            NotificationCenter.default.post(name: .gameTick, object: nil, userInfo: ["dt": dt])

            // third-person camera: behind the player at yaw, framing player AND car.
            // look target is biased toward the car center so repairs stay in frame.
            let yaw = controller.cameraYaw
            let dist: Float = 4.6
            let height: Float = 4.6
            let px = controller.localPosition.x
            let pz = controller.localPosition.z
            // clamp inside the garage shell so walls never swallow the camera
            let rawCx = px - sinf(yaw) * dist
            let rawCz = pz - cosf(yaw) * dist
            let cx = max(-7.8, min(7.8, rawCx))
            let cz = max(-5.8, min(5.8, rawCz))
            camNode?.position = SCNVector3(cx, height, cz)
            // when the wall clamp kicks in the camera sits almost above the player;
            // aim straight at them so they never leave the frame
            if abs(rawCx - cx) > 0.01 || abs(rawCz - cz) > 0.01 {
                camNode?.look(at: SCNVector3(px, 1.0, pz))
            } else {
                camNode?.look(at: SCNVector3(px * 0.35, 0.7, pz * 0.35))
            }
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
