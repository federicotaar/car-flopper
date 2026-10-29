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
    static let steel = Mat.flat(0.62, 0.63, 0.67, rough: 0.35, metal: 0.85)
    static let steelDark = Mat.flat(0.22, 0.23, 0.26, rough: 0.5, metal: 0.7)
    static let chrome = Mat.flat(0.85, 0.86, 0.90, rough: 0.15, metal: 1.0)
    static let rubber = Mat.flat(0.08, 0.08, 0.09)
    static let glass = SCNMaterial()
    static let wood = Mat.flat(0.45, 0.32, 0.18)
    static let rust = Mat.flat(0.40, 0.22, 0.12)

    static func setup() {
        glass.diffuse.contents = UIColor(white: 0.38, alpha: 0.42)
        glass.specular.contents = UIColor(white: 0.9, alpha: 1)
        glass.isDoubleSided = true
        glass.roughness.contents = 0.12
        glass.metalness.contents = 0.05
    }
}

// MARK: - Procedural textures (drawn at runtime, no bundled assets)

enum TexGen {
    static func concrete() -> UIImage {
        let s = CGSize(width: 1024, height: 768) // covers 16m x 12m
        let r = UIGraphicsImageRenderer(size: s)
        return r.image { _ in
            UIColor(red: 0.40, green: 0.40, blue: 0.43, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: s))
            // speckle noise
            for _ in 0..<2600 {
                let v = CGFloat.random(in: 0.30...0.52)
                UIColor(red: v, green: v, blue: v + 0.015, alpha: CGFloat.random(in: 0.15...0.4)).setFill()
                let d = CGFloat.random(in: 1...3.5)
                UIRectFill(CGRect(x: CGFloat.random(in: 0..<s.width), y: CGFloat.random(in: 0..<s.height), width: d, height: d))
            }
            // expansion joints every 2m (128px x, 128px y)
            UIColor(white: 0.22, alpha: 0.85).setFill()
            for i in 1..<8 { UIRectFill(CGRect(x: CGFloat(i) * 128 - 1.5, y: 0, width: 3, height: s.height)) }
            for i in 1..<6 { UIRectFill(CGRect(x: 0, y: CGFloat(i) * 128 - 1.5, width: s.width, height: 3)) }
            // wear stains
            for _ in 0..<7 {
                UIColor(white: 0.18, alpha: CGFloat.random(in: 0.05...0.13)).setFill()
                let w = CGFloat.random(in: 60...220)
                UIBezierPath(ovalIn: CGRect(x: CGFloat.random(in: 0..<s.width), y: CGFloat.random(in: 0..<s.height), width: w, height: w * CGFloat.random(in: 0.4...0.9))).fill()
            }
            // tire marks
            UIColor(white: 0.16, alpha: 0.16).setStroke()
            for _ in 0..<5 {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: CGFloat.random(in: 0..<s.width), y: CGFloat.random(in: 0..<s.height)))
                p.addCurve(to: CGPoint(x: CGFloat.random(in: 0..<s.width), y: CGFloat.random(in: 0..<s.height)),
                           controlPoint1: CGPoint(x: CGFloat.random(in: 0..<s.width), y: CGFloat.random(in: 0..<s.height)),
                           controlPoint2: CGPoint(x: CGFloat.random(in: 0..<s.width), y: CGFloat.random(in: 0..<s.height)))
                p.lineWidth = CGFloat.random(in: 8...16)
                p.stroke()
            }
        }
    }

    static func wallPaint(base: (CGFloat, CGFloat, CGFloat)) -> UIImage {
        let s = CGSize(width: 1024, height: 288) // covers 16m x 4.5m
        let r = UIGraphicsImageRenderer(size: s)
        return r.image { _ in
            UIColor(red: base.0, green: base.1, blue: base.2, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: s))
            // cinderblock mortar: courses every 0.5m (32px), block joints every 1m (64px)
            UIColor(white: 0.0, alpha: 0.18).setFill()
            for i in 1..<9 { UIRectFill(CGRect(x: 0, y: CGFloat(i) * 32 - 1, width: s.width, height: 2)) }
            for course in 0..<9 {
                let off: CGFloat = course % 2 == 0 ? 0 : 32
                var x = off
                while x < s.width {
                    UIRectFill(CGRect(x: x - 1, y: CGFloat(course) * 32, width: 2, height: 32))
                    x += 64
                }
            }
            // grime at the bottom
            let grad = CAGradientLayer()
            grad.frame = CGRect(origin: .zero, size: s)
            grad.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.30).cgColor]
            grad.locations = [0, 0.7, 1]
            grad.render(in: UIGraphicsGetCurrentContext()!)
            // scuffs
            for _ in 0..<20 {
                UIColor(white: 0.2, alpha: CGFloat.random(in: 0.04...0.10)).setFill()
                let w = CGFloat.random(in: 10...70)
                UIBezierPath(ovalIn: CGRect(x: CGFloat.random(in: 0..<s.width), y: s.height - CGFloat.random(in: 10...80), width: w, height: w * 0.4)).fill()
            }
        }
    }
}

