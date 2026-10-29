import Foundation
import SceneKit
import UIKit

// MARK: - Scene controller: maps RoomSnapshot state to visuals, owns local player motion.

final class GameSceneController: NSObject {
    let scene = SCNScene()
    private(set) var car: CarAssembly?
    private var avatars: [String: AvatarNode] = [:]
    private var sparks: [String: SCNNode] = [:]

    var localId: String
    var localPosition = SCNVector3(0, 0, 3.5)
    var localHeading: Float = .pi // facing -z toward car
    var cameraYaw: Float = .pi // start behind the player, who faces the car (-z)

    private var lastSnapshot: RoomSnapshot?
    private var celebrateNode: SCNNode?

    var carIndex: Int = 0

    init(localId: String) {
        self.localId = localId
        super.init()
        GarageBuilder.buildEnvironment(into: scene.rootNode)
    }

    func setCar(index: Int, parts: [String: PartState]) {
        car?.root.removeFromParentNode()
        car = nil
        let def = GameContent.cars[min(max(index, 0), GameContent.cars.count - 1)]
        let assembly = CarAssembly(def: def)
        scene.rootNode.addChildNode(assembly.root)
        self.car = assembly
        for (id, st) in parts { assembly.setPart(id, progress: st.progress) }
    }

    func apply(snapshot: RoomSnapshot) {
        let prev = lastSnapshot
        lastSnapshot = snapshot

        if snapshot.phase == "play" || snapshot.phase == "complete" {
            if car == nil || prev?.carIndex != snapshot.carIndex {
                setCar(index: snapshot.carIndex, parts: snapshot.parts)
            } else {
                for (id, st) in snapshot.parts {
                    if prev?.parts[id] != st { car?.setPart(id, progress: st.progress) }
                }
                updateSparks(parts: snapshot.parts)
            }
            if snapshot.phase == "complete" && prev?.phase != "complete" {
                showCelebration()
            }
        }

        // avatars
        let ids = Set(snapshot.players.map { $0.id })
        for (id, av) in avatars where !ids.contains(id) {
            av.root.removeFromParentNode()
            avatars.removeValue(forKey: id)
        }
        for p in snapshot.players where p.id != localId {
            if avatars[p.id] == nil {
                let av = AvatarNode(name: p.name, color: GameContent.playerColor(p.color))
                scene.rootNode.addChildNode(av.root)
                avatars[p.id] = av
            }
            let av = avatars[p.id]!
            let target = SCNVector3(p.x, 0, p.z)
            // light smoothing toward network position
            let cur = av.root.position
            let t: Float = 0.35
            av.root.position = SCNVector3(cur.x + (target.x - cur.x) * t, 0, cur.z + (target.z - cur.z) * t)
            av.root.eulerAngles.y = p.ry
        }
    }

    func syncLocalAvatar() {
        if avatars[localId] == nil {
            let av = AvatarNode(name: "You", color: .white)
            scene.rootNode.addChildNode(av.root)
            avatars[localId] = av
            av.label.isHidden = true
        }
        let av = avatars[localId]!
        av.root.position = localPosition
        av.root.eulerAngles.y = localHeading
    }

    // MARK: repair helpers

    func nearestBrokenPart(parts: [String: PartState]) -> (PartDef, Float)? {
        guard let car else { return nil }
        var best: (PartDef, Float)?
        for p in car.def.parts {
            let st = parts[p.id]
            guard (st?.progress ?? 0) < 1 else { continue }
            let dx = localPosition.x - p.x
            let dz = localPosition.z - p.z
            let d = sqrtf(dx * dx + dz * dz)
            if d < GameContent.repairReach, best == nil || d < best!.1 {
                best = (p, d)
            }
        }
        return best
    }

    private func updateSparks(parts: [String: PartState]) {
        guard let car else { return }
        for (id, st) in parts {
            let active = st.fixers > 0 && st.progress < 1
            if active && sparks[id] == nil, let pd = car.def.parts.first(where: { $0.id == id }) {
                let s = makeSparks()
                s.position = SCNVector3(pd.x, pd.y + 0.3, pd.z)
                car.root.addChildNode(s)
                sparks[id] = s
            } else if !active, let s = sparks[id] {
                s.removeFromParentNode()
                sparks.removeValue(forKey: id)
            }
        }
    }

    private func makeSparks() -> SCNNode {
        let node = SCNNode()
        let p = SCNParticleSystem()
        p.birthRate = 60
        p.particleLifeSpan = 0.35
        p.emissionDuration = .infinity
        p.spreadingAngle = 60
        p.particleVelocity = 1.6
        p.particleVelocityVariation = 0.8
        p.particleSize = 0.03
        p.particleColor = UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1)
        p.emitterShape = SCNSphere(radius: 0.05)
        p.isAffectedByGravity = true
        node.addParticleSystem(p)
        return node
    }

    private func showCelebration() {
        celebrateNode?.removeFromParentNode()
        let node = SCNNode()
        let p = SCNParticleSystem()
        p.birthRate = 200
        p.particleLifeSpan = 1.6
        p.emissionDuration = 2.5
        p.spreadingAngle = 180
        p.particleVelocity = 4
        p.particleSize = 0.08
        p.particleColor = UIColor(red: 0.4, green: 0.9, blue: 1, alpha: 1)
        p.isAffectedByGravity = true
        node.addParticleSystem(p)
        node.position = SCNVector3(0, 1.5, 0)
        scene.rootNode.addChildNode(node)
        celebrateNode = node
    }

    // MARK: movement (clamped to garage)
    func moveLocal(dx: Float, dz: Float, dt: Float) {
        let speed: Float = 3.4
        var nx = localPosition.x + dx * speed * dt
        var nz = localPosition.z + dz * speed * dt
        nx = max(-7.4, min(7.4, nx))
        nz = max(-5.4, min(5.4, nz))
        // keep out of the car's rectangle
        let inCarX = abs(nx) < 1.25
        let inCarZ = abs(nz) < 2.35
        if inCarX && inCarZ {
            // push out along the smaller penetration axis
            let pushX = 1.25 - abs(nx)
            let pushZ = 2.35 - abs(nz)
            if pushX < pushZ { nx = nx < 0 ? -1.25 : 1.25 } else { nz = nz < 0 ? -2.35 : 2.35 }
        }
        if dx != 0 || dz != 0 {
            localHeading = atan2f(dx, dz)
        }
        localPosition = SCNVector3(nx, 0, nz)
        syncLocalAvatar()
    }
}
