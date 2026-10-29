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
        let body = Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.30, metal: 0.55)
        body.specular.contents = UIColor(white: 0.9, alpha: 1)
        let accent = Mat.flat(def.accentRGB.0, def.accentRGB.1, def.accentRGB.2, rough: 0.5, metal: 0.6)
        let interiorMat = Mat.flat(0.34, 0.33, 0.36, rough: 0.9)
        interiorMat.emission.contents = UIColor(white: 0.18, alpha: 1)
        let seatMat = Mat.flat(0.48, 0.42, 0.36, rough: 0.85)
        seatMat.emission.contents = UIColor(white: 0.20, alpha: 1)

        // MARK: mesh body shell (CC0 1.0 muscle car, grab3d.com - public
        // domain, no attribution required). Real modeled surfaces replace the
        // authored loft: hood scoop, bumpers, lights, mirrors, wheel arches
        // and glass come from the model. Engine bay, interior and repair
        // parts below stay authored and are positioned to match the shell
        // (front = +z, ground y = 0, wheel centers y 0.33/0.355).
        body.isDoubleSided = true
        root.addChildNode(CarMeshAsset.node("body", material: body))
        root.addChildNode(CarMeshAsset.node("glass", material: Mat.glass))

        // hood: separate baked panel hinged at its rear edge, propped open
        // so the bay is genuinely open to a standing mechanic
        let hood = CarMeshAsset.node("hood", material: body)
        hood.position = SCNVector3(CarMeshAsset.hoodPivot.x, CarMeshAsset.hoodPivot.y, CarMeshAsset.hoodPivot.z)
        hood.eulerAngles.x = -1.15
        root.addChildNode(hood)

        // MARK: engine bay (authored) - a recognizable motor sitting inside
        // the mesh bay opening. The whole group is lowered 0.22 so the block
        // clears the mesh fender line.
        let bay = SCNNode()
        bay.position = SCNVector3(0, -0.22, 0)
        root.addChildNode(bay)
        let aluminum = Mat.flat(0.75, 0.76, 0.79, rough: 0.35, metal: 0.9)
        let blackPlastic = Mat.flat(0.07, 0.07, 0.08, rough: 0.85)
        let rubber = Mat.flat(0.05, 0.05, 0.05, rough: 0.95)
        let wireRed = Mat.flat(0.62, 0.10, 0.10, rough: 0.6)

        let bayFloor = box(1.42, 0.10, 1.90, 0.02, [Mat.flat(0.24, 0.24, 0.26, rough: 0.9)])
        bayFloor.position = SCNVector3(0, 0.71, 1.36)
        bay.addChildNode(bayFloor)
        let firewall = box(1.50, 0.30, 0.06, 0.01, [Mat.flat(0.15, 0.15, 0.16, rough: 0.9)])
        firewall.position = SCNVector3(0, 0.85, 0.62)
        bay.addChildNode(firewall)

        // engine block (the repairable part)
        let engine = SCNNode(geometry: SCNBox(width: 0.52, height: 0.24, length: 0.80, chamferRadius: 0.03))
        (engine.geometry as? SCNBox)?.materials = [Mat.flat(0.48, 0.49, 0.53, rough: 0.5, metal: 0.6)]
        engine.position = SCNVector3(0, 0.88, 1.30)
        engine.name = "part_engine"
        bay.addChildNode(engine)
        partNodes["engine"] = engine

        // cylinder head + red valve cover
        let head = box(0.46, 0.10, 0.74, 0.02, [aluminum])
        head.position = SCNVector3(0, 1.05, 1.30)
        bay.addChildNode(head)
        let cover = box(0.34, 0.09, 0.70, 0.035, [Mat.flat(0.58, 0.12, 0.12, rough: 0.4, metal: 0.3)])
        cover.position = SCNVector3(0, 1.135, 1.30)
        bay.addChildNode(cover)

        // ignition coils + plug wires
        for i in 0..<4 {
            let z: Float = 1.02 + Float(i) * 0.185
            let coil = box(0.09, 0.06, 0.12, 0.012, [blackPlastic])
            coil.position = SCNVector3(-0.19, 1.13, z)
            bay.addChildNode(coil)
            let wire = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.12))
            (wire.geometry as? SCNCylinder)?.materials = [wireRed]
            wire.position = SCNVector3(-0.24, 1.08, z)
            wire.eulerAngles.z = 0.5
            bay.addChildNode(wire)
        }

        // intake plenum, throttle body, intake tube, air box
        let plenum = box(0.16, 0.10, 0.52, 0.03, [blackPlastic])
        plenum.position = SCNVector3(0.19, 1.10, 1.28)
        bay.addChildNode(plenum)
        let throttle = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.09))
        (throttle.geometry as? SCNCylinder)?.materials = [aluminum]
        throttle.position = SCNVector3(0.19, 1.09, 1.60)
        throttle.eulerAngles.x = .pi / 2
        bay.addChildNode(throttle)
        let tube1 = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 0.30))
        (tube1.geometry as? SCNCylinder)?.materials = [rubber]
        tube1.position = SCNVector3(0.28, 0.99, 1.68)
        tube1.eulerAngles.z = -0.9
        bay.addChildNode(tube1)
        let airbox = box(0.24, 0.17, 0.28, 0.04, [blackPlastic])
        airbox.position = SCNVector3(0.40, 0.90, 1.70)
        bay.addChildNode(airbox)

        // battery + terminals
        let battery = box(0.24, 0.20, 0.18, 0.02, [blackPlastic])
        battery.position = SCNVector3(-0.57, 0.93, 1.02)
        bay.addChildNode(battery)
        let posTerm = box(0.045, 0.035, 0.045, 0.008, [wireRed])
        posTerm.position = SCNVector3(-0.62, 1.03, 1.02)
        bay.addChildNode(posTerm)
        let negTerm = box(0.045, 0.03, 0.045, 0.008, [blackPlastic])
        negTerm.position = SCNVector3(-0.52, 1.03, 1.02)
        bay.addChildNode(negTerm)

        // radiator + cap + upper hose
        let radiator = box(0.90, 0.26, 0.06, 0.01, [Mat.flat(0.25, 0.26, 0.28, rough: 0.6, metal: 0.4)])
        radiator.position = SCNVector3(0, 0.92, 1.80)
        bay.addChildNode(radiator)
        let radCap = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.03))
        (radCap.geometry as? SCNCylinder)?.materials = [Mat.steel]
        radCap.position = SCNVector3(0.25, 1.065, 1.80)
        bay.addChildNode(radCap)
        let hose1 = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.42))
        (hose1.geometry as? SCNCylinder)?.materials = [rubber]
        hose1.position = SCNVector3(0.13, 1.08, 1.62)
        hose1.eulerAngles.x = 1.1
        bay.addChildNode(hose1)

        // exhaust manifold: 4 pipes down the left side
        for i in 0..<4 {
            let z: Float = 1.06 + Float(i) * 0.16
            let pipe = SCNNode(geometry: SCNCylinder(radius: 0.024, height: 0.20))
            (pipe.geometry as? SCNCylinder)?.materials = [Mat.flat(0.45, 0.30, 0.20, rough: 0.6, metal: 0.6)]
            pipe.position = SCNVector3(-0.29, 0.92, z)
            pipe.eulerAngles.z = -0.45
            bay.addChildNode(pipe)
        }

        // belt drive: crank pulley, alternator, belt loop
        let crank = SCNNode(geometry: SCNCylinder(radius: 0.065, height: 0.05))
        (crank.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
        crank.position = SCNVector3(0.06, 0.80, 1.71)
        crank.eulerAngles.x = .pi / 2
        bay.addChildNode(crank)
        let alternator = SCNNode(geometry: SCNCylinder(radius: 0.075, height: 0.11))
        (alternator.geometry as? SCNCylinder)?.materials = [aluminum]
        alternator.position = SCNVector3(-0.24, 0.98, 1.66)
        alternator.eulerAngles.x = .pi / 2
        bay.addChildNode(alternator)
        let belt = SCNNode(geometry: SCNTorus(ringRadius: 0.17, pipeRadius: 0.014))
        (belt.geometry as? SCNTorus)?.materials = [rubber]
        belt.position = SCNVector3(-0.09, 0.89, 1.70)
        belt.eulerAngles.x = .pi / 2
        belt.scale = SCNVector3(0.75, 1.0, 1.15)
        bay.addChildNode(belt)

        // brake booster on the firewall
        let booster = SCNNode(geometry: SCNCylinder(radius: 0.085, height: 0.07))
        (booster.geometry as? SCNCylinder)?.materials = [blackPlastic]
        booster.position = SCNVector3(-0.42, 0.97, 0.60)
        booster.eulerAngles.x = .pi / 2
        bay.addChildNode(booster)

        // strut towers at the rear corners of the bay
        for sx in [-1, 1] as [Float] {
            let tower = SCNNode(geometry: SCNCylinder(radius: 0.09, height: 0.22))
            (tower.geometry as? SCNCylinder)?.materials = [Mat.flat(0.30, 0.31, 0.34, rough: 0.6, metal: 0.5)]
            tower.position = SCNVector3(sx * 0.62, 0.92, 0.82)
            bay.addChildNode(tower)
            let capNut = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.03))
            (capNut.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
            capNut.position = SCNVector3(sx * 0.62, 1.04, 0.82)
            bay.addChildNode(capNut)
        }

        // coolant reservoir (translucent tank, cap) by the radiator
        let coolant = box(0.21, 0.18, 0.16, 0.035, [{
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.85, green: 0.88, blue: 0.80, alpha: 0.75)
            m.roughness.contents = 0.3
            return m
        }()])
        coolant.position = SCNVector3(0.52, 0.96, 1.62)
        bay.addChildNode(coolant)
        let coolantCap = SCNNode(geometry: SCNCylinder(radius: 0.03, height: 0.03))
        (coolantCap.geometry as? SCNCylinder)?.materials = [blackPlastic]
        coolantCap.position = SCNVector3(0.52, 1.05, 1.62)
        bay.addChildNode(coolantCap)

        // fuse box on the left inner fender
        let fuse = box(0.22, 0.08, 0.16, 0.02, [blackPlastic])
        fuse.position = SCNVector3(-0.62, 1.00, 1.45)
        bay.addChildNode(fuse)

        // intake runners: four curved tubes from plenum to the head
        for i in 0..<4 {
            let z: Float = 1.02 + Float(i) * 0.185
            let runner = SCNNode(geometry: SCNCylinder(radius: 0.040, height: 0.16))
            (runner.geometry as? SCNCylinder)?.materials = [aluminum]
            runner.position = SCNVector3(0.13, 1.115, z)
            runner.eulerAngles.z = 1.05
            bay.addChildNode(runner)
        }

        // radiator fan + shroud behind the radiator
        let shroud = box(0.92, 0.28, 0.03, 0.01, [blackPlastic])
        shroud.position = SCNVector3(0, 0.92, 1.765)
        bay.addChildNode(shroud)
        let fan = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.035))
        (fan.geometry as? SCNCylinder)?.materials = [Mat.flat(0.16, 0.16, 0.18, rough: 0.8)]
        fan.position = SCNVector3(0.06, 0.92, 1.745)
        fan.eulerAngles.x = .pi / 2
        bay.addChildNode(fan)
        for i in 0..<4 {
            let blade = box(0.20, 0.055, 0.02, 0.008, [blackPlastic])
            blade.position = SCNVector3(0.06, 0.92, 1.755)
            blade.eulerAngles.z = Float(i) * .pi / 4
            bay.addChildNode(blade)
        }

        // lower radiator hose
        let hose2 = SCNNode(geometry: SCNCylinder(radius: 0.032, height: 0.30))
        (hose2.geometry as? SCNCylinder)?.materials = [rubber]
        hose2.position = SCNVector3(-0.20, 0.82, 1.66)
        hose2.eulerAngles.x = 1.2
        bay.addChildNode(hose2)

        // strut brace across the towers
        let brace = SCNNode(geometry: SCNCylinder(radius: 0.02, height: 1.24))
        (brace.geometry as? SCNCylinder)?.materials = [Mat.steel]
        brace.position = SCNVector3(0, 1.05, 0.82)
        brace.eulerAngles.z = .pi / 2
        bay.addChildNode(brace)

        // brake master cylinder next to the booster
        let master = box(0.09, 0.07, 0.14, 0.015, [aluminum])
        master.position = SCNVector3(-0.42, 1.055, 0.62)
        bay.addChildNode(master)

        // washer fluid tank (translucent white, black cap) front-left
        let washer = box(0.18, 0.14, 0.13, 0.03, [{
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.88, green: 0.90, blue: 0.86, alpha: 0.8)
            m.roughness.contents = 0.35
            return m
        }()])
        washer.position = SCNVector3(-0.55, 0.88, 1.82)
        bay.addChildNode(washer)
        let washerCap = SCNNode(geometry: SCNCylinder(radius: 0.028, height: 0.025))
        (washerCap.geometry as? SCNCylinder)?.materials = [blackPlastic]
        washerCap.position = SCNVector3(-0.55, 0.95, 1.82)
        bay.addChildNode(washerCap)

        // hood prop rod leaning back to the open mesh hood underside
        let prop = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 1.05))
        (prop.geometry as? SCNCylinder)?.materials = [Mat.steel]
        prop.position = SCNVector3(0.52, 1.22, 0.72)
        prop.eulerAngles = SCNVector3(0.42, 0, 0.08)
        bay.addChildNode(prop)

        // MARK: interior (authored) lowered into the mesh cabin
        let cabin = SCNNode()
        cabin.position = SCNVector3(0, -0.13, 0)
        root.addChildNode(cabin)
        let interior = box(1.22, 0.32, 1.50, 0.05, [interiorMat])
        interior.position = SCNVector3(0, 0.97, -0.30)
        cabin.addChildNode(interior)
        let dash = box(1.26, 0.16, 0.30, 0.03, [interiorMat])
        dash.position = SCNVector3(0, 1.08, 0.32)
        cabin.addChildNode(dash)
        for sx in [-1, 1] as [Float] {
            let seat = box(0.50, 0.55, 0.45, 0.06, [seatMat])
            seat.position = SCNVector3(sx * 0.33, 0.96, -0.62)
            cabin.addChildNode(seat)
            let headrest = box(0.22, 0.16, 0.10, 0.03, [seatMat])
            headrest.position = SCNVector3(sx * 0.33, 1.24, -0.72)
            cabin.addChildNode(headrest)
        }
        let wheel1 = SCNNode(geometry: SCNTorus(ringRadius: 0.13, pipeRadius: 0.018))
        (wheel1.geometry as? SCNTorus)?.materials = [interiorMat]
        wheel1.position = SCNVector3(-0.33, 1.10, 0.12)
        wheel1.eulerAngles.x = -1.1
        cabin.addChildNode(wheel1)

        // windshield repair overlay: the mesh glass always renders; this thin
        // panel carries the crack read and goes near-invisible when fixed
        let shield = box(1.30, 0.42, 0.03, 0.01, [crackedGlass()])
        shield.position = SCNVector3(0, 1.04, 0.30)
        shield.eulerAngles.x = 0.60
        shield.name = "part_windshield"
        root.addChildNode(shield)
        partNodes["windshield"] = shield

        // driver door repair skin: the mesh body is one shell, so this
        // body-color patch carries the broken read (rusted, slightly ajar)
        // and sits flush with matching paint once fixed
        let door = box(0.03, 0.62, 1.10, 0.01, [body])
        door.position = SCNVector3(-0.955, 0.62, -0.05)
        door.name = "part_door"
        root.addChildNode(door)
        partNodes["door"] = door

        // exhaust (part)
        let ex = SCNNode(geometry: SCNCylinder(radius: 0.07, height: 0.5))
        (ex.geometry as? SCNCylinder)?.materials = [Mat.steel]
        ex.eulerAngles.x = .pi / 2
        ex.position = SCNVector3(0.35, 0.24, -2.44)
        ex.name = "part_exhaust"
        root.addChildNode(ex)
        partNodes["exhaust"] = ex

        // wheels (parts): real modeled tires + rims from the mesh pack,
        // baked centered so the repair squash and future removal work on
        // the wheel's own pivot. Mesh corner geometries face their own side.
        for (id, x, y, z, loc) in [("wheelFL", Float(-0.74), Float(0.33), Float(1.5183), "fr"),
                                   ("wheelFR", Float(0.74), Float(0.33), Float(1.5183), "fl"),
                                   ("wheelRL", Float(-0.76), Float(0.355), Float(-1.3417), "rr"),
                                   ("wheelRR", Float(0.76), Float(0.355), Float(-1.3417), "rl")] {
            let wheel = SCNNode()
            wheel.name = "part_\(id)"
            let rim = Mat.flat(0.75, 0.76, 0.80, rough: 0.25, metal: 0.9)
            let disc = Mat.flat(0.28, 0.28, 0.31, rough: 0.45, metal: 0.7)
            wheel.addChildNode(CarMeshAsset.node("wheel_\(loc)_0", material: Mat.rubber))
            wheel.addChildNode(CarMeshAsset.node("wheel_\(loc)_1", material: rim))
            wheel.addChildNode(CarMeshAsset.node("wheel_\(loc)_2", material: Mat.steelDark))
            wheel.addChildNode(CarMeshAsset.node("wheel_\(loc)_3", material: disc))
            wheel.position = SCNVector3(x, y, z)
            root.addChildNode(wheel)
            partNodes[id] = wheel
        }

        // spoiler for drift cars
        if def.hasSpoiler {
            let wing = box(1.5, 0.05, 0.30, 0.02, [accent])
            wing.position = SCNVector3(0, 1.22, -2.00)
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
            (anchor.parent ?? root).addChildNode(holder)
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
            g?.materials = fixed ? [clearGlass()] : [crackedGlass()]
        } else if id == "engine" || id == "exhaust" {
            if !fixed { node.geometry?.materials = [Mat.rust] }
            else { node.geometry?.materials = [id == "engine" ? Mat.steelDark : Mat.steel] }
        } else if id.hasPrefix("wheel") {
            // broken = flat: squash y; fixed = normal
            node.scale = SCNVector3(1, fixed ? 1 : 0.55, 1)
        } else if id == "door" {
            if !fixed { node.geometry?.materials = [Mat.flat(def.bodyRGB.0 * 0.4, def.bodyRGB.1 * 0.4, def.bodyRGB.2 * 0.4, rough: 0.9)] ; node.eulerAngles.y = 0.18 }
            else { node.geometry?.materials = [Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.25, metal: 0.85)]; node.eulerAngles.y = 0 }
        }
        _ = brokenTint
    }

    private func clearGlass() -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(white: 0.9, alpha: 0.04)
        m.isDoubleSided = true
        return m
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
