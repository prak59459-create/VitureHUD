import Foundation

// 奥行き（距離）。LiDAR・2 つのカメラ・AI の推定のどれからでも、同じ「距離の格子」にまとめて使う。

/// 距離の取り方
public enum DepthSourceKind: String, Codable, CaseIterable, Sendable {
    /// 使える中でいちばん正確なもの
    case auto
    /// LiDAR（iPhone Pro・iPad Pro）
    case lidar
    /// 2 つの背面カメラの視差（iPhone 15 など）
    case dualCamera
    /// AI（1 台のカメラの画像から推定し、地面の見え方で m に直す）
    case aiMonocular

    public var displayName: String {
        switch self {
        case .auto: return "自動（使える中で最も正確）"
        case .lidar: return "LiDAR"
        case .dualCamera: return "2 つのカメラ（視差）"
        case .aiMonocular: return "AI 推定（カメラ 1 台）"
        }
    }

    public var shortName: String {
        switch self {
        case .auto: return "自動"
        case .lidar: return "LiDAR"
        case .dualCamera: return "視差"
        case .aiMonocular: return "AI"
        }
    }
}

public struct DepthSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = false
    public var source: DepthSourceKind = .auto
    /// AI 推定の回数（1 秒あたり）
    public var aiFPS: Double = 4
    /// 端末を持つ高さ（地面から m）。AI の推定を m に直すのに使う
    public var cameraHeight: Double = 1.3
    public var showsGrid: Bool = true
    public var showsHeatmap: Bool = false
    public var showsReticle: Bool = true
    public var showsObjectDistance: Bool = true
    /// 近くの物を知らせる
    public var obstacleAlerts: Bool = true
    /// 近い物を音で知らせる（駐車センサーのように、近いほど速く鳴る・左右の位置も音で）
    public var proximityBeeps: Bool = false
    /// この距離（m）より近いと知らせる
    public var obstacleDistance: Double = 1.5
    /// これより遠い値は使わない（m）
    public var maxRange: Double = 20
    public init() {}
}

/// 画面を格子に分けた距離（m）。値のないマスは nan。
public struct DepthGrid: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var values: [Float]
    /// m で表しているか（false は AI の相対値で、大きいほど近い 0〜1）
    public var isMetric: Bool

    public init(columns: Int, rows: Int, values: [Float], isMetric: Bool) {
        self.columns = columns
        self.rows = rows
        self.values = values
        self.isMetric = isMetric
    }

    public func value(column: Int, row: Int) -> Float? {
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        let v = values[row * columns + column]
        return v.isFinite ? v : nil
    }

    /// 正規化座標（左上 0,0）の値
    public func value(atX x: Double, y: Double) -> Float? {
        value(column: min(columns - 1, max(0, Int(x * Double(columns)))), row: min(rows - 1, max(0, Int(y * Double(rows)))))
    }

    func cells(in rect: NormalizedRect) -> [(column: Int, row: Int, value: Float)] {
        let c0 = max(0, Int((rect.x * Double(columns)).rounded(.down)))
        let c1 = min(columns - 1, Int(((rect.x + rect.width) * Double(columns)).rounded(.up)) - 1)
        let r0 = max(0, Int((rect.y * Double(rows)).rounded(.down)))
        let r1 = min(rows - 1, Int(((rect.y + rect.height) * Double(rows)).rounded(.up)) - 1)
        guard c0 <= c1, r0 <= r1 else { return [] }
        var out: [(column: Int, row: Int, value: Float)] = []
        for r in r0...r1 {
            for c in c0...c1 {
                if let v = value(column: c, row: r) { out.append((column: c, row: r, value: v)) }
            }
        }
        return out
    }

    /// 枠の中の距離（中央値）
    public func median(in rect: NormalizedRect) -> Float? {
        let vs = cells(in: rect).map(\.value).sorted()
        guard !vs.isEmpty else { return nil }
        return vs[vs.count / 2]
    }
}

public enum DepthMath {
    /// 細かい距離の配列（width×height、左上から）を格子にまとめる。各マスは中央値。
    public static func grid(from samples: [Float], width: Int, height: Int, columns: Int, rows: Int, isMetric: Bool) -> DepthGrid {
        var values = [Float](repeating: .nan, count: columns * rows)
        guard width > 0, height > 0, samples.count >= width * height else {
            return DepthGrid(columns: columns, rows: rows, values: values, isMetric: isMetric)
        }
        for r in 0..<rows {
            let y0 = r * height / rows, y1 = max(y0 + 1, (r + 1) * height / rows)
            for c in 0..<columns {
                let x0 = c * width / columns, x1 = max(x0 + 1, (c + 1) * width / columns)
                var cell: [Float] = []
                cell.reserveCapacity((y1 - y0) * (x1 - x0))
                for y in y0..<min(y1, height) {
                    for x in x0..<min(x1, width) {
                        let v = samples[y * width + x]
                        if v.isFinite && v > 0 { cell.append(v) }
                    }
                }
                if !cell.isEmpty {
                    cell.sort()
                    values[r * columns + c] = cell[cell.count / 2]
                }
            }
        }
        return DepthGrid(columns: columns, rows: rows, values: values, isMetric: isMetric)
    }

