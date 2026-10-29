import Foundation
import SceneKit
import UIKit

// MARK: - Procedural lofted car surfaces.
// Cross-section stations along the car length are lofted into continuous
// triangle meshes with smooth normals. Wheel-arch openings, the open engine
// bay and the greenhouse all come from the same section machinery, so body,
// glass and pillars stay consistent per silhouette.

struct BodyStation {
    var z: Float
    var floorY: Float   // lower edge of the section (arches raise this)
    var halfW: Float    // half width at the widest point
    var topY: Float     // top surface height at the centerline
    var square: Float   // section squareness: 1.0 = round, 2.5+ = slab side
    var bay: Bool       // true = top middle left open (engine bay)
}

enum CarMesh {

    // half-profile point on a section: t in [0,1], 0 = bottom edge, 1 = centerline top
    private static func prof(_ st: BodyStation, _ t: Float) -> (x: Float, y: Float) {
        let a = t * Float.pi / 2
        let x = st.halfW * powf(cosf(a), 1.0 / st.square)
        let y = st.floorY + (st.topY - st.floorY) * powf(sinf(a), 0.85)
        return (x, y)
    }

    // Build one row of vertices across the car for a station.
    // Full section: left bottom -> center top -> right bottom.
    // Bay section: left strip + right strip, middle open.
    // tRange selects a vertical band (used for roof skin / glass bands / pillars).
    // Always two strips per station (left half, right half) so bay<->solid
    // transitions stitch with matching topology. Bay stations stop their
    // strips at tBay, leaving the middle open; neighbours ramp closed.
    private static func row(_ st: BodyStation, _ n: Int, _ t0: Float, _ t1: Float) -> [[SCNVector3]] {
        let tTop = (st.bay && t1 > 0.55) ? Float(0.55) : t1
        var l: [SCNVector3] = []
        var r: [SCNVector3] = []
        for i in 0...n {
            let t = t0 + (tTop - t0) * Float(i) / Float(n)
            let p = prof(st, t)
            l.append(SCNVector3(-p.x, p.y, st.z))
            r.append(SCNVector3(p.x, p.y, st.z))
        }
        return [l, r]
    }

    struct Mesh { var v: [SCNVector3] = []; var n: [SCNVector3] = []; var idx: [Int32] = [] }

    // Loft a set of stations into a smooth mesh. tRange bands the section.
    static func loft(_ stations: [BodyStation], segs: Int = 10, t0: Float = 0, t1: Float = 1) -> Mesh {
        var m = Mesh()
        var prevStripCounts: [Int] = []
        var stripStarts: [Int] = []
        for (si, st) in stations.enumerated() {
            let rows = row(st, segs, t0, t1)
            var starts: [Int] = []
            for (ri, r) in rows.enumerated() {
                starts.append(m.v.count)
                m.v.append(contentsOf: r)
                // stitch to previous station's matching strip
                if si > 0 && ri < prevStripCounts.count {
                    let pStart = stripStarts[ri]
                    let count = min(r.count, prevStripCounts[ri])
                    for i in 0..<(count - 1) {
                        let a = Int32(pStart + i), b = Int32(pStart + i + 1)
                        let c = Int32(starts[ri] + i), d = Int32(starts[ri] + i + 1)
                        m.idx.append(contentsOf: [a, c, b, b, c, d])
                    }
                }
            }
            prevStripCounts = rows.map { $0.count }
            stripStarts = starts
        }
        m.n = smoothNormals(m.v, m.idx)
        return m
    }

    // Flat end cap across a station's row polyline (fan around centroid).
    static func cap(_ st: BodyStation, segs: Int = 10, flip: Bool) -> Mesh {
        let rows = row(st, segs, 0, 1)
        var m = Mesh()
        for r in rows {
            var cx: Float = 0, cy: Float = 0
            for p in r { cx += p.x; cy += p.y }
            cx /= Float(r.count); cy /= Float(r.count)
            let base = Int32(m.v.count)
            m.v.append(SCNVector3(cx, cy, st.z))
            m.v.append(contentsOf: r)
            for i in 0..<r.count {
                let a = base, b = base + 1 + Int32(i), c = base + 1 + Int32((i + 1) % r.count)
                m.idx.append(contentsOf: flip ? [a, c, b] : [a, b, c])
            }
        }
        // flat normal facing +/-z
        let nz: Float = flip ? -1 : 1
        m.n = m.v.map { _ in SCNVector3(0, 0, nz) }
        return m
    }

