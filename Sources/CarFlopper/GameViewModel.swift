import Foundation
import SwiftUI
import UIKit
import SceneKit // SCNVector3 for station world positions
import QuartzCore

@MainActor
final class GameViewModel: ObservableObject {
    let session: GameSession
    let sceneCtrl: GameSceneController
    let localId = UUID().uuidString.prefix(8).description

    @Published var autodriveDebug = ""
    @Published var roomCode: String = ""
    @Published var phase: String = "lobby"
    @Published var players: [RoomPlayer] = []
    @Published var parts: [String: PartState] = [:]
    @Published var carIndex: Int = 0
    @Published var isHost = false
    @Published var hostId = ""
    @Published var connectionError: String?

    @Published var isRepairing = false
    @Published var heldTool: String? = nil   // nil = bare hands
    @Published var toolToast: String? = nil  // "Wrench equipped" flash
    private var pendingPickupTool: String? = nil   // station ring you stand in, not yet grabbed
    private var pendingPickupSince: TimeInterval = 0
    private var pickupPromptTool: String? = nil    // which "look to grab" prompt is up
    @Published var wrongToolFlash = false    // tapped fix without the right tool

    private var tickObserver: NSObjectProtocol?
    private var lastPosSent: TimeInterval = 0
    private var hapticTimer: TimeInterval = 0
    private var currentCarIndex = -1

    var carDef: CarDef { GameContent.cars[min(max(carIndex, 0), GameContent.cars.count - 1)] }
    var carName: String { carDef.name }
    var nextCarLocked: Bool { carIndex + 1 >= GameContent.cars.count }
    var nextCarName: String { nextCarLocked ? "" : GameContent.cars[carIndex + 1].name }

    var fixedCount: Int { parts.values.filter { $0.progress >= 1 }.count }
    var totalCount: Int { max(parts.count, 1) }
    var totalProgress: Double {
        guard !parts.isEmpty else { return 0 }
        return Double(parts.values.reduce(0) { $0 + min($1.progress, 1) } / Float(parts.count))
    }

    var activePart: PartDef? {
        sceneCtrl.nearestBrokenPart(parts: parts)?.0
    }
    var activePartProgress: Double {
        guard let p = activePart else { return 0 }
        return Double(parts[p.id]?.progress ?? 0)
    }

    init(session: GameSession) {
        self.session = session
        self.sceneCtrl = GameSceneController(localId: "")
        session.delegate = self
        tickObserver = NotificationCenter.default.addObserver(forName: .gameTick, object: nil, queue: .main) { [weak self] note in
            guard let self, let dt = note.userInfo?["dt"] as? Float else { return }
            self.tick(dt: dt)
        }
    }

    deinit { if let o = tickObserver { NotificationCenter.default.removeObserver(o) } }