    /// 1/Z = a × d + b を最小二乗で求める（d は AI の相対値：大きいほど近い）。外れ値を除いてもう一度求める。
    public static func fitInverse(_ pairs: [(d: Double, z: Double)]) -> (a: Double, b: Double)? {
        func ls(_ p: [(d: Double, z: Double)]) -> (a: Double, b: Double)? {
            guard p.count >= 4 else { return nil }
            let n = Double(p.count)
            var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
            for (d, z) in p {
                let y = 1 / z
                sx += d; sy += y; sxx += d * d; sxy += d * y
            }
            let den = n * sxx - sx * sx
            guard abs(den) > 1e-12 else { return nil }
            let a = (n * sxy - sx * sy) / den
            let b = (sy - a * sx) / n
            return a > 0 ? (a, b) : nil
        }
        let valid = pairs.filter { $0.z > 0.05 && $0.z.isFinite && $0.d.isFinite }
        guard let first = ls(valid) else { return nil }
        let residuals = valid.map { abs(1 / $0.z - (first.a * $0.d + first.b)) }
        let cutoff = residuals.sorted()[Int(Double(residuals.count - 1) * 0.7)]
        let inliers = zip(valid, residuals).filter { $0.1 <= cutoff }.map(\.0)
        return ls(inliers) ?? first
    }

    public static func metric(_ d: Double, fit: (a: Double, b: Double), maxRange: Double) -> Double? {
        let inv = fit.a * d + fit.b
        guard inv > 1 / maxRange else { return nil }
        return 1 / inv
    }

    /// 半精度（16 ビット浮動小数点）→ Float
    public static func halfToFloat(_ h: UInt16) -> Float {
        let sign = UInt32(h & 0x8000) << 16
        let exp = Int((h >> 10) & 0x1F)
        let frac = UInt32(h & 0x3FF)
        if exp == 0 {
            if frac == 0 { return Float(bitPattern: sign) }
            // 非正規化数
            let v = Float(frac) / 1024 * pow(2, -14)
            return sign != 0 ? -v : v
        }
        if exp == 31 { return Float(bitPattern: sign | 0x7F80_0000 | (frac << 13)) }
        return Float(bitPattern: sign | UInt32(exp - 15 + 127) << 23 | (frac << 13))
    }
}

/// 地面の見え方から距離を求める（端末の傾き・持つ高さ・カメラの縦の画角から）
public enum GroundGeometry {
    /// 画像の行 y（0＝上、1＝下）が水平より何度下を見ているか
    public static func angleBelowHorizon(row y: Double, cameraPitchDown: Double, verticalFOV: Double) -> Double {
        let t = (y - 0.5) * 2 * tan(verticalFOV * .pi / 360)
        return cameraPitchDown + atan(t) * 180 / .pi
    }

    /// 地面までの直線距離（m）。地平線より上（または 3 度未満）は nil
    public static func groundRange(row y: Double, cameraPitchDown: Double, verticalFOV: Double, height: Double) -> Double? {
        let a = angleBelowHorizon(row: y, cameraPitchDown: cameraPitchDown, verticalFOV: verticalFOV)
        guard a >= 3 else { return nil }
        return height / sin(a * .pi / 180)
    }

    /// AI の相対値を m に直す係数を、画像の下の方（地面）から求める
    public static func fitAIToGround(_ grid: DepthGrid, cameraPitchDown: Double, verticalFOV: Double, height: Double) -> (a: Double, b: Double)? {
        var pairs: [(d: Double, z: Double)] = []
        for r in 0..<grid.rows {
            let y = (Double(r) + 0.5) / Double(grid.rows)
            guard y >= 0.55, let range = groundRange(row: y, cameraPitchDown: cameraPitchDown, verticalFOV: verticalFOV, height: height), range < 15 else { continue }
            let c0 = grid.columns / 4, c1 = grid.columns - grid.columns / 4
            for c in c0..<max(c0 + 1, c1) {
                if let v = grid.value(column: c, row: r) { pairs.append((Double(v), range)) }
            }
        }
        return DepthMath.fitInverse(pairs)
    }
}

/// 近くの物（障害物）
public struct Obstacle: Equatable, Sendable {
    public var distance: Double
    /// 横の位置（0＝左端、1＝右端）
    public var x: Double
    public var level: HazardLevel