    static func smoothNormals(_ v: [SCNVector3], _ idx: [Int32]) -> [SCNVector3] {
        var acc = [SIMD3<Float>](repeating: .zero, count: v.count)
        var i = 0
        while i + 2 < idx.count {
            let a = Int(idx[i]), b = Int(idx[i + 1]), c = Int(idx[i + 2])
            let pa = SIMD3<Float>(v[a].x, v[a].y, v[a].z)
            let pb = SIMD3<Float>(v[b].x, v[b].y, v[b].z)
            let pc = SIMD3<Float>(v[c].x, v[c].y, v[c].z)
            let n = simd_cross(pb - pa, pc - pa)
            acc[a] += n; acc[b] += n; acc[c] += n
            i += 3
        }
        return acc.map { nv in
            let l = simd_length(nv)
            let u = l > 0.0001 ? nv / l : SIMD3<Float>(0, 1, 0)
            return SCNVector3(u.x, u.y, u.z)
        }
    }

    static func geometry(_ m: Mesh, material: SCNMaterial) -> SCNNode {
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: m.v),
                                      SCNGeometrySource(normals: m.n)],
                            elements: [SCNGeometryElement(indices: m.idx, primitiveType: .triangles)])
        g.materials = [material]
        return SCNNode(geometry: g)
    }

    // Revolve a (radius, y) profile around the X axis (wheel lathe).
    static func latheX(_ profile: [(Float, Float)], segs: Int, material: SCNMaterial) -> SCNNode {
        var m = Mesh()
        let n = profile.count
        for s in 0...segs {
            let a = Float(s) / Float(segs) * 2 * Float.pi
            let ca = cosf(a), sa = sinf(a)
            for (r, x) in profile {
                m.v.append(SCNVector3(x, r * ca, r * sa))
            }
        }
        for s in 0..<segs {
            for i in 0..<(n - 1) {
                let a = Int32(s * n + i), b = Int32(s * n + i + 1)
                let c = Int32((s + 1) * n + i), d = Int32((s + 1) * n + i + 1)
                m.idx.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        m.n = smoothNormals(m.v, m.idx)
        return geometry(m, material: material)
    }

    // MARK: - station data

    // arch helper: raise floorY around wheel centers
    static func applyArches(_ stations: inout [BodyStation], wheels: [(z: Float, y: Float, r: Float)]) {
        for i in stations.indices {
            for w in wheels {
                let dz = abs(stations[i].z - w.z)
                if dz < w.r {
                    let ay = w.y + sqrtf(w.r * w.r - dz * dz) + 0.02
                    if ay > stations[i].floorY { stations[i].floorY = ay }
                }
            }
        }
    }

    // Main body shell for a coupe-ish silhouette, front at +z.
    static func bodyStations() -> [BodyStation] {
        var s: [BodyStation] = []
        func st(_ z: Float, _ f: Float, _ w: Float, _ t: Float, _ sq: Float = 2.2, _ bay: Bool = false) {
            s.append(BodyStation(z: z, floorY: f, halfW: w, topY: t, square: sq, bay: bay))
        }
        st(2.32, 0.28, 0.87, 0.56)          // nose tip
        st(2.22, 0.20, 0.92, 0.70)          // bumper line
        st(2.02, 0.18, 0.935, 0.84)         // hood leading edge
        st(1.70, 0.18, 0.94, 0.885, 2.4, true)   // bay front
        st(1.30, 0.18, 0.94, 0.905, 2.4, true)   // bay mid (fender tops)
        st(0.90, 0.18, 0.935, 0.915, 2.4, true)  // bay rear
        st(0.66, 0.18, 0.93, 0.94)          // cowl / firewall
        st(0.30, 0.18, 0.925, 0.955)        // door front
        st(-0.10, 0.18, 0.92, 0.96, 2.3)    // door mid
        st(-0.55, 0.18, 0.915, 0.955)       // door rear / quarter
        st(-1.05, 0.18, 0.91, 0.94)         // rear quarter
        st(-1.55, 0.19, 0.895, 0.915)       // trunk deck
        st(-1.95, 0.22, 0.88, 0.86)         // tail
        st(-2.26, 0.28, 0.86, 0.68)         // tail tip
        applyArches(&s, wheels: [(1.38, 0.36, 0.47), (-1.38, 0.36, 0.47)])
        return s
    }

    // Greenhouse stations (cabin), same z reference. y0 = beltline, roof per z.
    static func greenhouseStations() -> [BodyStation] {
        var s: [BodyStation] = []
        func st(_ z: Float, _ w: Float, _ t: Float, _ sq: Float = 1.7) {
            s.append(BodyStation(z: z, floorY: 0.985, halfW: w, topY: t, square: sq, bay: false))
        }
        st(0.62, 0.55, 0.97)   // windshield base (cowl)
        st(0.28, 0.61, 1.24)   // windshield slope
        st(-0.02, 0.63, 1.33)  // roof front
        st(-0.48, 0.63, 1.335) // roof mid
        st(-0.85, 0.61, 1.30)  // roof rear
        st(-1.22, 0.57, 1.16)  // backlight slope
        st(-1.55, 0.50, 0.97)  // backlight base (trunk)
        return s
    }
}
