import Foundation
import SceneKit
import UIKit

// MARK: - Car assembly from primitives. Node names carry part ids for damage state.

final class CarAssembly {
    let root = SCNNode()
    let def: CarDef
    private(set) var partNodes: [String: SCNNode] = [:]
    private(set) var markers: [String: SCNNode] = [:]

    init(def: CarDef) {
        self.def = def
        build()
    }

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ chamfer: CGFloat = 0.05, _ mats: [SCNMaterial]) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        g.materials = mats
        return SCNNode(geometry: g)
    }

    private func build() {
        let body = Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.35, metal: 0.5)
        let accent = Mat.flat(def.accentRGB.0, def.accentRGB.1, def.accentRGB.2, rough: 0.6, metal: 0.3)

        // main tub
        let tub = box(1.75, 0.55, 4.0, 0.12, [body])
        tub.position = SCNVector3(0, 0.55, 0)
        root.addChildNode(tub)

        // cabin
        let cabin = box(1.5, 0.5, 1.9, 0.14, [body])
        cabin.position = SCNVector3(0, 1.05, -0.25)
        root.addChildNode(cabin)

        // windshield (part)
        let shield = box(1.35, 0.5, 0.08, 0.02, [Mat.glass])
        shield.position = SCNVector3(0, 1.02, 0.62)
        shield.eulerAngles.x = -0.35
        shield.name = "part_windshield"
        root.addChildNode(shield)
        partNodes["windshield"] = shield

        // hood / engine bay (part: engine sits under hood)
        let hood = box(1.6, 0.10, 1.2, 0.03, [body])
        hood.position = SCNVector3(0, 0.86, 1.4)
        root.addChildNode(hood)
        let engine = SCNNode(geometry: SCNBox(width: 1.0, height: 0.4, length: 0.9, chamferRadius: 0.04))
        (engine.geometry as? SCNBox)?.materials = [Mat.steelDark]
        engine.position = SCNVector3(0, 0.72, 1.4)
        engine.name = "part_engine"
        root.addChildNode(engine)
        partNodes["engine"] = engine

        // driver door (part)
        let door = box(0.06, 0.5, 1.0, 0.02, [body])
        door.position = SCNVector3(-0.90, 0.60, -0.05)
        door.name = "part_door"
        root.addChildNode(door)
        partNodes["door"] = door

        // bumpers
        let bf = box(1.8, 0.25, 0.25, 0.06, [accent])
        bf.position = SCNVector3(0, 0.35, 2.05)
        root.addChildNode(bf)
        let bb = box(1.8, 0.25, 0.25, 0.06, [accent])
        bb.position = SCNVector3(0, 0.35, -2.05)
        root.addChildNode(bb)

        // headlights
        for dx in [-0.6, 0.6] as [Float] {
            let hl = SCNNode(geometry: SCNSphere(radius: 0.12))
            let m = SCNMaterial()
            m.emission.contents = UIColor(white: 0.9, alpha: 1)
            (hl.geometry as? SCNSphere)?.materials = [m]
            hl.position = SCNVector3(dx, 0.62, 2.02)
            root.addChildNode(hl)
        }

        // exhaust (part)
        let ex = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.5))
        (ex.geometry as? SCNCylinder)?.materials = [Mat.steel]
        ex.eulerAngles.x = .pi / 2
        ex.position = SCNVector3(0.35, 0.25, -2.15)
        ex.name = "part_exhaust"
        root.addChildNode(ex)
        partNodes["exhaust"] = ex

        // wheels (parts)
        for (id, x, z) in [("wheelFL", Float(-0.85), Float(1.30)),
                           ("wheelFR", Float(0.85), Float(1.30)),
                           ("wheelRL", Float(-0.85), Float(-1.30)),
                           ("wheelRR", Float(0.85), Float(-1.30))] {
            let wheel = SCNNode()
            wheel.name = "part_\(id)"
            let tire = SCNNode(geometry: SCNCylinder(radius: 0.36, height: 0.25))
            (tire.geometry as? SCNCylinder)?.materials = [Mat.rubber]
            tire.eulerAngles.z = .pi / 2
            wheel.addChildNode(tire)
            let rim = SCNNode(geometry: SCNCylinder(radius: 0.19, height: 0.26))
            (rim.geometry as? SCNCylinder)?.materials = [Mat.steel]
            rim.eulerAngles.z = .pi / 2
            wheel.addChildNode(rim)
            wheel.position = SCNVector3(x, 0.36, z)
            root.addChildNode(wheel)
            partNodes[id] = wheel
        }

        // spoiler for drift cars
        if def.hasSpoiler {
            let wing = box(1.6, 0.06, 0.35, 0.02, [accent])
            wing.position = SCNVector3(0, 1.25, -1.95)
            root.addChildNode(wing)
            for dx in [-0.6, 0.6] as [Float] {
                let strut = box(0.06, 0.35, 0.10, 0.01, [accent])
                strut.position = SCNVector3(dx, 1.05, -1.95)
                root.addChildNode(strut)
            }
        }

        // repair markers (floating diamonds above broken parts)
        for p in def.parts {
            let marker = SCNNode(geometry: SCNPyramid(width: 0.24, height: 0.24, length: 0.24))
            let m = SCNMaterial()
            m.emission.contents = UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
            m.diffuse.contents = UIColor.black
            (marker.geometry as? SCNPyramid)?.materials = [m]
            marker.position = SCNVector3(p.x, p.y + 0.85, p.z)
            marker.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.15, z: 0, duration: 0.6),
                .moveBy(x: 0, y: -0.15, z: 0, duration: 0.6),
            ])))
            marker.runAction(.repeatForever(.rotateBy(x: 0, y: 2, z: 0, duration: 1.2)))
            root.addChildNode(marker)
            markers[p.id] = marker
        }
    }

    // Visual state per part: broken (dark + marker) -> fixed (clean, marker removed)
    func setPart(_ id: String, progress: Float) {
        guard let node = partNodes[id] else { return }
        let fixed = progress >= 1
        markers[id]?.isHidden = fixed
        let brokenTint = UIColor(red: 0.25, green: 0.20, blue: 0.18, alpha: 1)
        if id == "windshield" {
            let g = node.geometry as? SCNBox
            g?.materials = fixed ? [Mat.glass] : [crackedGlass()]
        } else if id == "engine" || id == "exhaust" {
            if !fixed { node.geometry?.materials = [Mat.rust] }
            else { node.geometry?.materials = [id == "engine" ? Mat.steelDark : Mat.steel] }
        } else if id.hasPrefix("wheel") {
            // broken = flat: squash y; fixed = normal
            node.scale = SCNVector3(1, fixed ? 1 : 0.55, 1)
        } else if id == "door" {
            if !fixed { node.geometry?.materials = [Mat.flat(def.bodyRGB.0 * 0.4, def.bodyRGB.1 * 0.4, def.bodyRGB.2 * 0.4, rough: 0.9)] ; node.eulerAngles.y = 0.5 }
            else { node.geometry?.materials = [Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.35, metal: 0.5)]; node.eulerAngles.y = 0 }
        }
        _ = brokenTint
    }

    private func crackedGlass() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(white: 0.55, alpha: 0.75)
        m.isDoubleSided = true
        return m
    }
}

