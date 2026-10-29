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
        interiorMat.emission.contents = UIColor(white: 0.10, alpha: 1)
        let seatMat = Mat.flat(0.30, 0.28, 0.26, rough: 0.85)
        seatMat.emission.contents = UIColor(white: 0.12, alpha: 1)

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

        // hood propped open, hinged at its rear edge: mechanic-game look and
        // the engine block is genuinely visible in the bay below it
        let hood = box(1.62, 0.07, 1.3, 0.03, [body])
        hood.position = SCNVector3(0, 0.90, 1.30)
        hood.pivot = SCNMatrix4MakeTranslation(0, 0, -0.60)
        hood.eulerAngles.x = -1.15 // propped wide (~66 deg) so the bay is open to a standing mechanic
        root.addChildNode(hood)
        // MARK: engine bay - a recognizable motor, not a textured block.
        // block + head + valve cover, coils and plug wires, intake plenum and
        // throttle body, intake tube to an air box, battery, radiator with cap
        // and upper hose, exhaust manifold pipes, belt drive (crank, alternator,
        // belt loop), brake booster on the firewall, inner fenders.
        let aluminum = Mat.flat(0.75, 0.76, 0.79, rough: 0.35, metal: 0.9)
        let blackPlastic = Mat.flat(0.07, 0.07, 0.08, rough: 0.85)
        let rubber = Mat.flat(0.05, 0.05, 0.05, rough: 0.95)
        let wireRed = Mat.flat(0.62, 0.10, 0.10, rough: 0.6)

        // bay walls: inner fenders + firewall
        for sx in [-1, 1] as [Float] {
            let fender = box(0.07, 0.14, 1.35, 0.02, [Mat.flat(def.bodyRGB.0 * 0.5, def.bodyRGB.1 * 0.5, def.bodyRGB.2 * 0.5, rough: 0.7)])
            fender.position = SCNVector3(sx * 0.79, 0.86, 1.30)
            root.addChildNode(fender)
        }
        let firewall = box(1.58, 0.12, 0.05, 0.01, [Mat.flat(0.15, 0.15, 0.16, rough: 0.9)])
        firewall.position = SCNVector3(0, 0.88, 0.66)
        root.addChildNode(firewall)

        // engine block (the repairable part)
        let engine = SCNNode(geometry: SCNBox(width: 0.52, height: 0.24, length: 0.80, chamferRadius: 0.03))
        (engine.geometry as? SCNBox)?.materials = [Mat.steelDark]
        engine.position = SCNVector3(0, 0.88, 1.30)
        engine.name = "part_engine"
        root.addChildNode(engine)
        partNodes["engine"] = engine

        // cylinder head + red valve cover
        let head = box(0.46, 0.10, 0.74, 0.02, [aluminum])
        head.position = SCNVector3(0, 1.05, 1.30)
        root.addChildNode(head)
        let cover = box(0.30, 0.07, 0.70, 0.03, [Mat.flat(0.55, 0.12, 0.12, rough: 0.4, metal: 0.3)])
        cover.position = SCNVector3(0, 1.135, 1.30)
        root.addChildNode(cover)

        // ignition coils + plug wires
        for i in 0..<4 {
            let z: Float = 1.02 + Float(i) * 0.185
            let coil = box(0.07, 0.05, 0.10, 0.01, [blackPlastic])
            coil.position = SCNVector3(-0.19, 1.13, z)
            root.addChildNode(coil)
            let wire = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.12))
            (wire.geometry as? SCNCylinder)?.materials = [wireRed]
            wire.position = SCNVector3(-0.24, 1.08, z)
            wire.eulerAngles.z = 0.5
            root.addChildNode(wire)
        }

        // intake plenum, throttle body, intake tube, air box
        let plenum = box(0.16, 0.10, 0.52, 0.03, [blackPlastic])
        plenum.position = SCNVector3(0.19, 1.10, 1.28)
        root.addChildNode(plenum)
        let throttle = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.09))
        (throttle.geometry as? SCNCylinder)?.materials = [aluminum]
        throttle.position = SCNVector3(0.19, 1.09, 1.60)
        throttle.eulerAngles.x = .pi / 2
        root.addChildNode(throttle)
        let tube1 = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.30))
        (tube1.geometry as? SCNCylinder)?.materials = [rubber]
        tube1.position = SCNVector3(0.36, 1.02, 1.66)
        tube1.eulerAngles.z = -0.9
        root.addChildNode(tube1)
        let airbox = box(0.24, 0.17, 0.28, 0.04, [blackPlastic])
        airbox.position = SCNVector3(0.55, 0.94, 1.66)
        root.addChildNode(airbox)

        // battery + terminals
        let battery = box(0.20, 0.17, 0.15, 0.02, [blackPlastic])
        battery.position = SCNVector3(-0.57, 0.93, 1.02)
        root.addChildNode(battery)
        let posTerm = box(0.045, 0.035, 0.045, 0.008, [wireRed])
        posTerm.position = SCNVector3(-0.62, 1.03, 1.02)
        root.addChildNode(posTerm)
        let negTerm = box(0.045, 0.03, 0.045, 0.008, [blackPlastic])
        negTerm.position = SCNVector3(-0.52, 1.03, 1.02)
        root.addChildNode(negTerm)

        // radiator + cap + upper hose
        let radiator = box(0.90, 0.26, 0.06, 0.01, [Mat.flat(0.25, 0.26, 0.28, rough: 0.6, metal: 0.4)])
        radiator.position = SCNVector3(0, 0.92, 1.80)
        root.addChildNode(radiator)
        let radCap = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.03))
        (radCap.geometry as? SCNCylinder)?.materials = [Mat.steel]
        radCap.position = SCNVector3(0.25, 1.065, 1.80)
        root.addChildNode(radCap)
        let hose1 = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.42))
        (hose1.geometry as? SCNCylinder)?.materials = [rubber]
        hose1.position = SCNVector3(0.13, 1.08, 1.62)
        hose1.eulerAngles.x = 1.1
        root.addChildNode(hose1)

        // exhaust manifold: 4 pipes down the left side
        for i in 0..<4 {
            let z: Float = 1.06 + Float(i) * 0.16
            let pipe = SCNNode(geometry: SCNCylinder(radius: 0.024, height: 0.20))
            (pipe.geometry as? SCNCylinder)?.materials = [Mat.flat(0.45, 0.30, 0.20, rough: 0.6, metal: 0.6)]
            pipe.position = SCNVector3(-0.29, 0.92, z)
            pipe.eulerAngles.z = -0.45
            root.addChildNode(pipe)
        }

        // belt drive: crank pulley, alternator, belt loop
        let crank = SCNNode(geometry: SCNCylinder(radius: 0.065, height: 0.05))
        (crank.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
        crank.position = SCNVector3(0.06, 0.80, 1.71)
        crank.eulerAngles.x = .pi / 2
        root.addChildNode(crank)
        let alternator = SCNNode(geometry: SCNCylinder(radius: 0.075, height: 0.11))
        (alternator.geometry as? SCNCylinder)?.materials = [aluminum]
        alternator.position = SCNVector3(-0.24, 0.98, 1.66)
        alternator.eulerAngles.x = .pi / 2
        root.addChildNode(alternator)
        let belt = SCNNode(geometry: SCNTorus(ringRadius: 0.17, pipeRadius: 0.014))
        (belt.geometry as? SCNTorus)?.materials = [rubber]
        belt.position = SCNVector3(-0.09, 0.89, 1.70)
        belt.eulerAngles.x = .pi / 2
        belt.scale = SCNVector3(0.75, 1.0, 1.15)
        root.addChildNode(belt)

        // brake booster on the firewall
        let booster = SCNNode(geometry: SCNCylinder(radius: 0.085, height: 0.07))
        (booster.geometry as? SCNCylinder)?.materials = [blackPlastic]
        booster.position = SCNVector3(-0.42, 0.97, 0.60)
        booster.eulerAngles.x = .pi / 2
        root.addChildNode(booster)

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
        let haloLift: [String: Float] = ["exhaust": 0.30, "engine": 0.42, "windshield": 0.40]
        for p in def.parts {
            guard let anchor = partNodes[p.id] else { continue }
            let holder = SCNNode()
            // lift above the part, then push the ring clear of the body so
            // panels stop biting its edge, while depth testing stays on so
            // markers never show through the car. Flank parts (wheels, door)
            // push straight OUT sideways: a radial push shoves the front
            // wheels' rings toward the bumper and the arch lip still clips
            // them. Centerline parts (engine, windshield, exhaust) push
            // radially away from the body axis.
            let push: Float = 0.30
            let flank = abs(anchor.position.x) > 0.5
            let alen = max(0.001, hypotf(anchor.position.x, anchor.position.z))
            let px = flank ? anchor.position.x + (anchor.position.x >= 0 ? push : -push)
                           : anchor.position.x + anchor.position.x / alen * push
            let pz = flank ? anchor.position.z
                           : anchor.position.z + anchor.position.z / alen * push
            holder.position = SCNVector3(px,
                                         anchor.position.y + (haloLift[p.id] ?? 0.40),
                                         pz)
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.12, pipeRadius: 0.012))
            let m = SCNMaterial()
            m.emission.contents = GameContent.tools[p.tool]?.color ?? UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
            m.diffuse.contents = UIColor.black
            (ring.geometry as? SCNTorus)?.materials = [m]
            ring.eulerAngles.x = .pi / 2 // stand the flat torus up, facing +/-z
            // billboard carrier: the ring always faces the camera as a full circle,
            // so body panels no longer slice it into broken arcs. Depth testing
            // stays ON: a part hidden behind the car keeps its marker hidden too.
            let face = SCNNode()
            face.constraints = [SCNBillboardConstraint()]
            face.addChildNode(ring)
            holder.addChildNode(face)
            ring.runAction(.repeatForever(.sequence([
                .scale(to: 1.10, duration: 0.8),
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
