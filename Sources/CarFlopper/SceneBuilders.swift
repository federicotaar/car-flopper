import Foundation
import SceneKit
import UIKit

// MARK: - Materials

enum Mat {
    static func flat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, rough: CGFloat = 0.9, metal: CGFloat = 0.0) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }
    static let concrete = Mat.flat(0.42, 0.42, 0.45)
    static let concreteDark = Mat.flat(0.30, 0.30, 0.33)
    static let wall = Mat.flat(0.55, 0.53, 0.50)
    static let wallDark = Mat.flat(0.38, 0.36, 0.34)
    static let steel = Mat.flat(0.55, 0.56, 0.60, rough: 0.4, metal: 0.8)
    static let steelDark = Mat.flat(0.22, 0.23, 0.26, rough: 0.5, metal: 0.7)
    static let rubber = Mat.flat(0.08, 0.08, 0.09)
    static let glass = SCNMaterial()
    static let wood = Mat.flat(0.45, 0.32, 0.18)
    static let rust = Mat.flat(0.40, 0.22, 0.12)

    static func setup() {
        glass.diffuse.contents = UIColor(white: 0.75, alpha: 0.55)
        glass.isDoubleSided = true
        glass.roughness.contents = 0.1
        glass.metalness.contents = 0.3
    }
}

// MARK: - Garage environment

