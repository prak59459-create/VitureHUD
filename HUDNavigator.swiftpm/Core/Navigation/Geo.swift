import Foundation

/// 緯度経度（CoreLocation 非依存）。
public struct GeoCoordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && !(latitude == 0 && longitude == 0)
    }

    /// 書き出し用に丸める（小数3桁 ≒ 約100m）。
    public func rounded(decimals: Int = 3) -> GeoCoordinate {
        let f = pow(10.0, Double(decimals))
        return GeoCoordinate(latitude: (latitude * f).rounded() / f, longitude: (longitude * f).rounded() / f)
    }
}

public enum Geo {
    public static let earthRadius = 6_371_000.0

    @inline(__always) static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    @inline(__always) static func deg(_ rad: Double) -> Double { rad * 180 / .pi }

    /// 2点間の距離（メートル、ハーサイン）。
    public static func distance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let la1 = rad(a.latitude)
        let la2 = rad(b.latitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// a から b への方位（度、北=0、時計回り）。
    public static func bearing(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let la1 = rad(a.latitude)
        let la2 = rad(b.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let y = sin(dLon) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        return normalizeDegrees(deg(atan2(y, x)))
    }

    /// 起点から方位・距離だけ進んだ地点。
    public static func destination(from start: GeoCoordinate, bearing: Double, distance: Double) -> GeoCoordinate {
        let delta = distance / earthRadius
        let theta = rad(bearing)
        let la1 = rad(start.latitude)
        let lo1 = rad(start.longitude)
        let la2 = asin(sin(la1) * cos(delta) + cos(la1) * sin(delta) * cos(theta))
        let lo2 = lo1 + atan2(sin(theta) * sin(delta) * cos(la1), cos(delta) - sin(la1) * sin(la2))
        return GeoCoordinate(latitude: deg(la2), longitude: deg(lo2))
    }

    public static func normalizeDegrees(_ value: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    /// 2つの方位の差（-180〜180、正は右回り）。
    public static func angleDifference(from a: Double, to b: Double) -> Double {
        var d = normalizeDegrees(b) - normalizeDegrees(a)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// 線分 a-b 上の、点 p に最も近い位置。
    /// 返り値: (線分上の比率 0〜1, 最短距離m)。短い距離なので局所平面近似で計算する。
    public static func project(_ p: GeoCoordinate, onSegment a: GeoCoordinate, _ b: GeoCoordinate) -> (fraction: Double, distance: Double) {
        let refLat = rad((a.latitude + b.latitude) / 2)
        func xy(_ c: GeoCoordinate) -> (Double, Double) {
            (rad(c.longitude) * cos(refLat) * earthRadius, rad(c.latitude) * earthRadius)
        }
        let (ax, ay) = xy(a)
        let (bx, by) = xy(b)
        let (px, py) = xy(p)
        let dx = bx - ax
        let dy = by - ay
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / len2 : 0
        t = t.clamped(to: 0...1)
        let cx = ax + t * dx
        let cy = ay + t * dy
        let dist = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
        return (t, dist)
    }

    public static func interpolate(_ a: GeoCoordinate, _ b: GeoCoordinate, fraction t: Double) -> GeoCoordinate {
        GeoCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    public static func pathLength(_ points: [GeoCoordinate]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count { total += distance(points[i - 1], points[i]) }
        return total
    }

    /// 8方位の日本語名。
    public static func cardinalName(_ bearing: Double) -> String {
        let names = ["北", "北東", "東", "南東", "南", "南西", "西", "北西"]
        let index = Int((normalizeDegrees(bearing) + 22.5) / 45) % 8
        return names[index]
    }

    /// 点列を間引く（距離が minSpacing 未満の点を除く）。履歴保存用。
    public static func downsample(_ points: [GeoCoordinate], minSpacing: Double) -> [GeoCoordinate] {
        guard var last = points.first else { return [] }
        var result = [last]
        for p in points.dropFirst() where distance(last, p) >= minSpacing {
            result.append(p)
            last = p
        }
        if let final = points.last, result.last != final { result.append(final) }
        return result
    }
}

/// 位置情報の1サンプル。
public struct LocationSample: Codable, Hashable, Sendable {
    public var coordinate: GeoCoordinate
    public var timestamp: Date
    /// m/s。負の値は無効。
    public var speed: Double
    /// 度。負の値は無効。
    public var course: Double
    public var horizontalAccuracy: Double
    public var altitude: Double?

    public init(coordinate: GeoCoordinate, timestamp: Date, speed: Double = -1, course: Double = -1, horizontalAccuracy: Double = 10, altitude: Double? = nil) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
    }

    public var hasValidSpeed: Bool { speed >= 0 }
    public var hasValidCourse: Bool { course >= 0 }
    public var isAccurateEnough: Bool { horizontalAccuracy >= 0 && horizontalAccuracy <= 65 }
}
