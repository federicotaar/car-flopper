import Foundation
import SwiftUI
import UIKit

@MainActor
final class GameViewModel: ObservableObject {
    let session: GameSession
    let sceneCtrl: GameSceneController
    let localId = UUID().uuidString.prefix(8).description

    @Published var roomCode: String = ""
    @Published var phase: String = "lobby"
    @Published var players: [RoomPlayer] = []
    @Published var parts: [String: PartState] = [:]
    @Published var carIndex: Int = 0
    @Published var isHost = false
    @Published var connectionError: String?

    @Published var joystick: CGVector = .zero
    @Published var cameraYaw: Float = 0
    @Published var isRepairing = false

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
        let jx = Float(joystick.dx), jy = Float(joystick.dy)
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
            isRepairing = true
            session.sendRepair(part: p.id, on: true)
        } else {
            isRepairing = false
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
            self.isHost = snapshot.hostId == s.myId
            if let myId = s.myId, self.sceneCtrl.localId != myId {
                self.sceneCtrl.localId = myId
            }
            self.sceneCtrl.apply(snapshot: snapshot)
            if snapshot.phase == "complete" && self.currentCarIndex != snapshot.carIndex {
                self.currentCarIndex = snapshot.carIndex
                UnlockStore.recordCompletion(carIndex: snapshot.carIndex)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if snapshot.phase == "play" && self.sceneCtrl.car == nil {
                self.sceneCtrl.setCar(index: snapshot.carIndex, parts: snapshot.parts)
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