// MARK: - Garage environment

enum GarageBuilder {
    // Garage interior: 16 x 7 walls around a 16 x 12 floor, origin center.
    static func buildEnvironment(into root: SCNNode) {
        Mat.setup()

        // floor with procedural concrete
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = TexGen.concrete()
        floorMat.roughness.contents = 0.85
        floorMat.metalness.contents = 0.05
        let floor = SCNNode(geometry: SCNBox(width: 16, height: 0.1, length: 12, chamferRadius: 0))
        floor.position = SCNVector3(0, -0.05, 0)
        (floor.geometry as? SCNBox)?.materials = [floorMat]
        root.addChildNode(floor)

        // painted parking box lines around car bay
        for (x, z, w, l) in [(Float(-2.2), Float(0), Float(0.08), Float(5.4)),
                             (Float(2.2), Float(0), Float(0.08), Float(5.4)),
                             (Float(0), Float(2.7), Float(4.4), Float(0.08)),
                             (Float(0), Float(-2.7), Float(4.4), Float(0.08))] {
            let line = SCNNode(geometry: SCNBox(width: CGFloat(w), height: 0.01, length: CGFloat(l), chamferRadius: 0))
            line.position = SCNVector3(x, 0.005, z)
            (line.geometry as? SCNBox)?.materials = [Mat.flat(0.85, 0.72, 0.15, rough: 0.6)]
            root.addChildNode(line)
        }

        // oil stains
        for (x, z, s) in [(Float(3.4), Float(1.8), Float(0.9)), (Float(-3.1), Float(-2.2), Float(1.3)), (Float(1.2), Float(-3.4), Float(0.7))] {
            let stain = SCNNode(geometry: SCNCylinder(radius: CGFloat(s * 0.5), height: 0.005))
            stain.position = SCNVector3(x, 0.003, z)
            (stain.geometry as? SCNCylinder)?.materials = [Mat.flat(0.16, 0.16, 0.18, rough: 0.35)]
            root.addChildNode(stain)
        }

        // walls with cinderblock paint
        let wallMatN = SCNMaterial(); wallMatN.diffuse.contents = TexGen.wallPaint(base: (0.56, 0.54, 0.50)); wallMatN.roughness.contents = 0.92
        let wallMatD = SCNMaterial(); wallMatD.diffuse.contents = TexGen.wallPaint(base: (0.40, 0.38, 0.35)); wallMatD.roughness.contents = 0.92

        let wallN = SCNNode(geometry: SCNBox(width: 16, height: 4.5, length: 0.2, chamferRadius: 0))
        wallN.position = SCNVector3(0, 2.25, -6)
        (wallN.geometry as? SCNBox)?.materials = [wallMatN]
        root.addChildNode(wallN)

        let wallS = SCNNode(geometry: SCNBox(width: 16, height: 4.5, length: 0.2, chamferRadius: 0))
        wallS.position = SCNVector3(0, 2.25, 6)
        (wallS.geometry as? SCNBox)?.materials = [wallMatD]
        root.addChildNode(wallS)

        let wallW = SCNNode(geometry: SCNBox(width: 0.2, height: 4.5, length: 12, chamferRadius: 0))
        wallW.position = SCNVector3(-8, 2.25, 0)
        (wallW.geometry as? SCNBox)?.materials = [wallMatN]
        root.addChildNode(wallW)

        let wallE = SCNNode(geometry: SCNBox(width: 0.2, height: 4.5, length: 12, chamferRadius: 0))
        wallE.position = SCNVector3(8, 2.25, 0)
        (wallE.geometry as? SCNBox)?.materials = [wallMatD]
        root.addChildNode(wallE)

        // dark skirting bands
        for (x, z, w, l) in [(Float(0), Float(-5.88), Float(16), Float(0.06)),
                             (Float(0), Float(5.88), Float(16), Float(0.06)),
                             (Float(-7.88), Float(0), Float(0.06), Float(12)),
                             (Float(7.88), Float(0), Float(0.06), Float(12))] {
            let skirt = SCNNode(geometry: SCNBox(width: CGFloat(w), height: 0.28, length: CGFloat(l), chamferRadius: 0))
            skirt.position = SCNVector3(x, 0.14, z)
            (skirt.geometry as? SCNBox)?.materials = [Mat.steelDark]
            root.addChildNode(skirt)
        }

        // safety stripe along the north wall
        let stripe = SCNNode(geometry: SCNBox(width: 16, height: 0.34, length: 0.03, chamferRadius: 0))
        stripe.position = SCNVector3(0, 1.35, -5.88)
        (stripe.geometry as? SCNBox)?.materials = [Mat.flat(0.80, 0.62, 0.10, rough: 0.7)]
        root.addChildNode(stripe)

        // ceiling beams
        for i in 0..<4 {
            let beam = SCNNode(geometry: SCNBox(width: 0.22, height: 0.3, length: 12, chamferRadius: 0.01))
            beam.position = SCNVector3(-6 + Float(i) * 4, 4.35, 0)
            (beam.geometry as? SCNBox)?.materials = [Mat.flat(0.30, 0.27, 0.24, rough: 0.8)]
            root.addChildNode(beam)
        }

        // window strip high on the north wall, cool daylight glow
        for i in 0..<4 {
            let frame = SCNNode(geometry: SCNBox(width: 1.7, height: 0.9, length: 0.08, chamferRadius: 0.01))
            frame.position = SCNVector3(-4.8 + Float(i) * 3.2, 3.6, -5.90)
            (frame.geometry as? SCNBox)?.materials = [Mat.steelDark]
            root.addChildNode(frame)
            let pane = SCNNode(geometry: SCNBox(width: 1.5, height: 0.72, length: 0.04, chamferRadius: 0))
            pane.position = SCNVector3(-4.8 + Float(i) * 3.2, 3.6, -5.87)
            let pm = SCNMaterial()
            pm.emission.contents = UIColor(red: 0.55, green: 0.72, blue: 0.90, alpha: 1)
            pm.diffuse.contents = UIColor.black
            (pane.geometry as? SCNBox)?.materials = [pm]
            root.addChildNode(pane)
        }

        // roll-up door on south wall (visual)
        let door = SCNNode(geometry: SCNBox(width: 5.5, height: 3.2, length: 0.1, chamferRadius: 0))
        door.position = SCNVector3(0, 1.6, 5.92)
        (door.geometry as? SCNBox)?.materials = [Mat.flat(0.30, 0.31, 0.35, rough: 0.45, metal: 0.8)]
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
        // clutter on the bench
        for (dx, w, h, c) in [(Float(-1.1), Float(0.3), Float(0.18), Mat.flat(0.75, 0.20, 0.12, rough: 0.5)),
                              (Float(-0.3), Float(0.45), Float(0.10), Mat.steelDark),
                              (Float(0.5), Float(0.2), Float(0.26), Mat.flat(0.20, 0.35, 0.65, rough: 0.5)),
                              (Float(1.2), Float(0.35), Float(0.12), Mat.wood)] as [(Float, Float, Float, SCNMaterial)] {
            let cl = SCNNode(geometry: SCNBox(width: CGFloat(w), height: CGFloat(h), length: 0.28, chamferRadius: 0.02))
            cl.position = SCNVector3(-3.5 + dx, 1.01 + h / 2, -5.3)
            (cl.geometry as? SCNBox)?.materials = [c]
            root.addChildNode(cl)
        }
        // pegboard + tools silhouettes
        let peg = SCNNode(geometry: SCNBox(width: 3.2, height: 1.4, length: 0.06, chamferRadius: 0))
        peg.position = SCNVector3(-3.5, 2.2, -5.85)
        (peg.geometry as? SCNBox)?.materials = [Mat.flat(0.50, 0.38, 0.24, rough: 0.85)]
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
        (cab.geometry as? SCNBox)?.materials = [Mat.flat(0.72, 0.12, 0.10, rough: 0.4, metal: 0.3)]
        root.addChildNode(cab)
        for i in 0..<4 {
            let drawer = SCNNode(geometry: SCNBox(width: 0.86, height: 0.04, length: 0.03, chamferRadius: 0))
            drawer.position = SCNVector3(4.6, 0.35 + Float(i) * 0.28, -5.19)
            (drawer.geometry as? SCNBox)?.materials = [Mat.chrome]
            root.addChildNode(drawer)
        }

        // rolling diagnostics cart (east side)
        let cart = SCNNode(geometry: SCNBox(width: 0.7, height: 0.85, length: 0.5, chamferRadius: 0.03))
        cart.position = SCNVector3(6.8, 0.48, 2.8)
        (cart.geometry as? SCNBox)?.materials = [Mat.flat(0.25, 0.32, 0.55, rough: 0.5, metal: 0.4)]
        root.addChildNode(cart)
        for (dx, dz) in [(-0.28, -0.18), (0.28, -0.18), (-0.28, 0.18), (0.28, 0.18)] as [(Float, Float)] {
            let cw = SCNNode(geometry: SCNSphere(radius: 0.06))
            (cw.geometry as? SCNSphere)?.materials = [Mat.rubber]
            cw.position = SCNVector3(6.8 + dx, 0.06, 2.8 + dz)
            root.addChildNode(cw)
        }

        // oil drums
        for (x, z) in [(Float(-6.6), Float(-4.6)), (Float(-7.1), Float(-3.7))] {
            let drum = SCNNode(geometry: SCNCylinder(radius: 0.32, height: 0.95))
            drum.position = SCNVector3(x, 0.475, z)
            (drum.geometry as? SCNCylinder)?.materials = [Mat.flat(0.15, 0.30, 0.55, rough: 0.5, metal: 0.5)]
            root.addChildNode(drum)
            for dy in [-0.18, 0.18] as [Float] {
                let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.325, pipeRadius: 0.02))
                ring.position = SCNVector3(x, 0.475 + dy, z)
                ring.eulerAngles.x = .pi / 2
                (ring.geometry as? SCNTorus)?.materials = [Mat.flat(0.12, 0.25, 0.46, rough: 0.5, metal: 0.5)]
                root.addChildNode(ring)
            }
        }

        // fire extinguisher on the west wall
        let ext = SCNNode(geometry: SCNCylinder(radius: 0.09, height: 0.42))
        ext.position = SCNVector3(-7.8, 1.15, -1.0)
        (ext.geometry as? SCNCylinder)?.materials = [Mat.flat(0.80, 0.10, 0.08, rough: 0.4, metal: 0.4)]
        root.addChildNode(ext)

        // cardboard boxes
        for (x, z, s, h) in [(Float(6.6), Float(4.6), Float(0.65), Float(0.55)), (Float(6.9), Float(3.9), Float(0.5), Float(0.4)), (Float(6.55), Float(4.45), Float(0.45), Float(1.05))] {
            let bx = SCNNode(geometry: SCNBox(width: CGFloat(s), height: CGFloat(h == 1.05 ? 0.45 : h), length: CGFloat(s), chamferRadius: 0.02))
            bx.position = SCNVector3(x, h == 1.05 ? 1.0 : h / 2, z)
            bx.eulerAngles.y = Float.random(in: -0.3...0.3)
            (bx.geometry as? SCNBox)?.materials = [Mat.flat(0.55, 0.42, 0.25, rough: 0.95)]
            root.addChildNode(bx)
        }

        // hanging lights
        for (x, z) in [(Float(-3), Float(0)), (Float(3), Float(0))] as [(Float, Float)] {
            let cable = SCNNode(geometry: SCNCylinder(radius: 0.015, height: 1.0))
            cable.position = SCNVector3(x, 4.0, z)
            (cable.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
            root.addChildNode(cable)
            let shade = SCNNode(geometry: SCNCone(topRadius: 0.05, bottomRadius: 0.45, height: 0.35))
            shade.position = SCNVector3(x, 3.4, z)
            (shade.geometry as? SCNCone)?.materials = [Mat.flat(0.15, 0.45, 0.28, rough: 0.4, metal: 0.6)]
            root.addChildNode(shade)
            let bulb = SCNNode(geometry: SCNSphere(radius: 0.09))
            bulb.position = SCNVector3(x, 3.28, z)
            let bulbMat = SCNMaterial()
            bulbMat.emission.contents = UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1)
            (bulb.geometry as? SCNSphere)?.materials = [bulbMat]
            root.addChildNode(bulb)

            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(red: 1.0, green: 0.94, blue: 0.82, alpha: 1)
            light.intensity = 520
            light.attenuationStartDistance = 0.8
            light.attenuationEndDistance = 13
            let ln = SCNNode()
            ln.light = light
            ln.position = SCNVector3(x, 3.2, z)
            root.addChildNode(ln)
        }

        // key light: angled from the window side, casts real shadows
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        key.intensity = 850
        key.castsShadow = true
