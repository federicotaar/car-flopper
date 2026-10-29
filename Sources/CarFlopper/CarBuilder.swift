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
        let body = Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.25, metal: 0.85)
        body.specular.contents = UIColor(white: 0.9, alpha: 1)
        let accent = Mat.flat(def.accentRGB.0, def.accentRGB.1, def.accentRGB.2, rough: 0.5, metal: 0.6)
        let interiorMat = Mat.flat(0.18, 0.18, 0.20, rough: 0.9)
        let seatMat = Mat.flat(0.30, 0.28, 0.26, rough: 0.85)

        // lower body tub
        let tub = box(1.75, 0.55, 4.0, 0.12, [body])
        tub.position = SCNVector3(0, 0.55, 0)
        root.addChildNode(tub)

        // side skirts
        for sx in [-1, 1] as [Float] {
            let skirt = box(0.08, 0.14, 2.1, 0.03, [accent])
            skirt.position = SCNVector3(sx * 0.87, 0.30, 0)
            root.addChildNode(skirt)
        }

        // sloped hood (engine sits under it)
        let hood = box(1.62, 0.07, 1.3, 0.03, [body])
        hood.position = SCNVector3(0, 0.90, 1.30)
        hood.eulerAngles.x = 0.06
        root.addChildNode(hood)
        let engine = SCNNode(geometry: SCNBox(width: 1.0, height: 0.4, length: 0.9, chamferRadius: 0.04))
        (engine.geometry as? SCNBox)?.materials = [Mat.steelDark]
        engine.position = SCNVector3(0, 0.72, 1.4)
        engine.name = "part_engine"
        root.addChildNode(engine)
        partNodes["engine"] = engine

        // sloped nose
        let nose = box(1.70, 0.42, 0.55, 0.10, [body])
        nose.position = SCNVector3(0, 0.60, 1.85)
        nose.eulerAngles.x = 0.28
        root.addChildNode(nose)

        // trunk deck
        let trunk = box(1.62, 0.07, 0.9, 0.03, [body])
        trunk.position = SCNVector3(0, 0.88, -1.55)
        root.addChildNode(trunk)

        // greenhouse: dark interior visible through glass
        let interior = box(1.30, 0.42, 1.55, 0.05, [interiorMat])
        interior.position = SCNVector3(0, 1.06, -0.30)
        root.addChildNode(interior)
        let dash = box(1.26, 0.16, 0.30, 0.03, [interiorMat])
        dash.position = SCNVector3(0, 1.16, 0.32)
        root.addChildNode(dash)
        for sx in [-1, 1] as [Float] {
            let seat = box(0.50, 0.55, 0.45, 0.06, [seatMat])
            seat.position = SCNVector3(sx * 0.33, 1.02, -0.62)
            root.addChildNode(seat)
            let headrest = box(0.22, 0.16, 0.10, 0.03, [seatMat])
            headrest.position = SCNVector3(sx * 0.33, 1.38, -0.72)
            root.addChildNode(headrest)
        }
        let wheel1 = SCNNode(geometry: SCNTorus(ringRadius: 0.13, pipeRadius: 0.018))
        (wheel1.geometry as? SCNTorus)?.materials = [interiorMat]
        wheel1.position = SCNVector3(-0.33, 1.18, 0.12)
        wheel1.eulerAngles.x = -1.1
        root.addChildNode(wheel1)

        // roof
        let roof = box(1.38, 0.06, 1.45, 0.03, [body])
        roof.position = SCNVector3(0, 1.42, -0.42)
        root.addChildNode(roof)

        // windshield (part): raked glass between hood and roof
        let shield = box(1.30, 0.68, 0.04, 0.01, [Mat.glass])
        shield.position = SCNVector3(0, 1.14, 0.55)
        shield.eulerAngles.x = 0.86
        shield.name = "part_windshield"
        root.addChildNode(shield)
        partNodes["windshield"] = shield

        // rear window
        let rearWin = box(1.26, 0.55, 0.04, 0.01, [Mat.glass])
        rearWin.position = SCNVector3(0, 1.18, -1.02)
        rearWin.eulerAngles.x = -0.62
        root.addChildNode(rearWin)

        // side windows
        for sx in [-1, 1] as [Float] {
            let side = box(0.03, 0.34, 1.42, 0.01, [Mat.glass])
            side.position = SCNVector3(sx * 0.66, 1.16, -0.40)
            root.addChildNode(side)
            // chrome beltline trim under the glass
            let trim = box(0.02, 0.03, 1.50, 0.005, [Mat.chrome])
            trim.position = SCNVector3(sx * 0.67, 0.97, -0.40)
            root.addChildNode(trim)
        }

        // pillars
        for sx in [-1, 1] as [Float] {
            let ap = box(0.05, 0.62, 0.05, 0.01, [body])
            ap.position = SCNVector3(sx * 0.62, 1.14, 0.42)
            ap.eulerAngles.x = 0.86
            root.addChildNode(ap)
            let bp = box(0.045, 0.40, 0.045, 0.01, [body])
            bp.position = SCNVector3(sx * 0.66, 1.16, -0.30)
            root.addChildNode(bp)
            let cp = box(0.06, 0.55, 0.06, 0.01, [body])
            cp.position = SCNVector3(sx * 0.62, 1.16, -0.95)
            cp.eulerAngles.x = -0.62
            root.addChildNode(cp)
        }

        // driver door (part) + passenger door panel
        let door = box(0.06, 0.5, 1.0, 0.02, [body])
        door.position = SCNVector3(-0.90, 0.60, -0.05)
        door.name = "part_door"
        root.addChildNode(door)
        partNodes["door"] = door
        let doorR = box(0.06, 0.5, 1.0, 0.02, [body])
        doorR.position = SCNVector3(0.90, 0.60, -0.05)
        root.addChildNode(doorR)

        // bumpers
        let bf = box(1.8, 0.25, 0.25, 0.06, [accent])
        bf.position = SCNVector3(0, 0.35, 2.05)
        root.addChildNode(bf)
        let bb = box(1.8, 0.25, 0.25, 0.06, [accent])
        bb.position = SCNVector3(0, 0.35, -2.05)
        root.addChildNode(bb)

        // headlights with chrome bezels
        for dx in [-0.62, 0.62] as [Float] {
            let hl = SCNNode(geometry: SCNSphere(radius: 0.12))
            let m = SCNMaterial()
            m.emission.contents = UIColor(white: 0.9, alpha: 1)
            (hl.geometry as? SCNSphere)?.materials = [m]
            hl.position = SCNVector3(dx, 0.60, 2.08)
            root.addChildNode(hl)
            let bezel = SCNNode(geometry: SCNTorus(ringRadius: 0.13, pipeRadius: 0.025))
            bezel.position = SCNVector3(dx, 0.60, 2.10)
            (bezel.geometry as? SCNTorus)?.materials = [Mat.chrome]
            root.addChildNode(bezel)
        }

        // grille with chrome slats
        let grille = box(0.9, 0.16, 0.05, 0.02, [Mat.steelDark])
        grille.position = SCNVector3(0, 0.55, 2.10)
        root.addChildNode(grille)
        for i in 0..<3 {
            let slat = box(0.84, 0.02, 0.02, 0.005, [Mat.chrome])
            slat.position = SCNVector3(0, 0.51 + Float(i) * 0.05, 2.13)
            root.addChildNode(slat)
        }

        // taillights
        for dx in [-0.62, 0.62] as [Float] {
            let tl = box(0.30, 0.10, 0.05, 0.02, {
                let m = SCNMaterial()
                m.emission.contents = UIColor(red: 0.9, green: 0.08, blue: 0.08, alpha: 1)
                m.diffuse.contents = UIColor.black
                return [m]
            }())
            tl.position = SCNVector3(dx, 0.62, -2.01)
            root.addChildNode(tl)
        }

        // side mirrors
        for sx in [-1, 1] as [Float] {
            let stalk = box(0.04, 0.04, 0.14, 0.01, [accent])
            stalk.position = SCNVector3(sx * 0.93, 0.98, 0.42)
            root.addChildNode(stalk)
            let mirror = box(0.05, 0.12, 0.18, 0.02, [body])
            mirror.position = SCNVector3(sx * 0.99, 0.99, 0.48)
            root.addChildNode(mirror)
        }

        // door handles
        for sx in [-1, 1] as [Float] {
            let handle = box(0.03, 0.04, 0.22, 0.01, [Mat.chrome])
            handle.position = SCNVector3(sx * 0.90, 0.78, -0.35)
            root.addChildNode(handle)
        }

        // rear plate
        let plate = box(0.42, 0.13, 0.02, 0.01, [Mat.flat(0.92, 0.92, 0.88, rough: 0.6)])
        plate.position = SCNVector3(0, 0.42, -2.18)
        root.addChildNode(plate)

        // exhaust (part)
        let ex = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.5))
        (ex.geometry as? SCNCylinder)?.materials = [Mat.steel]
        ex.eulerAngles.x = .pi / 2
        ex.position = SCNVector3(0.35, 0.25, -2.15)
        ex.name = "part_exhaust"
        root.addChildNode(ex)
        partNodes["exhaust"] = ex

        // wheels (parts): torus tire, rim ring, spokes, hub
        for (id, x, z) in [("wheelFL", Float(-0.85), Float(1.30)),
                           ("wheelFR", Float(0.85), Float(1.30)),
                           ("wheelRL", Float(-0.85), Float(-1.30)),
                           ("wheelRR", Float(0.85), Float(-1.30))] {
            let wheel = SCNNode()
            wheel.name = "part_\(id)"
            let tire = SCNNode(geometry: SCNTorus(ringRadius: 0.25, pipeRadius: 0.10))
            (tire.geometry as? SCNTorus)?.materials = [Mat.rubber]
            tire.eulerAngles.z = .pi / 2 // torus axis is Y; roll it onto the axle (X)
            wheel.addChildNode(tire)
            let rim = SCNNode(geometry: SCNCylinder(radius: 0.16, height: 0.20))
            (rim.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
            rim.eulerAngles.z = .pi / 2
            wheel.addChildNode(rim)
            let rimRing = SCNNode(geometry: SCNTorus(ringRadius: 0.16, pipeRadius: 0.018))
            (rimRing.geometry as? SCNTorus)?.materials = [Mat.chrome]
            rimRing.eulerAngles.z = .pi / 2
            wheel.addChildNode(rimRing)
            for i in 0..<6 {
                let spoke = SCNNode(geometry: SCNBox(width: 0.06, height: 0.26, length: 0.07, chamferRadius: 0.01))
                (spoke.geometry as? SCNBox)?.materials = [Mat.steel]
                spoke.eulerAngles.x = Float(i) * .pi / 3
                wheel.addChildNode(spoke)
            }
            let hub = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.24))
            (hub.geometry as? SCNCylinder)?.materials = [Mat.chrome]
            hub.eulerAngles.z = .pi / 2
            wheel.addChildNode(hub)
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

        // repair markers: small halo rings hugging the broken part, one slow
        // spin + gentle pulse, colored per required tool. No floating pyramids.
        let haloLift: [String: Float] = ["exhaust": 0.16, "engine": 0.24, "windshield": 0.30]
        for p in def.parts {
            guard let anchor = partNodes[p.id] else { continue }
            let holder = SCNNode()
            holder.position = SCNVector3(anchor.position.x, anchor.position.y + (haloLift[p.id] ?? 0.30), anchor.position.z)
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.14, pipeRadius: 0.013))
            let m = SCNMaterial()
            m.emission.contents = GameContent.tools[p.tool]?.color ?? UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
            m.diffuse.contents = UIColor.black
            (ring.geometry as? SCNTorus)?.materials = [m]
            ring.eulerAngles.x = .pi / 2
            holder.addChildNode(ring)
            holder.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3.2)))
            ring.runAction(.repeatForever(.sequence([
                .scale(to: 1.18, duration: 0.8),
                .scale(to: 1.0, duration: 0.8),
            ])))
            root.addChildNode(holder)
            markers[p.id] = holder
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
            else { node.geometry?.materials = [Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.25, metal: 0.85)]; node.eulerAngles.y = 0 }
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

    static func makeLabelImage(name: String, color: UIColor) -> UIImage {
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
