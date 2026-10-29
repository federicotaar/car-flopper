import Foundation
import UIKit

// MARK: - Static game content: cars, parts, palette

struct PartDef {
    let id: String
    let label: String
    let x: Float   // repair hotspot, car-local
    let y: Float
    let z: Float
    let seconds: Float // solo repair time
}

struct CarDef {
    let name: String
    let tagline: String
    let bodyRGB: (CGFloat, CGFloat, CGFloat)
    let accentRGB: (CGFloat, CGFloat, CGFloat)
    let hasSpoiler: Bool
    let parts: [PartDef]
}

enum GameContent {
    static let playerColors: [UIColor] = [
        UIColor(red: 0.95, green: 0.35, blue: 0.25, alpha: 1), // red
        UIColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1), // blue
        UIColor(red: 0.35, green: 0.85, blue: 0.40, alpha: 1), // green
        UIColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1), // yellow
    ]

    static func playerColor(_ index: Int) -> UIColor {
        playerColors[abs(index) % playerColors.count]
    }

    static func playerColorHex(_ index: Int) -> String {
        let c = playerColor(index)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    static func parts(wheelsMissing: Bool) -> [PartDef] {
        var list = [
            PartDef(id: "wheelFL", label: "Front left wheel", x: -0.90, y: 0.36, z: 1.30, seconds: 7),
            PartDef(id: "wheelFR", label: "Front right wheel", x: 0.90, y: 0.36, z: 1.30, seconds: 7),
            PartDef(id: "wheelRL", label: "Rear left wheel", x: -0.90, y: 0.36, z: -1.30, seconds: 7),
            PartDef(id: "wheelRR", label: "Rear right wheel", x: 0.90, y: 0.36, z: -1.30, seconds: 7),
            PartDef(id: "engine", label: "Engine", x: 0.0, y: 0.85, z: 1.45, seconds: 12),
            PartDef(id: "door", label: "Driver door", x: -0.95, y: 0.72, z: -0.05, seconds: 9),
            PartDef(id: "windshield", label: "Windshield", x: 0.0, y: 1.02, z: 0.55, seconds: 9),
            PartDef(id: "exhaust", label: "Exhaust", x: 0.35, y: 0.28, z: -2.05, seconds: 8),
        ]
        if wheelsMissing { /* same list; visual handled per car */ }
        return list
    }

    static let cars: [CarDef] = [
        CarDef(name: "Rusty Coupe", tagline: "She sat in a barn for 20 years. Bring her back.",
               bodyRGB: (0.62, 0.20, 0.14), accentRGB: (0.25, 0.25, 0.28), hasSpoiler: false,
               parts: parts(wheelsMissing: false)),
        CarDef(name: "Drift 350", tagline: "Angle kit, big wing, no fear. Needs love first.",
               bodyRGB: (0.95, 0.45, 0.05), accentRGB: (0.05, 0.05, 0.06), hasSpoiler: true,
               parts: parts(wheelsMissing: false)),
        CarDef(name: "Supra MK", tagline: "The legend. Fix her and the garage is yours.",
               bodyRGB: (0.92, 0.92, 0.94), accentRGB: (0.10, 0.25, 0.85), hasSpoiler: true,
               parts: parts(wheelsMissing: false)),
    ]

    static let repairReach: Float = 2.3
    static let coopBonus: Float = 0.7 // each extra player on same part adds 70% speed
}
