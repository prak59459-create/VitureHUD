import Foundation

/// 画面サイズ（ピクセル／ポイント）。CoreGraphics に依存しないための独自型。
public struct HUDSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let fullHD = HUDSize(width: 1920, height: 1080)
    public static let zero = HUDSize(width: 0, height: 0)

    public var aspectRatio: Double { height > 0 ? width / height : 1 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

public struct HUDPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = HUDPoint(x: 0, y: 0)
}

/// ピクセル座標の矩形。
public struct PixelRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// 0.0〜1.0 の正規化座標の矩形（左上原点）。
/// HUDパネルの位置は全てこの型で保存し、描画時にキャンバスサイズを掛ける。
/// → iPad / iPhone / 1080p 外部画面のどれでも同じ相対位置に表示される。
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }
    public var center: HUDPoint { HUDPoint(x: midX, y: midY) }

    /// 0〜1 の範囲に収め、最小サイズを保証する。
    public func clamped(minSize: Double = 0.02) -> NormalizedRect {
        let w = width.clamped(to: minSize...1)
        let h = height.clamped(to: minSize...1)
        let nx = x.clamped(to: 0...(1 - w))
        let ny = y.clamped(to: 0...(1 - h))
        return NormalizedRect(x: nx, y: ny, width: w, height: h)
    }

    public func offsetBy(dx: Double, dy: Double) -> NormalizedRect {
        NormalizedRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    public func insetBy(_ amount: Double) -> NormalizedRect {
        NormalizedRect(x: x + amount, y: y + amount, width: max(0, width - amount * 2), height: max(0, height - amount * 2))
    }

    public func intersects(_ other: NormalizedRect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    public func intersection(_ other: NormalizedRect) -> NormalizedRect? {
        let ix = max(minX, other.minX)
        let iy = max(minY, other.minY)
        let ax = min(maxX, other.maxX)
        let ay = min(maxY, other.maxY)
        guard ax > ix, ay > iy else { return nil }
        return NormalizedRect(x: ix, y: iy, width: ax - ix, height: ay - iy)
    }

    /// Intersection over Union（物体追跡で使う）。
    public func iou(_ other: NormalizedRect) -> Double {
        guard let inter = intersection(other) else { return 0 }
        let union = area + other.area - inter.area
        return union > 0 ? inter.area / union : 0
    }

    public func contains(_ point: HUDPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func denormalized(in size: HUDSize) -> PixelRect {
        PixelRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    public static func fromPixels(_ rect: PixelRect, in size: HUDSize) -> NormalizedRect {
        guard !size.isEmpty else { return NormalizedRect(x: 0, y: 0, width: 0, height: 0) }
        return NormalizedRect(
            x: rect.x / size.width,
            y: rect.y / size.height,
            width: rect.width / size.width,
            height: rect.height / size.height
        )
    }
}
