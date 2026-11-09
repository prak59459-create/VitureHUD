import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// GPX（trkpt / rtept / wpt）の読み込みと書き出し。
/// 位置情報のシミュレーション再生と、移動記録のエクスポートに使う。
public enum GPX {
    public struct Point: Hashable, Sendable {
        public var coordinate: GeoCoordinate
        public var time: Date?
        public var elevation: Double?
    }

    public static func parse(_ data: Data) -> [Point] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    public static func parse(_ text: String) -> [Point] {
        parse(Data(text.utf8))
    }

    public static func export(name: String, points: [LocationSample]) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"HUD Navigator\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
            "<trk><name>\(escape(name))</name><trkseg>",
        ]
        for p in points {
            var line = "<trkpt lat=\"\(p.coordinate.latitude)\" lon=\"\(p.coordinate.longitude)\">"
            if let alt = p.altitude { line += "<ele>\(alt)</ele>" }
            line += "<time>\(iso.string(from: p.timestamp))</time></trkpt>"
            lines.append(line)
        }
        lines.append("</trkseg></trk></gpx>")
        return lines.joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var points: [Point] = []
        private var current: Point?
        private var text = ""
        private let iso = ISO8601DateFormatter()
        private let isoFrac: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            text = ""
            let name = elementName.lowercased()
            if name == "trkpt" || name == "rtept" || name == "wpt" {
                if let lat = attributeDict["lat"].flatMap(Double.init), let lon = attributeDict["lon"].flatMap(Double.init) {
                    current = Point(coordinate: GeoCoordinate(latitude: lat, longitude: lon), time: nil, elevation: nil)
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "time":
                current?.time = iso.date(from: value) ?? isoFrac.date(from: value)
            case "ele":
                current?.elevation = Double(value)
            case "trkpt", "rtept", "wpt":
                if let p = current { points.append(p) }
                current = nil
            default:
                break
            }
            text = ""
        }
    }
}

/// GPX の点列を、一定速度で歩いているかのような LocationSample 列に変換する。
public struct SimulatedTrack: Sendable {
    public let points: [GeoCoordinate]
    public let speed: Double
    private let cumulative: [Double]

    public init(points: [GeoCoordinate], speed: Double = 1.4) {
        self.points = points
        self.speed = max(0.1, speed)
        var cum: [Double] = [0]
        if points.count > 1 {
            for i in 1..<points.count { cum.append(cum[i - 1] + Geo.distance(points[i - 1], points[i])) }
        }
        cumulative = cum
    }

    public var totalDistance: Double { cumulative.last ?? 0 }
    public var duration: TimeInterval { totalDistance / speed }

    /// 開始からの経過秒における位置。終点を過ぎたら nil。
    public func sample(at elapsed: TimeInterval, startDate: Date) -> LocationSample? {
        guard points.count > 1 else {
            return points.first.map { LocationSample(coordinate: $0, timestamp: startDate.addingTimeInterval(elapsed), speed: 0) }
        }
        let d = elapsed * speed
        guard d <= totalDistance else { return nil }
        var i = 0
        while i < cumulative.count - 2 && cumulative[i + 1] < d { i += 1 }
        let segLen = cumulative[i + 1] - cumulative[i]
        let t = segLen > 0 ? (d - cumulative[i]) / segLen : 0
        let coord = Geo.interpolate(points[i], points[i + 1], fraction: t)
        let course = Geo.bearing(points[i], points[i + 1])
        return LocationSample(coordinate: coord, timestamp: startDate.addingTimeInterval(elapsed), speed: speed, course: course, horizontalAccuracy: 5)
    }
}