// MARK: - Mechanic avatar

final class AvatarNode {
    let root = SCNNode()
    let label: SCNNode

    init(name: String, color: UIColor) {
        let shirt = SCNMaterial()
        shirt.diffuse.contents = color
        let skin = Mat.flat(0.85, 0.65, 0.50)
        let denim = Mat.flat(0.20, 0.28, 0.45)

        // legs
        for dx in [-0.09, 0.09] as [Float] {
            let leg = SCNNode(geometry: SCNBox(width: 0.14, height: 0.5, length: 0.16, chamferRadius: 0.03))
            (leg.geometry as? SCNBox)?.materials = [denim]
            leg.position = SCNVector3(dx, 0.25, 0)
            root.addChildNode(leg)
        }
        // torso
        let torso = SCNNode(geometry: SCNBox(width: 0.42, height: 0.55, length: 0.24, chamferRadius: 0.08))
        (torso.geometry as? SCNBox)?.materials = [shirt]
        torso.position = SCNVector3(0, 0.78, 0)
        root.addChildNode(torso)
        // arms
        for dx in [-0.28, 0.28] as [Float] {
            let arm = SCNNode(geometry: SCNBox(width: 0.11, height: 0.45, length: 0.13, chamferRadius: 0.03))
            (arm.geometry as? SCNBox)?.materials = [shirt]
            arm.position = SCNVector3(dx, 0.80, 0)
            root.addChildNode(arm)
        }
        // head
        let head = SCNNode(geometry: SCNSphere(radius: 0.17))
        (head.geometry as? SCNSphere)?.materials = [skin]
        head.position = SCNVector3(0, 1.25, 0)
        root.addChildNode(head)
        // cap
        let cap = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 0.10))
        (cap.geometry as? SCNCylinder)?.materials = [shirt]
        cap.position = SCNVector3(0, 1.38, 0)
        root.addChildNode(cap)

        // name tag
        label = SCNNode(geometry: SCNPlane(width: 1.4, height: 0.32))
        label.position = SCNVector3(0, 1.70, 0)
        let lm = SCNMaterial()
        lm.diffuse.contents = AvatarNode.makeLabelImage(name: name, color: color)
        lm.isDoubleSided = true
        (label.geometry as? SCNPlane)?.materials = [lm]
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        label.constraints = [billboard]
        root.addChildNode(label)
    }

    private static func makeLabelImage(name: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 280, height: 64)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            let bg = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16)
            UIColor(white: 0, alpha: 0.55).setFill()
            bg.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 30),
                .foregroundColor: color,
            ]
            let s = NSAttributedString(string: name, attributes: attrs)
            let ts = s.size()
            s.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2))
            _ = ctx
        }
    }
}
