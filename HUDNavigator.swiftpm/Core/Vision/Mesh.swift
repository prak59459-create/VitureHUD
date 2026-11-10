import Foundation

// 3D スキャンの三角形メッシュ。
// 毎フレームの奥行き（LiDAR・AI）を「表面からの距離（TSDF）」の小さな立方体（ボクセル）に重ねて平均し、
// その 0 になる所（＝物の表面）を三角形でつなぐ（Surface Nets）。LiDAR がなくてもメッシュになる。

/// 三角形メッシュ（世界座標・m・Y が上）
public struct TriangleMesh: Sendable {
    public var vertices: [Point3] = []
    /// 頂点の色（r, g, b を並べたもの）
    public var colors: [UInt8] = []
    /// 3 つずつで 1 つの三角形（0 始まり）
    public var indices: [UInt32] = []

    public init() {}

    public var triangleCount: Int { indices.count / 3 }
    public var isEmpty: Bool { indices.isEmpty }

    /// OBJ（頂点色付き：v x y z r g b）。Blender・MeshLab などで開ける。
    public func obj(name: String = "HUDNavigatorScan") -> String {
        var s = "# HUD Navigator 3D scan (meters, Y up)\n# vertices \(vertices.count), triangles \(triangleCount)\no \(name)\n"
        s.reserveCapacity(s.count + vertices.count * 48 + indices.count * 8)
        for (i, v) in vertices.enumerated() {
            let r = Double(colors[i * 3]) / 255, g = Double(colors[i * 3 + 1]) / 255, b = Double(colors[i * 3 + 2]) / 255
            s += String(format: "v %.4f %.4f %.4f %.3f %.3f %.3f\n", v.x, v.y, v.z, r, g, b)
        }
        var i = 0
        while i + 2 < indices.count {
            s += "f \(indices[i] + 1) \(indices[i + 1] + 1) \(indices[i + 2] + 1)\n"
            i += 3
        }
        return s
    }

    /// PLY（頂点色付きのメッシュ）
    public func ply() -> String {
        var s = "ply\nformat ascii 1.0\ncomment HUD Navigator 3D scan mesh (meters, Y up)\nelement vertex \(vertices.count)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nelement face \(triangleCount)\nproperty list uchar int vertex_indices\nend_header\n"
        for (i, v) in vertices.enumerated() {
            s += String(format: "%.4f %.4f %.4f %d %d %d\n", v.x, v.y, v.z, Int(colors[i * 3]), Int(colors[i * 3 + 1]), Int(colors[i * 3 + 2]))
        }
        var i = 0
        while i + 2 < indices.count {
            s += "3 \(indices[i]) \(indices[i + 1]) \(indices[i + 2])\n"
            i += 3
        }
        return s
    }
}

/// 表面からの距離を重ねるボクセルの集まり（必要な所だけ作る）
public struct TSDFVolume: Sendable {
    struct Voxel: Sendable {
        var tsdf: Float
        var weight: Float
        var r: Float, g: Float, b: Float
    }

    public let voxelSize: Float
    /// 表面の前後どこまでを記録するか（m）
    public let truncation: Float
    public var maxWeight: Float = 40
    public var maxVoxels: Int
    private(set) var voxels: [Int64: Voxel] = [:]

    public init(voxelSize: Float = 0.05, truncationVoxels: Float = 3, maxVoxels: Int = 3_000_000) {
        self.voxelSize = voxelSize
        self.truncation = voxelSize * truncationVoxels
        self.maxVoxels = maxVoxels
    }

    public var count: Int { voxels.count }

    public mutating func removeAll() { voxels.removeAll() }

