import Foundation
import SceneKit
import UIKit

// MARK: - Car assembly from primitives. Node names carry part ids for damage state.

final class CarAssembly {
    let root = SCNNode()
    let def: CarDef
    private(set) var partNodes: [String: SCNNode] = [:]
    private var wheelBaseY: [String: Float] = [:]
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

        // hood prop rod: spans the radiator support up to the open mesh hood
        // underside (leaning back, classic prop stance, actually touching both)
        let prop = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 1.29))
        (prop.geometry as? SCNCylinder)?.materials = [Mat.steel]
        prop.position = SCNVector3(0.45, 1.368, 1.27)
        prop.eulerAngles = SCNVector3(-0.843, 0, 0)
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

        // driver door repair skin: curved mesh baked from the shell surface
        // (1.5mm proud), hinged at its front edge so the broken read is a
        // real ajar door and the fixed read is flush matching paint
        let door = SCNNode(geometry: CarAssembly.doorSkinGeometry())
        door.geometry?.materials = [body]
        door.position = SCNVector3(-0.80, 0.62, 0.50) // hinge: front edge
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
            wheelBaseY[id] = y
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
        // the door node sits at its front-edge hinge for the ajar pivot; pull
        // its marker ring back to mid-door so it marks the panel, not the fender
        let markerZNudge: [String: Float] = ["door": -0.55]
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
            let pz = flank ? anchor.position.z + (markerZNudge[p.id] ?? 0)
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
            // broken = flat: squash y anchored at the contact patch (the
            // squash alone would lift the tire off the ground); fixed = normal
            node.scale = SCNVector3(1, fixed ? 1 : 0.55, 1)
            if let baseY = wheelBaseY[id] {
                node.position.y = fixed ? baseY : baseY * 0.55
            }
        } else if id == "door" {
            if !fixed { node.geometry?.materials = [Mat.flat(def.bodyRGB.0 * 0.4, def.bodyRGB.1 * 0.4, def.bodyRGB.2 * 0.4, rough: 0.9)] ; node.eulerAngles.y = 0.18 }
            else { node.geometry?.materials = [Mat.flat(def.bodyRGB.0, def.bodyRGB.1, def.bodyRGB.2, rough: 0.25, metal: 0.85)]; node.eulerAngles.y = 0 }
        }
        _ = brokenTint
    }

    // baked curved door skin: sampled from the body shell (door region),
    // 1.5mm proud, vertices relative to the front-edge hinge point
    private static let doorSkinPos: [Float] = [-0.07018, -0.31000, -1.10000, -0.06974, -0.31000, -1.05000, -0.06952, -0.31000, -1.00000, -0.07115, -0.31000, -0.95000, -0.07019, -0.31000, -0.90000, -0.06951, -0.31000, -0.85000, -0.06963, -0.31000, -0.80000, -0.06966, -0.31000, -0.75000, -0.07105, -0.31000, -0.70000, -0.07000, -0.31000, -0.65000, -0.06969, -0.31000, -0.60000, -0.06975, -0.31000, -0.55000, -0.06955, -0.31000, -0.50000, -0.07088, -0.31000, -0.45000, -0.07044, -0.31000, -0.40000, -0.06951, -0.31000, -0.35000, -0.06973, -0.31000, -0.30000, -0.06972, -0.31000, -0.25000, -0.07051, -0.31000, -0.20000, -0.07021, -0.31000, -0.15000, -0.06970, -0.31000, -0.10000, -0.06958, -0.31000, -0.05000, -0.06979, -0.31000, 0.00000, -0.06817, -0.25833, -1.10000, -0.06821, -0.25833, -1.05000, -0.06774, -0.25833, -1.00000, -0.06815, -0.25833, -0.95000, -0.06815, -0.25833, -0.90000, -0.06777, -0.25833, -0.85000, -0.06815, -0.25833, -0.80000, -0.06814, -0.25833, -0.75000, -0.06810, -0.25833, -0.70000, -0.06815, -0.25833, -0.65000, -0.06791, -0.25833, -0.60000, -0.06802, -0.25833, -0.55000, -0.06817, -0.25833, -0.50000, -0.06810, -0.25833, -0.45000, -0.06810, -0.25833, -0.40000, -0.06815, -0.25833, -0.35000, -0.06826, -0.25833, -0.30000, -0.06799, -0.25833, -0.25000, -0.06816, -0.25833, -0.20000, -0.06808, -0.25833, -0.15000, -0.06794, -0.25833, -0.10000, -0.06819, -0.25833, -0.05000, -0.06823, -0.25833, 0.00000, -0.06383, -0.20667, -1.10000, -0.06383, -0.20667, -1.05000, -0.06389, -0.20667, -1.00000, -0.06372, -0.20667, -0.95000, -0.06343, -0.20667, -0.90000, -0.06387, -0.20667, -0.85000, -0.06364, -0.20667, -0.80000, -0.06354, -0.20667, -0.75000, -0.06350, -0.20667, -0.70000, -0.06336, -0.20667, -0.65000, -0.06364, -0.20667, -0.60000, -0.06347, -0.20667, -0.55000, -0.06335, -0.20667, -0.50000, -0.06339, -0.20667, -0.45000, -0.06367, -0.20667, -0.40000, -0.06334, -0.20667, -0.35000, -0.06341, -0.20667, -0.30000, -0.06366, -0.20667, -0.25000, -0.06322, -0.20667, -0.20000, -0.06382, -0.20667, -0.15000, -0.06336, -0.20667, -0.10000, -0.06329, -0.20667, -0.05000, -0.06340, -0.20667, 0.00000, -0.05998, -0.15500, -1.10000, -0.05988, -0.15500, -1.05000, -0.05929, -0.15500, -1.00000, -0.05966, -0.15500, -0.95000, -0.05952, -0.15500, -0.90000, -0.05897, -0.15500, -0.85000, -0.05949, -0.15500, -0.80000, -0.05931, -0.15500, -0.75000, -0.05925, -0.15500, -0.70000, -0.05948, -0.15500, -0.65000, -0.05930, -0.15500, -0.60000, -0.05893, -0.15500, -0.55000, -0.05935, -0.15500, -0.50000, -0.05912, -0.15500, -0.45000, -0.05892, -0.15500, -0.40000, -0.05936, -0.15500, -0.35000, -0.05889, -0.15500, -0.30000, -0.05893, -0.15500, -0.25000, -0.05931, -0.15500, -0.20000, -0.05882, -0.15500, -0.15000, -0.05885, -0.15500, -0.10000, -0.05903, -0.15500, -0.05000, -0.05869, -0.15500, 0.00000, -0.05555, -0.10333, -1.10000, -0.05497, -0.10333, -1.05000, -0.05543, -0.10333, -1.00000, -0.05499, -0.10333, -0.95000, -0.05500, -0.10333, -0.90000, -0.05502, -0.10333, -0.85000, -0.05491, -0.10333, -0.80000, -0.05493, -0.10333, -0.75000, -0.05498, -0.10333, -0.70000, -0.05489, -0.10333, -0.65000, -0.05486, -0.10333, -0.60000, -0.05525, -0.10333, -0.55000, -0.05484, -0.10333, -0.50000, -0.05489, -0.10333, -0.45000, -0.05488, -0.10333, -0.40000, -0.05482, -0.10333, -0.35000, -0.05501, -0.10333, -0.30000, -0.05494, -0.10333, -0.25000, -0.05483, -0.10333, -0.20000, -0.05480, -0.10333, -0.15000, -0.05466, -0.10333, -0.10000, -0.05485, -0.10333, -0.05000, -0.05494, -0.10333, 0.00000, -0.05129, -0.05167, -1.10000, -0.05140, -0.05167, -1.05000, -0.05087, -0.05167, -1.00000, -0.05103, -0.05167, -0.95000, -0.05091, -0.05167, -0.90000, -0.05110, -0.05167, -0.85000, -0.05096, -0.05167, -0.80000, -0.05087, -0.05167, -0.75000, -0.05107, -0.05167, -0.70000, -0.05076, -0.05167, -0.65000, -0.05095, -0.05167, -0.60000, -0.05069, -0.05167, -0.55000, -0.05051, -0.05167, -0.50000, -0.05032, -0.05167, -0.45000, -0.05052, -0.05167, -0.40000, -0.05053, -0.05167, -0.35000, -0.05051, -0.05167, -0.30000, -0.05048, -0.05167, -0.25000, -0.05008, -0.05167, -0.20000, -0.05057, -0.05167, -0.15000, -0.05011, -0.05167, -0.10000, -0.05002, -0.05167, -0.05000, -0.05012, -0.05167, 0.00000, -0.04687, 0.00000, -1.10000, -0.04670, 0.00000, -1.05000, -0.04700, 0.00000, -1.00000, -0.04647, 0.00000, -0.95000, -0.04649, 0.00000, -0.90000, -0.04655, 0.00000, -0.85000, -0.04647, 0.00000, -0.80000, -0.04650, 0.00000, -0.75000, -0.04635, 0.00000, -0.70000, -0.04644, 0.00000, -0.65000, -0.04625, 0.00000, -0.60000, -0.04610, 0.00000, -0.55000, -0.04642, 0.00000, -0.50000, -0.04623, 0.00000, -0.45000, -0.04605, 0.00000, -0.40000, -0.04637, 0.00000, -0.35000, -0.04572, 0.00000, -0.30000, -0.04580, 0.00000, -0.25000, -0.04626, 0.00000, -0.20000, -0.04559, 0.00000, -0.15000, -0.04564, 0.00000, -0.10000, -0.04587, 0.00000, -0.05000, -0.04541, 0.00000, 0.00000, -0.04382, 0.05167, -1.10000, -0.04217, 0.05167, -1.05000, -0.04242, 0.05167, -1.00000, -0.04269, 0.05167, -0.95000, -0.04262, 0.05167, -0.90000, -0.04200, 0.05167, -0.85000, -0.04206, 0.05167, -0.80000, -0.04218, 0.05167, -0.75000, -0.04191, 0.05167, -0.70000, -0.04201, 0.05167, -0.65000, -0.04178, 0.05167, -0.60000, -0.04208, 0.05167, -0.55000, -0.04166, 0.05167, -0.50000, -0.04172, 0.05167, -0.45000, -0.04171, 0.05167, -0.40000, -0.04151, 0.05167, -0.35000, -0.04180, 0.05167, -0.30000, -0.04169, 0.05167, -0.25000, -0.04151, 0.05167, -0.20000, -0.04155, 0.05167, -0.15000, -0.04138, 0.05167, -0.10000, -0.04152, 0.05167, -0.05000, -0.04167, 0.05167, 0.00000, -0.03823, 0.10333, -1.10000, -0.03833, 0.10333, -1.05000, -0.03803, 0.10333, -1.00000, -0.03816, 0.10333, -0.95000, -0.03804, 0.10333, -0.90000, -0.03798, 0.10333, -0.85000, -0.03813, 0.10333, -0.80000, -0.03809, 0.10333, -0.75000, -0.03801, 0.10333, -0.70000, -0.03798, 0.10333, -0.65000, -0.03813, 0.10333, -0.60000, -0.03791, 0.10333, -0.55000, -0.03796, 0.10333, -0.50000, -0.03759, 0.10333, -0.45000, -0.03739, 0.10333, -0.40000, -0.03774, 0.10333, -0.35000, -0.03739, 0.10333, -0.30000, -0.03734, 0.10333, -0.25000, -0.03708, 0.10333, -0.20000, -0.03734, 0.10333, -0.15000, -0.03714, 0.10333, -0.10000, -0.03689, 0.10333, -0.05000, -0.03684, 0.10333, 0.00000, -0.03426, 0.15500, -1.10000, -0.03405, 0.15500, -1.05000, -0.03395, 0.15500, -1.00000, -0.03365, 0.15500, -0.95000, -0.03347, 0.15500, -0.90000, -0.03350, 0.15500, -0.85000, -0.03896, 0.15500, -0.80000, -0.03722, 0.15500, -0.75000, -0.04088, 0.15500, -0.70000, -0.03312, 0.15500, -0.65000, -0.03322, 0.15500, -0.60000, -0.03325, 0.15500, -0.55000, -0.03318, 0.15500, -0.50000, -0.03335, 0.15500, -0.45000, -0.03281, 0.15500, -0.40000, -0.03316, 0.15500, -0.35000, -0.03271, 0.15500, -0.30000, -0.03262, 0.15500, -0.25000, -0.03304, 0.15500, -0.20000, -0.03224, 0.15500, -0.15000, -0.03218, 0.15500, -0.10000, -0.03218, 0.15500, -0.05000, -0.03158, 0.15500, 0.00000, -0.02700, 0.20667, -1.10000, -0.02725, 0.20667, -1.05000, -0.02678, 0.20667, -1.00000, -0.02667, 0.20667, -0.95000, -0.02673, 0.20667, -0.90000, -0.02674, 0.20667, -0.85000, -0.02948, 0.20667, -0.80000, -0.02850, 0.20667, -0.75000, -0.03596, 0.20667, -0.70000, -0.02609, 0.20667, -0.65000, -0.02560, 0.20667, -0.60000, -0.02551, 0.20667, -0.55000, -0.02565, 0.20667, -0.50000, -0.02523, 0.20667, -0.45000, -0.02528, 0.20667, -0.40000, -0.02484, 0.20667, -0.35000, -0.02374, 0.20667, -0.30000, -0.02425, 0.20667, -0.25000, -0.02432, 0.20667, -0.20000, -0.02326, 0.20667, -0.15000, -0.02331, 0.20667, -0.10000, -0.02326, 0.20667, -0.05000, -0.02280, 0.20667, 0.00000, 0.01393, 0.25833, -1.10000, 0.02983, 0.25833, -1.05000, 0.06548, 0.25833, -1.00000, 0.00406, 0.25833, -0.95000, 0.01227, 0.25833, -0.90000, 0.06344, 0.25833, -0.85000, 0.00650, 0.25833, -0.80000, 0.02701, 0.25833, -0.75000, 0.05904, 0.25833, -0.70000, 0.02057, 0.25833, -0.65000, 0.01757, 0.25833, -0.60000, 0.05841, 0.25833, -0.55000, 0.01422, 0.25833, -0.50000, 0.02755, 0.25833, -0.45000, 0.04829, 0.25833, -0.40000, 0.01832, 0.25833, -0.35000, 0.05013, 0.25833, -0.30000, 0.03830, 0.25833, -0.25000, 0.02503, 0.25833, -0.20000, 0.05892, 0.25833, -0.15000, -0.05468, 0.25833, -0.10000, -0.01494, 0.25833, -0.05000, 0.03661, 0.25833, 0.00000, 0.14348, 0.31000, -1.10000, 0.15419, 0.31000, -1.05000, 0.06963, 0.31000, -1.00000, 0.12856, 0.31000, -0.95000, 0.08366, 0.31000, -0.90000, 0.07592, 0.31000, -0.85000, 0.10419, 0.31000, -0.80000, 0.07860, 0.31000, -0.75000, 0.10189, 0.31000, -0.70000, 0.07545, 0.31000, -0.65000, 0.07568, 0.31000, -0.60000, 0.14720, 0.31000, -0.55000, 0.07222, 0.31000, -0.50000, 0.07708, 0.31000, -0.45000, 0.08291, 0.31000, -0.40000, 0.07484, 0.31000, -0.35000, 0.14693, 0.31000, -0.30000, 0.07735, 0.31000, -0.25000, 0.12206, 0.31000, -0.20000, 0.11930, 0.31000, -0.15000, -0.11990, 0.31000, -0.10000, 0.00764, 0.31000, -0.05000, -0.14412, 0.31000, 0.00000]
    private static let doorSkinNrm: [Float] = [-0.99920, 0.03888, 0.00886, -0.99954, 0.02949, 0.00656, -0.99931, 0.03445, -0.01416, -0.99829, 0.05808, -0.00671, -0.99909, 0.03945, 0.01639, -0.99942, 0.03361, 0.00569, -0.99959, 0.02855, -0.00149, -0.99947, 0.02943, -0.01422, -0.99838, 0.05688, -0.00341, -0.99926, 0.03591, 0.01359, -0.99941, 0.03438, 0.00249, -0.99944, 0.03350, 0.00137, -0.99958, 0.02679, -0.01130, -0.99852, 0.05371, -0.00888, -0.99888, 0.04535, 0.01369, -0.99963, 0.02635, 0.00710, -0.99959, 0.02839, -0.00207, -0.99941, 0.03346, -0.00776, -0.99895, 0.04546, -0.00488, -0.99912, 0.04126, 0.00808, -0.99940, 0.03403, 0.00634, -0.99964, 0.02679, -0.00090, -0.99954, 0.03008, -0.00428, -0.99812, 0.06132, -0.00085, -0.99836, 0.05702, 0.00427, -0.99852, 0.05446, 0.00064, -0.99741, 0.07177, -0.00413, -0.99785, 0.06537, 0.00371, -0.99851, 0.05451, 0.00005, -0.99832, 0.05780, -0.00364, -0.99825, 0.05917, 0.00045, -0.99734, 0.07288, -0.00007, -0.99794, 0.06420, 0.00193, -0.99829, 0.05845, 0.00124, -0.99815, 0.06071, -0.00256, -0.99820, 0.05989, -0.00083, -0.99738, 0.07229, 0.00071, -0.99786, 0.06535, -0.00047, -0.99822, 0.05959, -0.00167, -0.99813, 0.06103, 0.00160, -0.99828, 0.05855, 0.00107, -0.99752, 0.07037, -0.00085, -0.99809, 0.06169, 0.00216, -0.99813, 0.06119, -0.00114, -0.99815, 0.06075, -0.00294, -0.99810, 0.06168, -0.00088, -0.99687, 0.07900, -0.00007, -0.99676, 0.08039, -0.00056, -0.99667, 0.08155, 0.00116, -0.99663, 0.08186, 0.00460, -0.99653, 0.08324, -0.00153, -0.99639, 0.08485, -0.00217, -0.99650, 0.08349, 0.00334, -0.99636, 0.08518, 0.00146, -0.99634, 0.08542, 0.00180, -0.99650, 0.08358, -0.00140, -0.99654, 0.08307, -0.00113, -0.99615, 0.08760, 0.00285, -0.99638, 0.08500, 0.00075, -0.99624, 0.08659, -0.00321, -0.99608, 0.08845, 0.00049, -0.99640, 0.08475, 0.00260, -0.99591, 0.09032, -0.00314, -0.99618, 0.08735, 0.00194, -0.99636, 0.08528, -0.00162, -0.99601, 0.08919, -0.00145, -0.99614, 0.08759, 0.00536, -0.99610, 0.08827, -0.00040, -0.99576, 0.09194, -0.00235, -0.99680, 0.07990, 0.00205, -0.99632, 0.08545, 0.00690, -0.99666, 0.08159, 0.00217, -0.99645, 0.08418, -0.00236, -0.99667, 0.08131, 0.00682, -0.99636, 0.08530, 0.00030, -0.99644, 0.08424, -0.00330, -0.99654, 0.08302, 0.00246, -0.99662, 0.08219, -0.00173, -0.99666, 0.08161, -0.00051, -0.99640, 0.08461, 0.00542, -0.99685, 0.07931, -0.00055, -0.99662, 0.08212, -0.00188, -0.99662, 0.08206, 0.00431, -0.99640, 0.08478, -0.00239, -0.99662, 0.08217, 0.00028, -0.99670, 0.08105, 0.00432, -0.99645, 0.08405, -0.00418, -0.99672, 0.08094, 0.00107, -0.99620, 0.08696, 0.00456, -0.99647, 0.08398, -0.00210, -0.99668, 0.08139, 0.00159, -0.99664, 0.08160, 0.00678, -0.99642, 0.08381, 0.01148, -0.99666, 0.08171, 0.00120, -0.99670, 0.08115, -0.00016, -0.99653, 0.08318, 0.00430, -0.99655, 0.08302, -0.00036, -0.99711, 0.07601, 0.00087, -0.99661, 0.08230, 0.00096, -0.99668, 0.08138, -0.00068, -0.99689, 0.07883, 0.00034, -0.99646, 0.08405, 0.00112, -0.99674, 0.08054, -0.00353, -0.99683, 0.07951, 0.00025, -0.99635, 0.08530, 0.00361, -0.99639, 0.08492, -0.00044, -0.99671, 0.08106, 0.00061, -0.99637, 0.08515, -0.00128, -0.99673, 0.08083, -0.00119, -0.99667, 0.08150, 0.00184, -0.99603, 0.08903, 0.00141, -0.99683, 0.07960, 0.00170, -0.99644, 0.08428, -0.00044, -0.99621, 0.08691, -0.00287, -0.99657, 0.08271, -0.00191, -0.99649, 0.08365, -0.00233, -0.99681, 0.07977, 0.00413, -0.99669, 0.08125, 0.00370, -0.99662, 0.08215, -0.00041, -0.99663, 0.08204, -0.00064, -0.99665, 0.08173, -0.00045, -0.99668, 0.08136, 0.00229, -0.99669, 0.08126, -0.00115, -0.99653, 0.08318, 0.00106, -0.99667, 0.08153, 0.00127, -0.99654, 0.08307, 0.00070, -0.99610, 0.08816, 0.00440, -0.99669, 0.08117, 0.00375, -0.99651, 0.08348, -0.00010, -0.99636, 0.08520, -0.00215, -0.99667, 0.08150, 0.00004, -0.99599, 0.08952, 0.00052, -0.99609, 0.08819, 0.00435, -0.99658, 0.08262, -0.00091, -0.99605, 0.08883, -0.00039, -0.99620, 0.08687, 0.00550, -0.99625, 0.08657, -0.00004, -0.99577, 0.09188, -0.00196, -0.99740, 0.07205, 0.00342, -0.99603, 0.08899, -0.00129, -0.99666, 0.08157, 0.00231, -0.99674, 0.08052, 0.00513, -0.99679, 0.08004, -0.00080, -0.99615, 0.08766, 0.00017, -0.99631, 0.08579, 0.00048, -0.99648, 0.08382, 0.00121, -0.99609, 0.08836, 0.00062, -0.99643, 0.08436, 0.00101, -0.99609, 0.08833, 0.00337, -0.99654, 0.08306, -0.00172, -0.99636, 0.08524, -0.00126, -0.99655, 0.08290, 0.00375, -0.99638, 0.08494, -0.00145, -0.99620, 0.08698, 0.00322, -0.99645, 0.08403, 0.00577, -0.99639, 0.08471, -0.00535, -0.99658, 0.08258, 0.00208, -0.99619, 0.08698, 0.00613, -0.99644, 0.08421, -0.00279, -0.99663, 0.08194, 0.00236, -0.99664, 0.08145, 0.00915, -0.99598, 0.08327, 0.03289, -0.99663, 0.08077, 0.01403, -0.99624, 0.08651, -0.00512, -0.99678, 0.08020, -0.00201, -0.99665, 0.08147, 0.00680, -0.99656, 0.08268, 0.00553, -0.99675, 0.08050, -0.00172, -0.99670, 0.08119, 0.00153, -0.99676, 0.08047, 0.00162, -0.99666, 0.08162, 0.00124, -0.99693, 0.07834, -0.00066, -0.99687, 0.07902, 0.00119, -0.99666, 0.08162, 0.00359, -0.99652, 0.08333, -0.00041, -0.99651, 0.08349, 0.00210, -0.99652, 0.08331, -0.00091, -0.99676, 0.08041, -0.00185, -0.99666, 0.08156, 0.00284, -0.99607, 0.08852, 0.00145, -0.99683, 0.07957, 0.00132, -0.99663, 0.08207, 0.00026, -0.99624, 0.08659, -0.00291, -0.99658, 0.08260, -0.00297, -0.99575, 0.09212, -0.00186, -0.99692, 0.07837, 0.00203, -0.99666, 0.08165, 0.00170, -0.99620, 0.08710, -0.00012, -0.99610, 0.08816, 0.00178, -0.99663, 0.08202, -0.00084, -0.99955, 0.03005, -0.00107, -0.99885, 0.04793, 0.00118, -0.99995, 0.00993, 0.00107, -0.99632, 0.08576, -0.00121, -0.99659, 0.08255, 0.00067, -0.99636, 0.08518, 0.00170, -0.99664, 0.08186, 0.00321, -0.99672, 0.08072, 0.00569, -0.99631, 0.08581, -0.00146, -0.99675, 0.08055, 0.00002, -0.99614, 0.08765, 0.00395, -0.99616, 0.08749, 0.00309, -0.99665, 0.08173, -0.00000, -0.99597, 0.08973, -0.00059, -0.99605, 0.08867, 0.00451, -0.99593, 0.09005, 0.00290, -0.99526, 0.09725, 0.00084, -0.99414, 0.10805, 0.00428, -0.99429, 0.10664, 0.00312, -0.99412, 0.10822, 0.00395, -0.99386, 0.11052, 0.00476, -0.99406, 0.10883, 0.00150, -0.99266, 0.10796, -0.05444, -0.99583, 0.08337, -0.03702, -0.99554, 0.09235, -0.01919, -0.99897, 0.01979, 0.04094, -0.99058, 0.11399, 0.07586, -0.99273, 0.12037, -0.00126, -0.99287, 0.11916, 0.00046, -0.99298, 0.11827, -0.00105, -0.99292, 0.11876, 0.00369, -0.99320, 0.11640, 0.00192, -0.99231, 0.12381, 0.00100, -0.99138, 0.13089, 0.00535, -0.99207, 0.12563, -0.00331, -0.99246, 0.12251, 0.00377, -0.99081, 0.13501, 0.00849, -0.99116, 0.13265, 0.00059, -0.99140, 0.13070, 0.00601, -0.99082, 0.13468, 0.01197, -0.90626, 0.42270, -0.00440, -0.85061, 0.52579, 0.00188, -0.72058, 0.69336, 0.00418, -0.93940, 0.34283, 0.00049, -0.91442, 0.40476, -0.00068, -0.72915, 0.68406, -0.02002, -0.91523, 0.40262, -0.01611, -0.84803, 0.52709, -0.05501, -0.71876, 0.69505, 0.01734, -0.88364, 0.45913, 0.09156, -0.89744, 0.44112, 0.00519, -0.74812, 0.66356, -0.00038, -0.90895, 0.41691, 0.00255, -0.86150, 0.50775, 0.00322, -0.78668, 0.61735, 0.00304, -0.89500, 0.44586, 0.01374, -0.78026, 0.62544, 0.00460, -0.82449, 0.56585, -0.00476, -0.87174, 0.48990, 0.00867, -0.74988, 0.66153, 0.00761, -0.97710, -0.21276, -0.00004, -0.98636, 0.16455, 0.00502, -0.83463, 0.55075, 0.00776, -0.51146, 0.84379, 0.16256, -0.47953, 0.84199, 0.24718, -0.71853, 0.67040, -0.18513, -0.53151, 0.79844, -0.28282, -0.63322, 0.67648, 0.37603, -0.70881, 0.70421, -0.04088, -0.59698, 0.77221, -0.21751, -0.65229, 0.67607, 0.34271, -0.59933, 0.79957, -0.03858, -0.68398, 0.67208, -0.28368, -0.68945, 0.67573, 0.26085, -0.51335, 0.85801, -0.01719, -0.70846, 0.67104, -0.21860, -0.69067, 0.68382, 0.23529, -0.68928, 0.72169, -0.06363, -0.71965, 0.69421, 0.01324, -0.51516, 0.85089, 0.10293, -0.70189, 0.69016, -0.17613, -0.57268, 0.81123, 0.11809, -0.53160, 0.73337, -0.42376, -0.64292, -0.60097, -0.47486, -0.72115, 0.21565, 0.65836, -0.53905, -0.63287, 0.55579, -0.36930, 0.92593, 0.07916, -0.36912, 0.88851, -0.27258, -0.96577, 0.07756, -0.24751, -0.38273, 0.92230, 0.05371, -0.56020, 0.77409, -0.29490, -0.95326, 0.23023, 0.19566, -0.46750, 0.88390, 0.01252, -0.70752, 0.70650, -0.01622, -0.76948, 0.63821, -0.02426, -0.67468, 0.71659, -0.17690, -0.59979, 0.67457, 0.43036, -0.50285, 0.86420, -0.01736, -0.60279, 0.67673, -0.42270, -0.71975, 0.68995, 0.07695, -0.83054, 0.55665, -0.01861, -0.61940, 0.67757, 0.39653, -0.47082, 0.88215, 0.01185, -0.78247, 0.59148, -0.19465, -0.46115, 0.86599, 0.19341, -0.34880, 0.40760, -0.84392, -0.51031, -0.64413, -0.56980, -0.89456, 0.39093, -0.21664, -0.21107, -0.73830, -0.64060]
    private static let doorSkinIdx: [UInt16] = [0, 1, 23, 1, 24, 23, 1, 2, 24, 2, 25, 24, 2, 3, 25, 3, 26, 25, 3, 4, 26, 4, 27, 26, 4, 5, 27, 5, 28, 27, 5, 6, 28, 6, 29, 28, 6, 7, 29, 7, 30, 29, 7, 8, 30, 8, 31, 30, 8, 9, 31, 9, 32, 31, 9, 10, 32, 10, 33, 32, 10, 11, 33, 11, 34, 33, 11, 12, 34, 12, 35, 34, 12, 13, 35, 13, 36, 35, 13, 14, 36, 14, 37, 36, 14, 15, 37, 15, 38, 37, 15, 16, 38, 16, 39, 38, 16, 17, 39, 17, 40, 39, 17, 18, 40, 18, 41, 40, 18, 19, 41, 19, 42, 41, 19, 20, 42, 20, 43, 42, 20, 21, 43, 21, 44, 43, 21, 22, 44, 22, 45, 44, 23, 24, 46, 24, 47, 46, 24, 25, 47, 25, 48, 47, 25, 26, 48, 26, 49, 48, 26, 27, 49, 27, 50, 49, 27, 28, 50, 28, 51, 50, 28, 29, 51, 29, 52, 51, 29, 30, 52, 30, 53, 52, 30, 31, 53, 31, 54, 53, 31, 32, 54, 32, 55, 54, 32, 33, 55, 33, 56, 55, 33, 34, 56, 34, 57, 56, 34, 35, 57, 35, 58, 57, 35, 36, 58, 36, 59, 58, 36, 37, 59, 37, 60, 59, 37, 38, 60, 38, 61, 60, 38, 39, 61, 39, 62, 61, 39, 40, 62, 40, 63, 62, 40, 41, 63, 41, 64, 63, 41, 42, 64, 42, 65, 64, 42, 43, 65, 43, 66, 65, 43, 44, 66, 44, 67, 66, 44, 45, 67, 45, 68, 67, 46, 47, 69, 47, 70, 69, 47, 48, 70, 48, 71, 70, 48, 49, 71, 49, 72, 71, 49, 50, 72, 50, 73, 72, 50, 51, 73, 51, 74, 73, 51, 52, 74, 52, 75, 74, 52, 53, 75, 53, 76, 75, 53, 54, 76, 54, 77, 76, 54, 55, 77, 55, 78, 77, 55, 56, 78, 56, 79, 78, 56, 57, 79, 57, 80, 79, 57, 58, 80, 58, 81, 80, 58, 59, 81, 59, 82, 81, 59, 60, 82, 60, 83, 82, 60, 61, 83, 61, 84, 83, 61, 62, 84, 62, 85, 84, 62, 63, 85, 63, 86, 85, 63, 64, 86, 64, 87, 86, 64, 65, 87, 65, 88, 87, 65, 66, 88, 66, 89, 88, 66, 67, 89, 67, 90, 89, 67, 68, 90, 68, 91, 90, 69, 70, 92, 70, 93, 92, 70, 71, 93, 71, 94, 93, 71, 72, 94, 72, 95, 94, 72, 73, 95, 73, 96, 95, 73, 74, 96, 74, 97, 96, 74, 75, 97, 75, 98, 97, 75, 76, 98, 76, 99, 98, 76, 77, 99, 77, 100, 99, 77, 78, 100, 78, 101, 100, 78, 79, 101, 79, 102, 101, 79, 80, 102, 80, 103, 102, 80, 81, 103, 81, 104, 103, 81, 82, 104, 82, 105, 104, 82, 83, 105, 83, 106, 105, 83, 84, 106, 84, 107, 106, 84, 85, 107, 85, 108, 107, 85, 86, 108, 86, 109, 108, 86, 87, 109, 87, 110, 109, 87, 88, 110, 88, 111, 110, 88, 89, 111, 89, 112, 111, 89, 90, 112, 90, 113, 112, 90, 91, 113, 91, 114, 113, 92, 93, 115, 93, 116, 115, 93, 94, 116, 94, 117, 116, 94, 95, 117, 95, 118, 117, 95, 96, 118, 96, 119, 118, 96, 97, 119, 97, 120, 119, 97, 98, 120, 98, 121, 120, 98, 99, 121, 99, 122, 121, 99, 100, 122, 100, 123, 122, 100, 101, 123, 101, 124, 123, 101, 102, 124, 102, 125, 124, 102, 103, 125, 103, 126, 125, 103, 104, 126, 104, 127, 126, 104, 105, 127, 105, 128, 127, 105, 106, 128, 106, 129, 128, 106, 107, 129, 107, 130, 129, 107, 108, 130, 108, 131, 130, 108, 109, 131, 109, 132, 131, 109, 110, 132, 110, 133, 132, 110, 111, 133, 111, 134, 133, 111, 112, 134, 112, 135, 134, 112, 113, 135, 113, 136, 135, 113, 114, 136, 114, 137, 136, 115, 116, 138, 116, 139, 138, 116, 117, 139, 117, 140, 139, 117, 118, 140, 118, 141, 140, 118, 119, 141, 119, 142, 141, 119, 120, 142, 120, 143, 142, 120, 121, 143, 121, 144, 143, 121, 122, 144, 122, 145, 144, 122, 123, 145, 123, 146, 145, 123, 124, 146, 124, 147, 146, 124, 125, 147, 125, 148, 147, 125, 126, 148, 126, 149, 148, 126, 127, 149, 127, 150, 149, 127, 128, 150, 128, 151, 150, 128, 129, 151, 129, 152, 151, 129, 130, 152, 130, 153, 152, 130, 131, 153, 131, 154, 153, 131, 132, 154, 132, 155, 154, 132, 133, 155, 133, 156, 155, 133, 134, 156, 134, 157, 156, 134, 135, 157, 135, 158, 157, 135, 136, 158, 136, 159, 158, 136, 137, 159, 137, 160, 159, 138, 139, 161, 139, 162, 161, 139, 140, 162, 140, 163, 162, 140, 141, 163, 141, 164, 163, 141, 142, 164, 142, 165, 164, 142, 143, 165, 143, 166, 165, 143, 144, 166, 144, 167, 166, 144, 145, 167, 145, 168, 167, 145, 146, 168, 146, 169, 168, 146, 147, 169, 147, 170, 169, 147, 148, 170, 148, 171, 170, 148, 149, 171, 149, 172, 171, 149, 150, 172, 150, 173, 172, 150, 151, 173, 151, 174, 173, 151, 152, 174, 152, 175, 174, 152, 153, 175, 153, 176, 175, 153, 154, 176, 154, 177, 176, 154, 155, 177, 155, 178, 177, 155, 156, 178, 156, 179, 178, 156, 157, 179, 157, 180, 179, 157, 158, 180, 158, 181, 180, 158, 159, 181, 159, 182, 181, 159, 160, 182, 160, 183, 182, 161, 162, 184, 162, 185, 184, 162, 163, 185, 163, 186, 185, 163, 164, 186, 164, 187, 186, 164, 165, 187, 165, 188, 187, 165, 166, 188, 166, 189, 188, 166, 167, 189, 167, 190, 189, 167, 168, 190, 168, 191, 190, 168, 169, 191, 169, 192, 191, 169, 170, 192, 170, 193, 192, 170, 171, 193, 171, 194, 193, 171, 172, 194, 172, 195, 194, 172, 173, 195, 173, 196, 195, 173, 174, 196, 174, 197, 196, 174, 175, 197, 175, 198, 197, 175, 176, 198, 176, 199, 198, 176, 177, 199, 177, 200, 199, 177, 178, 200, 178, 201, 200, 178, 179, 201, 179, 202, 201, 179, 180, 202, 180, 203, 202, 180, 181, 203, 181, 204, 203, 181, 182, 204, 182, 205, 204, 182, 183, 205, 183, 206, 205, 184, 185, 207, 185, 208, 207, 185, 186, 208, 186, 209, 208, 186, 187, 209, 187, 210, 209, 187, 188, 210, 188, 211, 210, 188, 189, 211, 189, 212, 211, 189, 190, 212, 190, 213, 212, 190, 191, 213, 191, 214, 213, 191, 192, 214, 192, 215, 214, 192, 193, 215, 193, 216, 215, 193, 194, 216, 194, 217, 216, 194, 195, 217, 195, 218, 217, 195, 196, 218, 196, 219, 218, 196, 197, 219, 197, 220, 219, 197, 198, 220, 198, 221, 220, 198, 199, 221, 199, 222, 221, 199, 200, 222, 200, 223, 222, 200, 201, 223, 201, 224, 223, 201, 202, 224, 202, 225, 224, 202, 203, 225, 203, 226, 225, 203, 204, 226, 204, 227, 226, 204, 205, 227, 205, 228, 227, 205, 206, 228, 206, 229, 228, 207, 208, 230, 208, 231, 230, 208, 209, 231, 209, 232, 231, 209, 210, 232, 210, 233, 232, 210, 211, 233, 211, 234, 233, 211, 212, 234, 212, 235, 234, 212, 213, 235, 213, 236, 235, 213, 214, 236, 214, 237, 236, 214, 215, 237, 215, 238, 237, 215, 216, 238, 216, 239, 238, 216, 217, 239, 217, 240, 239, 217, 218, 240, 218, 241, 240, 218, 219, 241, 219, 242, 241, 219, 220, 242, 220, 243, 242, 220, 221, 243, 221, 244, 243, 221, 222, 244, 222, 245, 244, 222, 223, 245, 223, 246, 245, 223, 224, 246, 224, 247, 246, 224, 225, 247, 225, 248, 247, 225, 226, 248, 226, 249, 248, 226, 227, 249, 227, 250, 249, 227, 228, 250, 228, 251, 250, 228, 229, 251, 229, 252, 251, 230, 231, 253, 231, 254, 253, 231, 232, 254, 232, 255, 254, 232, 233, 255, 233, 256, 255, 233, 234, 256, 234, 257, 256, 234, 235, 257, 235, 258, 257, 235, 236, 258, 236, 259, 258, 236, 237, 259, 237, 260, 259, 237, 238, 260, 238, 261, 260, 238, 239, 261, 239, 262, 261, 239, 240, 262, 240, 263, 262, 240, 241, 263, 241, 264, 263, 241, 242, 264, 242, 265, 264, 242, 243, 265, 243, 266, 265, 243, 244, 266, 244, 267, 266, 244, 245, 267, 245, 268, 267, 245, 246, 268, 246, 269, 268, 246, 247, 269, 247, 270, 269, 247, 248, 270, 248, 271, 270, 248, 249, 271, 249, 272, 271, 249, 250, 272, 250, 273, 272, 250, 251, 273, 251, 274, 273, 251, 252, 274, 252, 275, 274, 253, 254, 276, 254, 277, 276, 254, 255, 277, 255, 278, 277, 255, 256, 278, 256, 279, 278, 256, 257, 279, 257, 280, 279, 257, 258, 280, 258, 281, 280, 258, 259, 281, 259, 282, 281, 259, 260, 282, 260, 283, 282, 260, 261, 283, 261, 284, 283, 261, 262, 284, 262, 285, 284, 262, 263, 285, 263, 286, 285, 263, 264, 286, 264, 287, 286, 264, 265, 287, 265, 288, 287, 265, 266, 288, 266, 289, 288, 266, 267, 289, 267, 290, 289, 267, 268, 290, 268, 291, 290, 268, 269, 291, 269, 292, 291, 269, 270, 292, 270, 293, 292, 270, 271, 293, 271, 294, 293, 271, 272, 294, 272, 295, 294, 272, 273, 295, 273, 296, 295, 273, 274, 296, 274, 297, 296, 274, 275, 297, 275, 298, 297]
    private static let doorSkinNZ = 23

    private static func doorSkinGeometry() -> SCNGeometry {
        let n = doorSkinPos.count / 3
        let psrc = SCNGeometrySource(data: Data(bytes: doorSkinPos, count: doorSkinPos.count * 4),
                                     semantic: .vertex, vectorCount: n,
                                     usesFloatComponents: true, componentsPerVector: 3,
                                     bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let nsrc = SCNGeometrySource(data: Data(bytes: doorSkinNrm, count: doorSkinNrm.count * 4),
                                     semantic: .normal, vectorCount: n,
                                     usesFloatComponents: true, componentsPerVector: 3,
                                     bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let el = SCNGeometryElement(indices: doorSkinIdx.map(Int.init), primitiveType: .triangles)
        return SCNGeometry(sources: [psrc, nsrc], elements: [el])
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