#if targetEnvironment(simulator)
        key.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.shadowSampleCount = 8
#else
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowSampleCount = 12
#endif
        key.shadowRadius = 4
        key.shadowColor = UIColor(white: 0, alpha: 0.5)
        key.orthographicScale = 12
        key.zNear = 2
        key.zFar = 30
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0, 10, -4)
        keyNode.eulerAngles = SCNVector3(-1.25, 0, 0)
        root.addChildNode(keyNode)

        // cool fill from the door side, no shadows
        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 1)
        fill.intensity = 130
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.9, 2.6, 0)
        root.addChildNode(fillNode)

        // ambient fill
        let amb = SCNLight()
        amb.type = .ambient
        amb.color = UIColor(white: 0.30, alpha: 1)
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

        buildToolStations(into: root)
    }

    // MARK: tool stations: glowing spot + floating tool you walk into to equip

    private static func buildToolStations(into root: SCNNode) {
        for st in GameContent.toolStations {
            guard let td = GameContent.tools[st.tool] else { continue }
            // glowing floor ring
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.55, pipeRadius: 0.035))
            ring.eulerAngles.x = .pi / 2
            ring.position = SCNVector3(st.x, 0.04, st.z)
            let rm = SCNMaterial()
            rm.emission.contents = td.color.withAlphaComponent(0.9)
            rm.diffuse.contents = UIColor.black
            (ring.geometry as? SCNTorus)?.materials = [rm]
            root.addChildNode(ring)

            // floating tool model
            let holder = SCNNode()
            holder.position = SCNVector3(st.x, 1.05, st.z)
            holder.addChildNode(toolModel(st.tool, color: td.color))
            holder.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.12, z: 0, duration: 0.9),
                .moveBy(x: 0, y: -0.12, z: 0, duration: 0.9),
            ])))
            holder.runAction(.repeatForever(.rotateBy(x: 0, y: 1.6, z: 0, duration: 2.4)))
            root.addChildNode(holder)

            // label
            let label = SCNNode(geometry: SCNPlane(width: 1.5, height: 0.34))
            label.position = SCNVector3(st.x, 1.65, st.z)
            let lm = SCNMaterial()
            lm.diffuse.contents = AvatarNode.makeLabelImage(name: td.label, color: td.color)
            lm.isDoubleSided = true
            (label.geometry as? SCNPlane)?.materials = [lm]
            let bb = SCNBillboardConstraint()
            bb.freeAxes = .Y
            label.constraints = [bb]
            root.addChildNode(label)
        }
    }

    private static func toolModel(_ tool: String, color: UIColor) -> SCNNode {
        let n = SCNNode()
        let accent = Mat.flat(0, 0, 0); accent.diffuse.contents = color; accent.roughness.contents = 0.4; accent.metalness.contents = 0.3
        switch tool {
        case "wrench":
            let handle = SCNNode(geometry: SCNBox(width: 0.07, height: 0.55, length: 0.04, chamferRadius: 0.02))
            (handle.geometry as? SCNBox)?.materials = [Mat.chrome]
            n.addChildNode(handle)
            let jaw = SCNNode(geometry: SCNTorus(ringRadius: 0.10, pipeRadius: 0.035))
            jaw.position = SCNVector3(0, 0.32, 0)
            (jaw.geometry as? SCNTorus)?.materials = [Mat.chrome]
            n.addChildNode(jaw)
            let grip = SCNNode(geometry: SCNBox(width: 0.09, height: 0.16, length: 0.05, chamferRadius: 0.03))
            grip.position = SCNVector3(0, -0.2, 0)
            (grip.geometry as? SCNBox)?.materials = [accent]
            n.addChildNode(grip)
        case "screwdriver":
            let handle = SCNNode(geometry: SCNCylinder(radius: 0.05, height: 0.22))
            handle.position = SCNVector3(0, -0.12, 0)
            (handle.geometry as? SCNCylinder)?.materials = [accent]
            n.addChildNode(handle)
            let shaft = SCNNode(geometry: SCNCylinder(radius: 0.018, height: 0.38))
            shaft.position = SCNVector3(0, 0.2, 0)
            (shaft.geometry as? SCNCylinder)?.materials = [Mat.chrome]
            n.addChildNode(shaft)
        case "welder":
            let body = SCNNode(geometry: SCNBox(width: 0.3, height: 0.28, length: 0.2, chamferRadius: 0.03))
            (body.geometry as? SCNBox)?.materials = [accent]
            n.addChildNode(body)
            let torch = SCNNode(geometry: SCNCylinder(radius: 0.025, height: 0.3))
            torch.position = SCNVector3(0.22, -0.05, 0)
            torch.eulerAngles.z = 0.9
            (torch.geometry as? SCNCylinder)?.materials = [Mat.steelDark]
            n.addChildNode(torch)
            let tip = SCNNode(geometry: SCNSphere(radius: 0.04))
            tip.position = SCNVector3(0.35, -0.15, 0)
            let tm = SCNMaterial(); tm.emission.contents = UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 1)
            (tip.geometry as? SCNSphere)?.materials = [tm]
            n.addChildNode(tip)
        default: // diagnostics tablet
            let tab = SCNNode(geometry: SCNBox(width: 0.26, height: 0.36, length: 0.03, chamferRadius: 0.02))
            (tab.geometry as? SCNBox)?.materials = [Mat.steelDark]
            n.addChildNode(tab)
            let screen = SCNNode(geometry: SCNPlane(width: 0.21, height: 0.30))
            screen.position = SCNVector3(0, 0, 0.02)
            let sm = SCNMaterial(); sm.emission.contents = color; sm.isDoubleSided = true
            (screen.geometry as? SCNPlane)?.materials = [sm]
            n.addChildNode(screen)
        }
        return n
    }
}