    // 21 ビットずつに詰めた番号（-1,048,576〜1,048,575）
    static let mask: Int64 = 0x1FFFFF
    static func key(_ x: Int, _ y: Int, _ z: Int) -> Int64 {
        ((Int64(x) & mask) << 42) | ((Int64(y) & mask) << 21) | (Int64(z) & mask)
    }
    static func unpack(_ k: Int64) -> (Int, Int, Int) {
        func ext(_ v: Int64) -> Int { Int(v & 0x100000 != 0 ? v - 0x200000 : v) }
        return (ext((k >> 42) & mask), ext((k >> 21) & mask), ext(k & mask))
    }

    func index(_ p: Point3) -> (Int, Int, Int) {
        (Int((p.x / voxelSize).rounded(.down)), Int((p.y / voxelSize).rounded(.down)), Int((p.z / voxelSize).rounded(.down)))
    }

    /// ボクセルの中心
    func center(_ x: Int, _ y: Int, _ z: Int) -> Point3 {
        Point3((Float(x) + 0.5) * voxelSize, (Float(y) + 0.5) * voxelSize, (Float(z) + 0.5) * voxelSize)
    }

    /// 1 本の光線を重ねる：カメラの位置 origin から点 hit まで見えた（その間は空間、hit が表面）
    public mutating func integrate(origin: Point3, hit: Point3, color: (UInt8, UInt8, UInt8), weight: Float = 1) {
        let dx = hit.x - origin.x, dy = hit.y - origin.y, dz = hit.z - origin.z
        let depth = (dx * dx + dy * dy + dz * dz).squareRoot()
        guard depth > 0.05, depth.isFinite else { return }
        let ux = dx / depth, uy = dy / depth, uz = dz / depth
        let step = voxelSize * 0.5
        var t = max(0, depth - truncation)
        var lastKey: Int64?
        while t <= depth + truncation {
            let p = Point3(origin.x + ux * t, origin.y + uy * t, origin.z + uz * t)
            let (ix, iy, iz) = index(p)
            let k = Self.key(ix, iy, iz)
            if k != lastKey {
                lastKey = k
                // ボクセルの中心で表面までの距離を測る（前＝プラス、奥＝マイナス）
                let c = center(ix, iy, iz)
                let along = (c.x - origin.x) * ux + (c.y - origin.y) * uy + (c.z - origin.z) * uz
                let sdf = depth - along
                if sdf >= -truncation {
                    let value = max(-1, min(1, sdf / truncation))
                    update(k, value: value, weight: weight, color: abs(sdf) < voxelSize * 1.5 ? color : nil)
                }
            }
            t += step
        }
    }

    private mutating func update(_ k: Int64, value: Float, weight w: Float, color: (UInt8, UInt8, UInt8)?) {
        if var v = voxels[k] {
            let total = v.weight + w
            v.tsdf = (v.tsdf * v.weight + value * w) / total
            if let c = color {
                v.r = (v.r * v.weight + Float(c.0) * w) / total
                v.g = (v.g * v.weight + Float(c.1) * w) / total
                v.b = (v.b * v.weight + Float(c.2) * w) / total
            }
            v.weight = min(total, maxWeight)
            voxels[k] = v
        } else {
            guard voxels.count < maxVoxels else { return }
            let c = color ?? (160, 160, 160)
            voxels[k] = Voxel(tsdf: value, weight: w, r: Float(c.0), g: Float(c.1), b: Float(c.2))
        }
    }

    /// 表面を三角形にする（Surface Nets）。minWeight 回以上見えたボクセルだけ使う。
    public func extractMesh(minWeight: Float = 2) -> TriangleMesh {
        var mesh = TriangleMesh()
        var cubeVertex: [Int64: UInt32] = [:]
        cubeVertex.reserveCapacity(voxels.count / 4)

        func voxel(_ x: Int, _ y: Int, _ z: Int) -> Voxel? {
            guard let v = voxels[Self.key(x, y, z)], v.weight >= minWeight else { return nil }
            return v
        }
        let cornerOffsets: [(Int, Int, Int)] = [(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)]
        let edges: [(Int, Int)] = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]