    private func tick(dt: Float) {
        guard phase == "play" else { return }
        // joystick is screen-space; rotate by camera yaw
        let jx = Float(sceneCtrl.joystickVector.dx), jy = Float(sceneCtrl.joystickVector.dy)
        if jx != 0 || jy != 0 {
            let yaw = sceneCtrl.cameraYaw
            let dx = jx * cosf(yaw) + jy * sinf(yaw)
            let dz = jy * cosf(yaw) - jx * sinf(yaw)
            // normalize if needed
            let len = max(1, hypotf(dx, dz))
            sceneCtrl.moveLocal(dx: dx / len * min(1, hypotf(jx, jy)), dz: dz / len * min(1, hypotf(jx, jy)), dt: dt)
        }
        // network send at ~12 Hz
        let now = CACurrentMediaTime()
        if now - lastPosSent > 0.08 {
            lastPosSent = now
            let moving = jx != 0 || jy != 0
            session.sendPosition(x: sceneCtrl.localPosition.x, z: sceneCtrl.localPosition.z, ry: sceneCtrl.localHeading, moving: moving)
        }
        // tool stations: walk into a ring to equip. Benches sit close
        // together, so equip the NEAREST station in reach - never an
        // arbitrary neighbor picked by array order. While you still stand
        // inside the ring of the tool you already hold, KEEP it: two
        // overlapping rings (wrench/welder benches are 1.28m apart, reach
        // is 1.3m) would otherwise swap the tool back and forth every tick
        // and leave you holding whichever one the last frame picked.
        let reach2 = GameContent.toolPickupReach * GameContent.toolPickupReach
        var keepHeld = false
        if let held = heldTool, let hs = GameContent.toolStations.first(where: { $0.tool == held }) {
            let hx = sceneCtrl.localPosition.x - hs.x
            let hz = sceneCtrl.localPosition.z - hs.z
            keepHeld = hx * hx + hz * hz < reach2
        }
        var pickStation: ToolStation?
        var pickD2 = reach2
        if !keepHeld {
            for st in GameContent.toolStations where st.tool != heldTool {
                let dx = sceneCtrl.localPosition.x - st.x
                let dz = sceneCtrl.localPosition.z - st.z
                let d2 = dx * dx + dz * dz
                if d2 < pickD2 { pickD2 = d2; pickStation = st }
            }
        }
        if let st = pickStation {
            // facing-gated pickup: the grab fires while you look at the
            // station so the reach to the floating tool is on camera. Stand
            // in the ring without looking and a 5s grace still hands you the
            // tool - tool access never dead-ends behind the camera.
            if pendingPickupTool != st.tool { pendingPickupTool = st.tool; pendingPickupSince = now }
            let fdx = st.x - sceneCtrl.localPosition.x
            let fdz = st.z - sceneCtrl.localPosition.z
            let fl = max(0.001, hypotf(fdx, fdz))
            let facing = -sinf(sceneCtrl.cameraYaw) * (fdx / fl) - cosf(sceneCtrl.cameraYaw) * (fdz / fl)
            if facing > 0.55 || now - pendingPickupSince > 5 {
                pendingPickupTool = nil
                pickupPromptTool = nil
                heldTool = st.tool
                sceneCtrl.equipHandTool(st.tool, fromWorld: SCNVector3(st.x, 1.05, st.z))
                // the station float vanishes as the tool lands in the hand
                let heldNow = st.tool
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.sceneCtrl.setHeldStationDisplay(heldNow)
                }
                if let td = GameContent.tools[st.tool] {
                    toolToast = "\(td.label) equipped"
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let t = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        await MainActor.run { if self?.toolToast == "\(td.label) equipped" { self?.toolToast = nil } }
                    }
                    _ = t
                }
            } else if let td = GameContent.tools[st.tool], pickupPromptTool != st.tool {
                pickupPromptTool = st.tool
                toolToast = "Look at the \(td.label) to grab it"
            }
        } else {
            pendingPickupTool = nil
            if let pt = pickupPromptTool {
                pickupPromptTool = nil
                if let td = GameContent.tools[pt], toolToast == "Look at the \(td.label) to grab it" { toolToast = nil }
            }
        }
        // repairing must stop if we walk out of range or part got fixed
        if isRepairing && activePart == nil { setRepairing(false) }
        // haptics while repairing
        if isRepairing, now - hapticTimer > 0.25 {
            hapticTimer = now
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func setRepairing(_ on: Bool) {
        guard on != isRepairing else { return }
        if on, let p = activePart {
            guard heldTool == p.tool else {
                // wrong tool (or bare hands): flash the need, never start
                wrongToolFlash = true
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                let t = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await MainActor.run { self?.wrongToolFlash = false }
                }
                _ = t
                return
            }
            isRepairing = true
            sceneCtrl.setHandWorking(true, tool: p.tool, atWorld: SCNVector3(p.x, p.y, p.z))
            session.sendRepair(part: p.id, on: true)
        } else {
            isRepairing = false
            sceneCtrl.setHandWorking(false, tool: nil)
            session.sendRepair(part: nil, on: false)
        }
    }

    func advanceCar() { session.sendNextCar() }
    func pickCar(_ i: Int) { session.sendPickCar(i) }
    func startGame() { session.sendStart() }

    func leave() {
        session.close()
    }
}

extension GameViewModel: GameSessionDelegate {
    nonisolated func session(_ s: GameSession, didReceive snapshot: RoomSnapshot) {
        Task { @MainActor in
            self.roomCode = snapshot.code
            self.phase = snapshot.phase
            self.players = snapshot.players
            self.parts = snapshot.parts
            self.carIndex = snapshot.carIndex
            self.hostId = snapshot.hostId
            self.isHost = snapshot.hostId == s.myId
            if let myId = s.myId, self.sceneCtrl.localId != myId {
                self.sceneCtrl.localId = myId
            }
            self.sceneCtrl.enqueue(snapshot: snapshot)
            if snapshot.phase == "complete" && self.currentCarIndex != snapshot.carIndex {
                self.currentCarIndex = snapshot.carIndex
                UnlockStore.recordCompletion(carIndex: snapshot.carIndex)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    nonisolated func session(_ s: GameSession, didGetEvent kind: String, payload: [String: String]) {
        Task { @MainActor in
            if kind == "partFixed" {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    nonisolated func sessionDidClose(_ s: GameSession, reason: String) {
        Task { @MainActor in
            self.connectionError = reason
        }
    }
}

// MARK: - Local unlock persistence

enum UnlockStore {
    private static let key = "carflopper.unlockedMax"
    static var unlockedMax: Int {
        get { max(UserDefaults.standard.integer(forKey: key), 0) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func recordCompletion(carIndex: Int) {
        if carIndex + 1 > unlockedMax { unlockedMax = min(carIndex + 1, GameContent.cars.count - 1) }
    }
    static func isUnlocked(_ index: Int) -> Bool { index <= unlockedMax }
}