enum GarageBuilder {
    // Garage interior: 16 x 7 walls around a 16 x 12 floor, origin center.
    static func buildEnvironment(into root: SCNNode) {
        Mat.setup()

        let floor = SCNNode(geometry: SCNBox(width: 16, height: 0.1, length: 12, chamferRadius: 0))
        floor.position = SCNVector3(0, -0.05, 0)
        (floor.geometry as? SCNBox)?.materials = [Mat.concrete]
        root.addChildNode(floor)

        // painted parking box lines around car bay
        for (x, z, w, l) in [(Float(-2.2), Float(0), Float(0.08), Float(5.4)),
                             (Float(2.2), Float(0), Float(0.08), Float(5.4)),
                             (Float(0), Float(2.7), Float(4.4), Float(0.08)),
                             (Float(0), Float(-2.7), Float(4.4), Float(0.08))] {
            let line = SCNNode(geometry: SCNBox(width: CGFloat(w), height: 0.01, length: CGFloat(l), chamferRadius: 0))
            line.position = SCNVector3(x, 0.005, z)
            (line.geometry as? SCNBox)?.materials = [Mat.flat(0.85, 0.75, 0.20)]
            root.addChildNode(line)
        }

        // oil stains
        for (x, z, s) in [(Float(3.4), Float(1.8), Float(0.9)), (Float(-3.1), Float(-2.2), Float(1.3)), (Float(1.2), Float(-3.4), Float(0.7))] {
            let stain = SCNNode(geometry: SCNCylinder(radius: CGFloat(s * 0.5), height: 0.005))
            stain.position = SCNVector3(x, 0.003, z)
            (stain.geometry as? SCNCylinder)?.materials = [Mat.flat(0.16, 0.16, 0.18)]
            root.addChildNode(stain)
        }

        // walls
        let wallN = SCNNode(geometry: SCNBox(width: 16, height: 4.5, length: 0.2, chamferRadius: 0))
        wallN.position = SCNVector3(0, 2.25, -6)
        (wallN.geometry as? SCNBox)?.materials = [Mat.wall]
        root.addChildNode(wallN)

        let wallS = SCNNode(geometry: SCNBox(width: 16, height: 4.5, length: 0.2, chamferRadius: 0))
        wallS.position = SCNVector3(0, 2.25, 6)
        (wallS.geometry as? SCNBox)?.materials = [Mat.wallDark]
        root.addChildNode(wallS)

        let wallW = SCNNode(geometry: SCNBox(width: 0.2, height: 4.5, length: 12, chamferRadius: 0))
        wallW.position = SCNVector3(-8, 2.25, 0)
        (wallW.geometry as? SCNBox)?.materials = [Mat.wall]
        root.addChildNode(wallW)

        let wallE = SCNNode(geometry: SCNBox(width: 0.2, height: 4.5, length: 12, chamferRadius: 0))
        wallE.position = SCNVector3(8, 2.25, 0)
        (wallE.geometry as? SCNBox)?.materials = [Mat.wallDark]
        root.addChildNode(wallE)

        // roll-up door on south wall (visual)
        let door = SCNNode(geometry: SCNBox(width: 5.5, height: 3.2, length: 0.1, chamferRadius: 0))
        door.position = SCNVector3(0, 1.6, 5.92)
        (door.geometry as? SCNBox)?.materials = [Mat.steelDark]
        root.addChildNode(door)
        for i in 0..<6 {
            let rib = SCNNode(geometry: SCNBox(width: 5.5, height: 0.06, length: 0.04, chamferRadius: 0))
            rib.position = SCNVector3(0, 0.4 + Float(i) * 0.5, 5.86)
            (rib.geometry as? SCNBox)?.materials = [Mat.steel]
            root.addChildNode(rib)
        }

        // workbench against north wall
        let bench = SCNNode(geometry: SCNBox(width: 3.2, height: 0.12, length: 0.9, chamferRadius: 0.01))
        bench.position = SCNVector3(-3.5, 0.95, -5.3)
        (bench.geometry as? SCNBox)?.materials = [Mat.wood]
        root.addChildNode(bench)
        for dx in [-1.4, 1.4] as [Float] {
            let leg = SCNNode(geometry: SCNBox(width: 0.1, height: 0.95, length: 0.8, chamferRadius: 0))
            leg.position = SCNVector3(-3.5 + dx, 0.475, -5.3)
            (leg.geometry as? SCNBox)?.materials = [Mat.steelDark]
            root.addChildNode(leg)
        }
        // pegboard + tools silhouettes
        let peg = SCNNode(geometry: SCNBox(width: 3.2, height: 1.4, length: 0.06, chamferRadius: 0))
        peg.position = SCNVector3(-3.5, 2.2, -5.85)
        (peg.geometry as? SCNBox)?.materials = [Mat.flat(0.50, 0.38, 0.24)]
        root.addChildNode(peg)
        for i in 0..<5 {
            let tool = SCNNode(geometry: SCNBox(width: 0.12, height: CGFloat(0.5 + Float(i % 3) * 0.12), length: 0.04, chamferRadius: 0.02))
            tool.position = SCNVector3(-4.7 + Float(i) * 0.6, 2.2, -5.80)
            (tool.geometry as? SCNBox)?.materials = [i % 2 == 0 ? Mat.steel : Mat.flat(0.8, 0.2, 0.15)]
            root.addChildNode(tool)
        }

        // tire stack
        for i in 0..<3 {
            let tire = SCNNode(geometry: SCNTorus(ringRadius: 0.30, pipeRadius: 0.13))
            tire.position = SCNVector3(5.6, 0.14 + Float(i) * 0.27, -4.6)
            tire.eulerAngles.x = .pi / 2
            (tire.geometry as? SCNTorus)?.materials = [Mat.rubber]
            root.addChildNode(tire)
        }

        // red tool cabinet
        let cab = SCNNode(geometry: SCNBox(width: 1.0, height: 1.3, length: 0.6, chamferRadius: 0.02))
        cab.position = SCNVector3(4.6, 0.65, -5.5)
        (cab.geometry as? SCNBox)?.materials = [Mat.flat(0.72, 0.12, 0.10)]
        root.addChildNode(cab)
        for i in 0..<4 {
            let drawer = SCNNode(geometry: SCNBox(width: 0.86, height: 0.04, length: 0.03, chamferRadius: 0))
            drawer.position = SCNVector3(4.6, 0.35 + Float(i) * 0.28, -5.19)
            (drawer.geometry as? SCNBox)?.materials = [Mat.steelDark]
            root.addChildNode(drawer)
        }

        // hanging lights
        for (x, z) in [(Float(-3), Float(0)), (Float(3), Float(0))] as [(Float, Float)] {
            let cable = SCNNode(geometry: SCNCylinder(radius: 0.015, height: 1.0))
            cable.position = SCNVector3(x, 4.0, z)
            (cable.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
            root.addChildNode(cable)
            let shade = SCNNode(geometry: SCNCone(topRadius: 0.05, bottomRadius: 0.45, height: 0.35))
            shade.position = SCNVector3(x, 3.4, z)
            (shade.geometry as? SCNCone)?.materials = [Mat.flat(0.15, 0.5, 0.3)]
            root.addChildNode(shade)
            let bulb = SCNNode(geometry: SCNSphere(radius: 0.09))
            bulb.position = SCNVector3(x, 3.28, z)
            let bulbMat = SCNMaterial()
            bulbMat.emission.contents = UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1)
            (bulb.geometry as? SCNSphere)?.materials = [bulbMat]
            root.addChildNode(bulb)

            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
            light.intensity = 700
            light.attenuationStartDistance = 1
            light.attenuationEndDistance = 14
            let ln = SCNNode()
            ln.light = light
            ln.position = SCNVector3(x, 3.2, z)
            root.addChildNode(ln)
        }

        // ambient fill
        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(white: 0.45, alpha: 1)
        let ambNode = SCNNode()
        ambNode.light = amb
        root.addChildNode(ambNode)

        // neon sign on north wall
        let neon = SCNNode(geometry: SCNBox(width: 2.6, height: 0.5, length: 0.05, chamferRadius: 0.06))
        neon.position = SCNVector3(3.0, 3.0, -5.86)
        let neonMat = SCNMaterial()
        neonMat.emission.contents = UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1)
        neonMat.diffuse.contents = UIColor.black
        (neon.geometry as? SCNBox)?.materials = [neonMat]
        root.addChildNode(neon)
    }
}