        // 1. 表面をまたぐ立方体ごとに 1 つ頂点を置く（辺の交点の平均）
        for k in voxels.keys {
            let (x, y, z) = Self.unpack(k)
            var corners: [Voxel] = []
            corners.reserveCapacity(8)
            for o in cornerOffsets {
                guard let v = voxel(x + o.0, y + o.1, z + o.2) else { break }
                corners.append(v)
            }
            guard corners.count == 8 else { continue }
            let inside = corners.map { $0.tsdf < 0 }
            if !inside.contains(true) || !inside.contains(false) { continue }
            var sx: Float = 0, sy: Float = 0, sz: Float = 0, n: Float = 0
            for (a, b) in edges where inside[a] != inside[b] {
                let va = corners[a].tsdf, vb = corners[b].tsdf
                let t = va / (va - vb)
                let pa = cornerOffsets[a], pb = cornerOffsets[b]
                sx += Float(pa.0) + (Float(pb.0) - Float(pa.0)) * t
                sy += Float(pa.1) + (Float(pb.1) - Float(pa.1)) * t
                sz += Float(pa.2) + (Float(pb.2) - Float(pa.2)) * t
                n += 1
            }
            let base = center(x, y, z)
            mesh.vertices.append(Point3(base.x + sx / n * voxelSize, base.y + sy / n * voxelSize, base.z + sz / n * voxelSize))
            var r: Float = 0, g: Float = 0, b: Float = 0
            for c in corners { r += c.r; g += c.g; b += c.b }
            mesh.colors += [UInt8(max(0, min(255, r / 8))), UInt8(max(0, min(255, g / 8))), UInt8(max(0, min(255, b / 8)))]
            cubeVertex[k] = UInt32(mesh.vertices.count - 1)
        }

        // 2. 符号が変わる辺ごとに、その辺を囲む 4 つの立方体の頂点を四角形（三角形 2 つ）でつなぐ
        let axes: [((Int, Int, Int), (Int, Int, Int), (Int, Int, Int))] = [
            ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
            ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
            ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
        ]
        for (k, v0) in voxels where v0.weight >= minWeight {
            let (x, y, z) = Self.unpack(k)
            for (a, b, c) in axes {
                guard let v1 = voxel(x + a.0, y + a.1, z + a.2), (v0.tsdf < 0) != (v1.tsdf < 0) else { continue }
                // 辺を囲む 4 つの立方体（起点）
                let cubes = [
                    Self.key(x - b.0 - c.0, y - b.1 - c.1, z - b.2 - c.2),
                    Self.key(x - c.0, y - c.1, z - c.2),
                    Self.key(x, y, z),
                    Self.key(x - b.0, y - b.1, z - b.2),
                ]
                guard let i0 = cubeVertex[cubes[0]], let i1 = cubeVertex[cubes[1]],
                      let i2 = cubeVertex[cubes[2]], let i3 = cubeVertex[cubes[3]] else { continue }
                // 表（空間側）を向くように並びを決める
                let p0 = mesh.vertices[Int(i0)], p1 = mesh.vertices[Int(i1)], p2 = mesh.vertices[Int(i2)]
                let e1 = (p1.x - p0.x, p1.y - p0.y, p1.z - p0.z), e2 = (p2.x - p0.x, p2.y - p0.y, p2.z - p0.z)
                let nrm = (e1.1 * e2.2 - e1.2 * e2.1, e1.2 * e2.0 - e1.0 * e2.2, e1.0 * e2.1 - e1.1 * e2.0)
                let sign: Float = v0.tsdf > v1.tsdf ? -1 : 1   // 空間側（プラス）の向き
                let dot = (nrm.0 * Float(a.0) + nrm.1 * Float(a.1) + nrm.2 * Float(a.2)) * sign
                if dot >= 0 {
                    mesh.indices += [i0, i1, i2, i0, i2, i3]
                } else {
                    mesh.indices += [i0, i2, i1, i0, i3, i2]
                }
            }
        }
        return mesh
    }
}
