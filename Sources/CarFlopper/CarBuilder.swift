import Foundation
import SceneKit
import UIKit

// MARK: - Car assembly from primitives. Node names carry part ids for damage state.

final class CarAssembly {
    let root = SCNNode()
    let def: CarDef
    // Repair points are PART-LOCAL, following flat-wheel scale and ajar-door
    // hinge rotation. Wheel center-cap face comes from baked mesh bounds;
    // door is an exact baked surface vertex, exhaust is its cylinder side.
    static let repairTargetLocal: [String: SCNVector3] = [
        "wheelFL": SCNVector3(-0.1208, 0, 0),
        "wheelFR": SCNVector3(0.1208, 0, 0),
        "wheelRL": SCNVector3(-0.14305, 0, 0),
        "wheelRR": SCNVector3(0.14305, 0, 0),
        "door": SCNVector3(-0.04610, 0, -0.550),
        "exhaust": SCNVector3(0, -0.049497, -0.049497),
        "engine": SCNVector3(0, 0.120, 0),
        "windshield": SCNVector3(-0.60, 0, 0.015),
    ]
    static let repairNormalLocal: [String: SCNVector3] = [
        "wheelFL": SCNVector3(-1,0,0), "wheelFR": SCNVector3(1,0,0),
        "wheelRL": SCNVector3(-1,0,0), "wheelRR": SCNVector3(1,0,0),
        "door": SCNVector3(-1,0,0), "exhaust": SCNVector3(0,-0.7071,-0.7071),
        "engine": SCNVector3(0,1,0),
        "windshield": SCNVector3(0,0,1),
    ]
    func repairPointWorld(_ id: String) -> SCNVector3? {
        guard let node = partNodes[id], let p = CarAssembly.repairTargetLocal[id] else { return nil }
        return node.convertPosition(p, to: nil)
    }
    func repairNormalWorld(_ id: String) -> SCNVector3? {
        guard let node = partNodes[id], let n = CarAssembly.repairNormalLocal[id] else { return nil }
        return node.convertVector(n, to: nil)
    }
    private func updateRepairMarker(_ id: String) {
        guard let node = partNodes[id], let marker = markers[id],
              let p = CarAssembly.repairTargetLocal[id] else { return }
        let n = CarAssembly.repairNormalLocal[id] ?? SCNVector3(0,1,0)
        let local = SCNVector3(p.x + n.x * 0.018, p.y + n.y * 0.018, p.z + n.z * 0.018)
        let world = node.convertPosition(local, to: nil)
        marker.position = marker.parent?.convertPosition(world, from: nil) ?? world
    }
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
            // A physical center fastener projects from the baked cap face.
            let fastener = SCNCylinder(radius:0.008,height:0.028)
            fastener.radialSegmentCount = 6
            let bolt = SCNNode(geometry:fastener)
            fastener.firstMaterial = rim
            bolt.eulerAngles.z = .pi / 2
            bolt.position = CarAssembly.repairTargetLocal[id] ?? SCNVector3Zero
            wheel.addChildNode(bolt)
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
        // markers HUG the part: the ring center is the repair target the hand
        // aims at, so ring, physical surface and tool tip share one anchor.
        // Billboarding (below) keeps the ring a full circle against the body.
        let haloLift: [String: Float] = ["exhaust": 0.10, "engine": 0.12, "windshield": 0.10]
        // the door node sits at its front-edge hinge for the ajar pivot; pull
        // its marker ring back to mid-door so it marks the panel, not the fender
        let markerZNudge: [String: Float] = ["door": -0.55]
        for p in def.parts {
            guard let anchor = partNodes[p.id] else { continue }
            let holder = SCNNode()
            if let t = CarAssembly.repairTargetLocal[p.id] {
                holder.position = root.convertPosition(anchor.convertPosition(t, to: nil), from: nil)
            } else {
                // generic placement (parts without a grounded target): lift
                // above the part, then push the ring clear of the body so
                // panels stop biting its edge, while depth testing stays on
                // so markers never show through the car. Flank parts push
                // straight OUT sideways; centerline parts push radially.
                let push: Float = 0.14
                let flank = abs(anchor.position.x) > 0.5
                let alen = max(0.001, hypotf(anchor.position.x, anchor.position.z))
                let px = flank ? anchor.position.x + (anchor.position.x >= 0 ? push : -push)
                               : anchor.position.x + anchor.position.x / alen * push
                let pz = flank ? anchor.position.z + (markerZNudge[p.id] ?? 0)
                               : anchor.position.z + anchor.position.z / alen * push
                holder.position = SCNVector3(px,
                                             anchor.position.y + (haloLift[p.id] ?? 0.10),
                                             pz)
            }
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
            updateRepairMarker(p.id)
        }
    }

    // Visual state per part: broken (dark + marker) -> fixed (clean, marker removed)
    func setPart(_ id: String, progress: Float) {
        guard let node = partNodes[id] else { NSLog("[CFPART] setPart %@ progress=%.2f SKIP no node", id, progress); return }
        NSLog("[CFPART] setPart %@ progress=%.2f attached=%d hidden=%d euler=(%.3f,%.3f,%.3f) diffuse=%@", id, progress, node.parent != nil, node.isHidden, node.eulerAngles.x, node.eulerAngles.y, node.eulerAngles.z, String(describing: node.geometry?.firstMaterial?.diffuse.contents))
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
            NSLog("[CFDOOR] after setPart fixed=%d eulerY=%.3f diffuse=%@", fixed, node.eulerAngles.y, String(describing: node.geometry?.firstMaterial?.diffuse.contents))
        }
        updateRepairMarker(id)
        _ = brokenTint
    }

    // baked curved door skin: sampled from the body shell (door region),
    // 1.5mm proud, vertices relative to the front-edge hinge point
    private static let doorSkinPos: [Float] = [-0.07018, -0.31000, -1.10000, -0.06974, -0.31000, -1.05000, -0.06952, -0.31000, -1.00000, -0.07115, -0.31000, -0.95000, -0.07019, -0.31000, -0.90000, -0.06951, -0.31000, -0.85000, -0.06963, -0.31000, -0.80000, -0.06966, -0.31000, -0.75000, -0.07105, -0.31000, -0.70000, -0.07000, -0.31000, -0.65000, -0.06969, -0.31000, -0.60000, -0.06975, -0.31000, -0.55000, -0.06955, -0.31000, -0.50000, -0.07088, -0.31000, -0.45000, -0.07044, -0.31000, -0.40000, -0.06951, -0.31000, -0.35000, -0.06973, -0.31000, -0.30000, -0.06972, -0.31000, -0.25000, -0.07051, -0.31000, -0.20000, -0.07021, -0.31000, -0.15000, -0.06970, -0.31000, -0.10000, -0.06958, -0.31000, -0.05000, -0.06979, -0.31000, 0.00000, -0.06817, -0.25833, -1.10000, -0.06821, -0.25833, -1.05000, -0.06774, -0.25833, -1.00000, -0.06815, -0.25833, -0.95000, -0.06815, -0.25833, -0.90000, -0.06777, -0.25833, -0.85000, -0.06815, -0.25833, -0.80000, -0.06814, -0.25833, -0.75000, -0.06810, -0.25833, -0.70000, -0.06815, -0.25833, -0.65000, -0.06791, -0.25833, -0.60000, -0.06802, -0.25833, -0.55000, -0.06817, -0.25833, -0.50000, -0.06810, -0.25833, -0.45000, -0.06810, -0.25833, -0.40000, -0.06815, -0.25833, -0.35000, -0.06826, -0.25833, -0.30000, -0.06799, -0.25833, -0.25000, -0.06816, -0.25833, -0.20000, -0.06808, -0.25833, -0.15000, -0.06794, -0.25833, -0.10000, -0.06819, -0.25833, -0.05000, -0.06823, -0.25833, 0.00000, -0.06383, -0.20667, -1.10000, -0.06383, -0.20667, -1.05000, -0.06389, -0.20667, -1.00000, -0.06372, -0.20667, -0.95000, -0.06343, -0.20667, -0.90000, -0.06387, -0.20667, -0.85000, -0.06364, -0.20667, -0.80000, -0.06354, -0.20667, -0.75000, -0.06350, -0.20667, -0.70000, -0.06336, -0.20667, -0.65000, -0.06364, -0.20667, -0.60000, -0.06347, -0.20667, -0.55000, -0.06335, -0.20667, -0.50000, -0.06339, -0.20667, -0.45000, -0.06367, -0.20667, -0.40000, -0.06334, -0.20667, -0.35000, -0.06341, -0.20667, -0.30000, -0.06366, -0.20667, -0.25000, -0.06322, -0.20667, -0.20000, -0.06382, -0.20667, -0.15000, -0.06336, -0.20667, -0.10000, -0.06329, -0.20667, -0.05000, -0.06340, -0.20667, 0.00000, -0.05998, -0.15500, -1.10000, -0.05988, -0.15500, -1.05000, -0.05929, -0.15500, -1.00000, -0.05966, -0.15500, -0.95000, -0.05952, -0.15500, -0.90000, -0.05897, -0.15500, -0.85000, -0.05949, -0.15500, -0.80000, -0.05931, -0.15500, -0.75000, -0.05925, -0.15500, -0.70000, -0.05948, -0.15500, -0.65000, -0.05930, -0.15500, -0.60000, -0.05893, -0.15500, -0.55000, -0.05935, -0.15500, -0.50000, -0.05912, -0.15500, -0.45000, -0.05892, -0.15500, -0.40000, -0.05936, -0.15500, -0.35000, -0.05889, -0.15500, -0.30000, -0.05893, -0.15500, -0.25000, -0.05931, -0.15500, -0.20000, -0.05882, -0.15500, -0.15000, -0.05885, -0.15500, -0.10000, -0.05903, -0.15500, -0.05000, -0.05869, -0.15500, 0.00000, -0.05555, -0.10333, -1.10000, -0.05497, -0.10333, -1.05000, -0.05543, -0.10333, -1.00000, -0.05499, -0.10333, -0.95000, -0.05500, -0.10333, -0.90000, -0.05502, -0.10333, -0.85000, -0.05491, -0.10333, -0.80000, -0.05493, -0.10333, -0.75000, -0.05498, -0.10333, -0.70000, -0.05489, -0.10333, -0.65000, -0.05486, -0.10333, -0.60000, -0.05525, -0.10333, -0.55000, -0.05484, -0.10333, -0.50000, -0.05489, -0.10333, -0.45000, -0.05488, -0.10333, -0.40000, -0.05482, -0.10333, -0.35000, -0.05501, -0.10333, -0.30000, -0.05494, -0.10333, -0.25000, -0.05483, -0.10333, -0.20000, -0.05480, -0.10333, -0.15000, -0.05466, -0.10333, -0.10000, -0.05485, -0.10333, -0.05000, -0.05494, -0.10333, 0.00000, -0.05129, -0.05167, -1.10000, -0.05140, -0.05167, -1.05000, -0.05087, -0.05167, -1.00000, -0.05103, -0.05167, -0.95000, -0.05091, -0.05167, -0.90000, -0.05110, -0.05167, -0.85000, -0.05096, -0.05167, -0.80000, -0.05087, -0.05167, -0.75000, -0.05107, -0.05167, -0.70000, -0.05076, -0.05167, -0.65000, -0.05095, -0.05167, -0.60000, -0.05069, -0.05167, -0.55000, -0.05051, -0.05167, -0.50000, -0.05032, -0.05167, -0.45000, -0.05052, -0.05167, -0.40000, -0.05053, -0.05167, -0.35000, -0.05051, -0.05167, -0.30000, -0.05048, -0.05167, -0.25000, -0.05008, -0.05167, -0.20000, -0.05057, -0.05167, -0.15000, -0.05011, -0.05167, -0.10000, -0.05002, -0.05167, -0.05000, -0.05012, -0.05167, 0.00000, -0.04687, 0.00000, -1.10000, -0.04670, 0.00000, -1.05000, -0.04700, 0.00000, -1.00000, -0.04647, 0.00000, -0.95000, -0.04649, 0.00000, -0.90000, -0.04655, 0.00000, -0.85000, -0.04647, 0.00000, -0.80000, -0.04650, 0.00000, -0.75000, -0.04635, 0.00000, -0.70000, -0.04644, 0.00000, -0.65000, -0.04625, 0.00000, -0.60000, -0.04610, 0.00000, -0.55000, -0.04642, 0.00000, -0.50000, -0.04623, 0.00000, -0.45000, -0.04605, 0.00000, -0.40000, -0.04637, 0.00000, -0.35000, -0.04572, 0.00000, -0.30000, -0.04580, 0.00000, -0.25000, -0.04626, 0.00000, -0.20000, -0.04559, 0.00000, -0.15000, -0.04564, 0.00000, -0.10000, -0.04587, 0.00000, -0.05000, -0.04541, 0.00000, 0.00000, -0.04382, 0.05167, -1.10000, -0.04217, 0.05167, -1.05000, -0.04242, 0.05167, -1.00000, -0.04269, 0.05167, -0.95000, -0.04262, 0.05167, -0.90000, -0.04200, 0.05167, -0.85000, -0.04206, 0.05167, -0.80000, -0.04218, 0.05167, -0.75000, -0.04191, 0.05167, -0.70000, -0.04201, 0.05167, -0.65000, -0.04178, 0.05167, -0.60000, -0.04208, 0.05167, -0.55000, -0.04166, 0.05167, -0.50000, -0.04172, 0.05167, -0.45000, -0.04171, 0.05167, -0.40000, -0.04151, 0.05167, -0.35000, -0.04180, 0.05167, -0.30000, -0.04169, 0.05167, -0.25000, -0.04151, 0.05167, -0.20000, -0.04155, 0.05167, -0.15000, -0.04138, 0.05167, -0.10000, -0.04152, 0.05167, -0.05000, -0.04167, 0.05167, 0.00000, -0.03823, 0.10333, -1.10000, -0.03833, 0.10333, -1.05000, -0.03803, 0.10333, -1.00000, -0.03816, 0.10333, -0.95000, -0.03804, 0.10333, -0.90000, -0.03798, 0.10333, -0.85000, -0.03813, 0.10333, -0.80000, -0.03809, 0.10333, -0.75000, -0.03801, 0.10333, -0.70000, -0.03798, 0.10333, -0.65000, -0.03813, 0.10333, -0.60000, -0.03791, 0.10333, -0.55000, -0.03796, 0.10333, -0.50000, -0.03759, 0.10333, -0.45000, -0.03739, 0.10333, -0.40000, -0.03774, 0.10333, -0.35000, -0.03739, 0.10333, -0.30000, -0.03734, 0.10333, -0.25000, -0.03708, 0.10333, -0.20000, -0.03734, 0.10333, -0.15000, -0.03714, 0.10333, -0.10000, -0.03689, 0.10333, -0.05000, -0.03684, 0.10333, 0.00000, -0.03426, 0.15500, -1.10000, -0.03405, 0.15500, -1.05000, -0.03395, 0.15500, -1.00000, -0.03365, 0.15500, -0.95000, -0.03347, 0.15500, -0.90000, -0.03350, 0.15500, -0.85000, -0.03896, 0.15500, -0.80000, -0.03722, 0.15500, -0.75000, -0.04088, 0.15500, -0.70000, -0.03312, 0.15500, -0.65000, -0.03322, 0.15500, -0.60000, -0.03325, 0.15500, -0.55000, -0.03318, 0.15500, -0.50000, -0.03335, 0.15500, -0.45000, -0.03281, 0.15500, -0.40000, -0.03316, 0.15500, -0.35000, -0.03271, 0.15500, -0.30000, -0.03262, 0.15500, -0.25000, -0.03304, 0.15500, -0.20000, -0.03224, 0.15500, -0.15000, -0.03218, 0.15500, -0.10000, -0.03218, 0.15500, -0.05000, -0.03158, 0.15500, 0.00000, -0.02700, 0.20667, -1.10000, -0.02725, 0.20667, -1.05000, -0.02678, 0.20667, -1.00000, -0.02667, 0.20667, -0.95000, -0.02673, 0.20667, -0.90000, -0.02674, 0.20667, -0.85000, -0.02948, 0.20667, -0.80000, -0.02850, 0.20667, -0.75000, -0.03596, 0.20667, -0.70000, -0.02609, 0.20667, -0.65000, -0.02560, 0.20667, -0.60000, -0.02551, 0.20667, -0.55000, -0.02565, 0.20667, -0.50000, -0.02523, 0.20667, -0.45000, -0.02528, 0.20667, -0.40000, -0.02484, 0.20667, -0.35000, -0.02374, 0.20667, -0.30000, -0.02425, 0.20667, -0.25000, -0.02432, 0.20667, -0.20000, -0.02326, 0.20667, -0.15000, -0.02331, 0.20667, -0.10000, -0.02326, 0.20667, -0.05000, -0.02280, 0.20667, 0.00000, -0.02222, 0.25833, -1.10000, -0.02319, 0.25833, -1.05000, -0.02255, 0.25833, -1.00000, -0.02215, 0.25833, -0.95000, -0.02216, 0.25833, -0.90000, -0.02249, 0.25833, -0.85000, -0.02793, 0.25833, -0.80000, -0.02602, 0.25833, -0.75000, -0.03545, 0.25833, -0.70000, -0.02165, 0.25833, -0.65000, -0.02132, 0.25833, -0.60000, -0.02110, 0.25833, -0.55000, -0.02141, 0.25833, -0.50000, -0.02105, 0.25833, -0.45000, -0.02083, 0.25833, -0.40000, -0.02067, 0.25833, -0.35000, -0.01920, 0.25833, -0.30000, -0.01972, 0.25833, -0.25000, -0.02009, 0.25833, -0.20000, -0.01861, 0.25833, -0.15000, -0.01871, 0.25833, -0.10000, -0.01859, 0.25833, -0.05000, -0.01776, 0.25833, 0.00000, -0.01678, 0.31000, -1.10000, -0.01829, 0.31000, -1.05000, -0.01745, 0.31000, -1.00000, -0.01689, 0.31000, -0.95000, -0.01693, 0.31000, -0.90000, -0.01746, 0.31000, -0.85000, -0.02424, 0.31000, -0.80000, -0.02183, 0.31000, -0.75000, -0.03395, 0.31000, -0.70000, -0.01638, 0.31000, -0.65000, -0.01598, 0.31000, -0.60000, -0.01566, 0.31000, -0.55000, -0.01613, 0.31000, -0.50000, -0.01567, 0.31000, -0.45000, -0.01544, 0.31000, -0.40000, -0.01521, 0.31000, -0.35000, -0.01331, 0.31000, -0.30000, -0.01401, 0.31000, -0.25000, -0.01452, 0.31000, -0.20000, -0.01261, 0.31000, -0.15000, -0.01279, 0.31000, -0.10000, -0.01264, 0.31000, -0.05000, -0.01157, 0.31000, 0.00000]
    private static let doorSkinNrm: [Float] = [-0.99921, 0.03887, 0.00879, -0.99946, 0.03269, 0.00413, -0.99944, 0.03282, -0.00626, -0.99872, 0.05013, -0.00719, -0.99890, 0.04562, 0.01092, -0.99935, 0.03559, 0.00626, -0.99953, 0.03031, -0.00353, -0.99953, 0.02915, -0.00940, -0.99885, 0.04781, -0.00200, -0.99904, 0.04286, 0.00872, -0.99939, 0.03488, 0.00326, -0.99943, 0.03378, 0.00020, -0.99954, 0.02895, -0.00853, -0.99898, 0.04473, -0.00546, -0.99880, 0.04807, 0.00912, -0.99946, 0.03263, 0.00440, -0.99961, 0.02773, -0.00213, -0.99949, 0.03179, -0.00340, -0.99913, 0.04145, -0.00440, -0.99907, 0.04260, 0.00593, -0.99932, 0.03642, 0.00513, -0.99957, 0.02928, -0.00227, -0.99959, 0.02853, -0.00250, -0.99871, 0.05077, 0.00240, -0.99832, 0.05778, 0.00359, -0.99818, 0.06002, -0.00522, -0.99777, 0.06679, 0.00103, -0.99797, 0.06339, 0.00576, -0.99841, 0.05630, -0.00186, -0.99843, 0.05604, -0.00180, -0.99798, 0.06342, -0.00396, -0.99759, 0.06935, 0.00356, -0.99799, 0.06329, 0.00276, -0.99820, 0.05996, -0.00027, -0.99828, 0.05864, -0.00050, -0.99797, 0.06352, -0.00456, -0.99746, 0.07124, 0.00180, -0.99800, 0.06313, 0.00183, -0.99827, 0.05874, -0.00070, -0.99809, 0.06175, 0.00087, -0.99806, 0.06220, -0.00279, -0.99770, 0.06772, 0.00186, -0.99803, 0.06272, 0.00116, -0.99826, 0.05903, 0.00120, -0.99818, 0.06028, -0.00240, -0.99736, 0.07265, -0.00126, -0.99673, 0.08084, -0.00027, -0.99693, 0.07834, 0.00150, -0.99669, 0.08128, 0.00133, -0.99642, 0.08454, 0.00183, -0.99671, 0.08109, 0.00073, -0.99650, 0.08364, -0.00083, -0.99628, 0.08620, 0.00050, -0.99639, 0.08489, 0.00166, -0.99630, 0.08588, 0.00123, -0.99654, 0.08313, -0.00090, -0.99659, 0.08246, -0.00050, -0.99613, 0.08786, 0.00266, -0.99626, 0.08642, -0.00063, -0.99639, 0.08482, -0.00136, -0.99610, 0.08817, 0.00083, -0.99618, 0.08735, -0.00010, -0.99621, 0.08693, 0.00033, -0.99607, 0.08862, 0.00056, -0.99631, 0.08578, -0.00206, -0.99622, 0.08680, 0.00116, -0.99592, 0.09021, 0.00259, -0.99604, 0.08888, -0.00100, -0.99606, 0.08868, 0.00080, -0.99690, 0.07865, 0.00133, -0.99628, 0.08596, 0.00631, -0.99653, 0.08322, 0.00050, -0.99670, 0.08111, 0.00090, -0.99638, 0.08494, 0.00309, -0.99640, 0.08475, 0.00090, -0.99660, 0.08242, -0.00156, -0.99649, 0.08373, 0.00166, -0.99669, 0.08134, -0.00083, -0.99662, 0.08214, -0.00096, -0.99631, 0.08577, 0.00432, -0.99679, 0.08000, -0.00123, -0.99677, 0.08028, -0.00003, -0.99643, 0.08440, 0.00176, -0.99656, 0.08290, -0.00047, -0.99661, 0.08230, 0.00017, -0.99648, 0.08380, 0.00140, -0.99670, 0.08111, -0.00110, -0.99656, 0.08284, -0.00090, -0.99621, 0.08686, 0.00468, -0.99659, 0.08255, -0.00070, -0.99656, 0.08287, 0.00007, -0.99668, 0.08127, 0.00392, -0.99614, 0.08740, 0.00837, -0.99674, 0.08064, 0.00239, -0.99674, 0.08064, 0.00040, -0.99641, 0.08467, 0.00279, -0.99673, 0.08080, 0.00203, -0.99691, 0.07850, -0.00176, -0.99667, 0.08154, 0.00166, -0.99674, 0.08071, 0.00003, -0.99676, 0.08042, -0.00116, -0.99655, 0.08291, 0.00242, -0.99689, 0.07882, -0.00179, -0.99679, 0.08007, -0.00040, -0.99637, 0.08508, 0.00375, -0.99651, 0.08348, 0.00103, -0.99652, 0.08329, -0.00166, -0.99653, 0.08326, 0.00066, -0.99675, 0.08051, -0.00086, -0.99653, 0.08320, 0.00003, -0.99624, 0.08658, 0.00389, -0.99665, 0.08179, -0.00060, -0.99653, 0.08323, 0.00060, -0.99641, 0.08460, -0.00043, -0.99628, 0.08614, -0.00186, -0.99689, 0.07879, 0.00239, -0.99663, 0.08205, 0.00183, -0.99662, 0.08205, 0.00292, -0.99676, 0.08039, 0.00146, -0.99663, 0.08198, -0.00060, -0.99668, 0.08138, -0.00017, -0.99663, 0.08195, 0.00173, -0.99670, 0.08122, -0.00100, -0.99656, 0.08281, 0.00153, -0.99663, 0.08208, 0.00060, -0.99647, 0.08390, -0.00020, -0.99612, 0.08782, 0.00478, -0.99650, 0.08358, 0.00123, -0.99656, 0.08285, 0.00060, -0.99649, 0.08371, -0.00060, -0.99653, 0.08317, -0.00163, -0.99617, 0.08741, 0.00272, -0.99599, 0.08939, 0.00295, -0.99649, 0.08374, -0.00203, -0.99628, 0.08610, 0.00249, -0.99598, 0.08948, 0.00286, -0.99616, 0.08757, -0.00113, -0.99613, 0.08792, 0.00173, -0.99693, 0.07827, 0.00153, -0.99665, 0.08159, 0.00638, -0.99650, 0.08354, 0.00017, -0.99658, 0.08255, 0.00289, -0.99679, 0.08009, -0.00093, -0.99635, 0.08536, 0.00266, -0.99631, 0.08587, 0.00043, -0.99636, 0.08520, -0.00027, -0.99624, 0.08663, 0.00232, -0.99633, 0.08561, -0.00030, -0.99612, 0.08791, 0.00388, -0.99656, 0.08287, -0.00153, -0.99655, 0.08297, 0.00116, -0.99638, 0.08494, 0.00159, -0.99642, 0.08450, -0.00093, -0.99618, 0.08730, 0.00292, -0.99624, 0.08663, 0.00292, -0.99668, 0.08140, -0.00189, -0.99644, 0.08431, 0.00037, -0.99614, 0.08759, 0.00551, -0.99659, 0.08245, -0.00100, -0.99651, 0.08348, 0.00073, -0.99659, 0.08229, 0.00512, -0.99615, 0.08464, 0.02304, -0.99622, 0.08648, 0.00797, -0.99662, 0.08218, -0.00070, -0.99679, 0.08000, -0.00183, -0.99650, 0.08352, 0.00478, -0.99646, 0.08399, 0.00419, -0.99676, 0.08045, -0.00179, -0.99671, 0.08099, 0.00163, -0.99671, 0.08103, 0.00110, -0.99669, 0.08131, 0.00159, -0.99694, 0.07812, -0.00047, -0.99682, 0.07972, 0.00047, -0.99660, 0.08230, 0.00286, -0.99668, 0.08141, 0.00149, -0.99642, 0.08457, 0.00100, -0.99663, 0.08198, 0.00040, -0.99688, 0.07892, -0.00030, -0.99648, 0.08384, 0.00056, -0.99629, 0.08597, 0.00402, -0.99671, 0.08099, -0.00017, -0.99662, 0.08218, 0.00010, -0.99652, 0.08339, 0.00043, -0.99639, 0.08486, -0.00166, -0.99624, 0.08613, 0.00963, -0.99687, 0.07911, 0.00120, -0.99657, 0.08278, 0.00056, -0.99630, 0.08594, 0.00116, -0.99627, 0.08623, 0.00385, -0.99663, 0.08198, -0.00090, -0.99868, 0.04758, -0.01931, -0.99910, 0.04187, 0.00749, -0.99968, 0.02245, -0.01180, -0.99788, 0.05975, 0.02578, -0.99646, 0.08406, -0.00086, -0.99643, 0.08444, 0.00242, -0.99657, 0.08278, 0.00216, -0.99654, 0.08307, 0.00326, -0.99655, 0.08297, 0.00146, -0.99658, 0.08259, -0.00213, -0.99619, 0.08712, 0.00452, -0.99615, 0.08757, 0.00296, -0.99653, 0.08317, -0.00153, -0.99625, 0.08645, 0.00282, -0.99590, 0.09037, 0.00272, -0.99581, 0.09146, 0.00149, -0.99546, 0.09505, 0.00465, -0.99503, 0.09956, 0.00212, -0.99421, 0.10743, 0.00222, -0.99410, 0.10841, 0.00378, -0.99378, 0.11130, 0.00394, -0.99401, 0.10927, 0.00099, -0.99515, 0.09113, -0.03695, -0.99622, 0.08011, -0.03367, -0.99652, 0.08290, -0.00923, -0.99837, 0.05694, 0.00256, -0.99077, 0.10741, 0.08270, -0.99305, 0.11772, 0.00149, -0.99288, 0.11914, 0.00040, -0.99310, 0.11724, 0.00010, -0.99301, 0.11797, 0.00450, -0.99298, 0.11825, -0.00007, -0.99256, 0.12169, 0.00328, -0.99161, 0.12903, 0.00737, -0.99210, 0.12541, -0.00301, -0.99218, 0.12478, 0.00142, -0.99097, 0.13374, 0.00984, -0.99122, 0.13221, 0.00106, -0.99120, 0.13233, 0.00430, -0.98915, 0.14651, 0.01095, -0.99269, 0.12066, -0.00192, -0.99415, 0.10798, -0.00142, -0.99407, 0.10855, 0.00697, -0.99405, 0.10894, 0.00224, -0.99407, 0.10874, -0.00058, -0.99260, 0.11551, -0.03737, -0.99339, 0.11225, -0.02390, -0.99451, 0.09262, -0.04877, -0.99779, 0.06560, 0.01050, -0.98859, 0.09913, 0.11342, -0.99332, 0.11530, 0.00482, -0.99328, 0.11573, 0.00065, -0.99330, 0.11559, 0.00025, -0.99317, 0.11655, 0.00545, -0.99315, 0.11682, 0.00214, -0.99234, 0.12295, 0.01222, -0.99191, 0.12663, 0.00906, -0.99213, 0.12506, -0.00694, -0.99198, 0.12616, 0.00797, -0.99156, 0.12914, 0.01177, -0.99157, 0.12959, -0.00035, -0.99153, 0.12973, 0.00575, -0.99289, 0.11848, 0.01162, -0.99568, 0.09175, -0.01454, -0.99604, 0.08870, -0.00561, -0.99587, 0.09025, 0.01006, -0.99558, 0.09387, 0.00422, -0.99562, 0.09348, -0.00242, -0.99547, 0.08133, -0.04918, -0.99741, 0.05788, -0.04274, -0.99618, 0.05639, -0.06667, -0.99893, 0.04080, 0.02164, -0.98512, 0.08006, 0.15205, -0.99566, 0.09291, 0.00530, -0.99557, 0.09406, -0.00001, -0.99575, 0.09207, 0.00016, -0.99569, 0.09264, 0.00519, -0.99558, 0.09384, 0.00475, -0.99548, 0.09377, 0.01529, -0.99502, 0.09904, 0.01090, -0.99513, 0.09823, -0.00847, -0.99532, 0.09617, 0.00918, -0.99477, 0.10097, 0.01531, -0.99481, 0.10173, -0.00035, -0.99461, 0.10331, 0.00836, -0.99375, 0.11015, 0.01817, -0.99472, 0.09960, -0.02466, -0.99541, 0.09574, -0.00015, -0.99499, 0.09922, 0.01186, -0.99488, 0.10102, 0.00338, -0.99504, 0.09934, -0.00601, -0.99254, 0.08800, -0.08435, -0.99709, 0.07445, -0.01632, -0.98999, 0.06310, -0.12628, -0.99049, 0.05277, 0.12708, -0.98756, 0.10111, 0.12046, -0.99461, 0.10348, 0.00630, -0.99461, 0.10366, -0.00311, -0.99476, 0.10225, 0.00231, -0.99461, 0.10350, 0.00597, -0.99455, 0.10416, 0.00420, -0.99389, 0.10775, 0.02388, -0.99369, 0.11204, 0.00447, -0.99401, 0.10882, -0.01050, -0.99377, 0.10976, 0.01910, -0.99333, 0.11478, 0.01077, -0.99348, 0.11398, 0.00058, -0.99317, 0.11588, 0.01364, -0.99268, 0.11887, 0.02130]
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