    public var direction: String {
        x < 0.38 ? "左前" : x > 0.62 ? "右前" : "正面"
    }
}

/// 進む方向（画面の中央）にある近い物を見つける。地面は除く。2 回続けて近いときだけ知らせる。
public struct ObstacleDetector: Sendable {
    public var threshold: Double
    public var corridor = NormalizedRect(x: 0.25, y: 0.15, width: 0.5, height: 0.7)
    private var streak = 0

    public init(threshold: Double = 1.5) {
        self.threshold = threshold
    }

    public mutating func update(_ grid: DepthGrid, cameraPitchDown: Double?, verticalFOV: Double, height: Double) -> Obstacle? {
        guard grid.isMetric else { streak = 0; return nil }
        var best: (d: Double, x: Double)?
        for cell in grid.cells(in: corridor) {
            let d = Double(cell.value)
            guard d > 0.15 else { continue }
            let y = (Double(cell.row) + 0.5) / Double(grid.rows)
            // 地面とほぼ同じ距離なら障害物ではない
            if let pitch = cameraPitchDown,
               let ground = GroundGeometry.groundRange(row: y, cameraPitchDown: pitch, verticalFOV: verticalFOV, height: height),
               abs(d - ground) / ground < 0.2 {
                continue
            }
            let x = (Double(cell.column) + 0.5) / Double(grid.columns)
            if best == nil || d < best!.d { best = (d, x) }
        }
        guard let b = best, b.d < threshold else { streak = 0; return nil }
        streak += 1
        guard streak >= 2 else { return nil }
        return Obstacle(distance: b.d, x: b.x, level: b.d < threshold * 0.6 ? .high : .medium)
    }
}

// MARK: - 3D（点群）

public struct Point3: Hashable, Sendable {
    public var x: Float, y: Float, z: Float
    public init(_ x: Float, _ y: Float, _ z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    public func distance(to p: Point3) -> Float {
        ((x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) + (z - p.z) * (z - p.z)).squareRoot()
    }
}

public struct ColoredPoint: Hashable, Sendable {
    public var position: Point3
    public var r: UInt8, g: UInt8, b: UInt8
    public init(_ position: Point3, r: UInt8, g: UInt8, b: UInt8) {
        self.position = position
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum Projection {
    /// 画像の点（ピクセル u, v）と奥行き d（m）→ カメラ座標（ARKit と同じ：x 右・y 上・-z 前）
    public static func backProject(u: Double, v: Double, depth d: Double, fx: Double, fy: Double, cx: Double, cy: Double) -> Point3 {
        Point3(Float((u - cx) / fx * d), Float(-(v - cy) / fy * d), Float(-d))
    }

    /// 4×4 行列（列優先・16 要素）をかける
    public static func transform(_ p: Point3, by m: [Float]) -> Point3 {
        guard m.count == 16 else { return p }
        return Point3(
            m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
            m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
            m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14]
        )
    }
}

/// 点群を小さな立方体（ボクセル）ごとに 1 点にまとめて増えすぎないようにする
public struct VoxelPointCloud: Sendable {
    public var voxelSize: Float
    public var maxPoints: Int
    private var map: [Int64: ColoredPoint] = [:]

    public init(voxelSize: Float = 0.05, maxPoints: Int = 300_000) {
        self.voxelSize = voxelSize
        self.maxPoints = maxPoints
    }

    public var count: Int { map.count }
    public var points: [ColoredPoint] { Array(map.values) }

    static func key(_ p: Point3, size: Float) -> Int64 {
        let x = Int64((p.x / size).rounded(.down)) & 0x1FFFFF
        let y = Int64((p.y / size).rounded(.down)) & 0x1FFFFF
        let z = Int64((p.z / size).rounded(.down)) & 0x1FFFFF
        return (x << 42) | (y << 21) | z
    }

    /// 追加できたら true（同じボクセルは新しい点で置き換え）
    @discardableResult
    public mutating func add(_ p: ColoredPoint) -> Bool {
        guard p.position.x.isFinite, p.position.y.isFinite, p.position.z.isFinite else { return false }
        let k = Self.key(p.position, size: voxelSize)
        if map[k] == nil && map.count >= maxPoints { return false }
        map[k] = p
        return true
    }

    public mutating func removeAll() { map.removeAll() }

    /// PLY（ASCII・色付き）。多くの 3D ソフトで開ける。
    public func ply() -> String {
        var s = "ply\nformat ascii 1.0\ncomment HUD Navigator 3D scan (meters, Y up)\nelement vertex \(map.count)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n"
        s.reserveCapacity(s.count + map.count * 40)
        for p in map.values {
            s += String(format: "%.4f %.4f %.4f %d %d %d\n", p.position.x, p.position.y, p.position.z, Int(p.r), Int(p.g), Int(p.b))
        }
        return s
    }
}
