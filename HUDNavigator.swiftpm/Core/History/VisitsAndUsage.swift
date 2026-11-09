import Foundation

/// 一定時間とどまった場所（訪問場所）
public struct VisitRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var arrivedAt: Date
    public var departedAt: Date
    public var coordinate: GeoCoordinate
    public var placeName: String?

    public init(id: UUID = UUID(), arrivedAt: Date, departedAt: Date, coordinate: GeoCoordinate, placeName: String? = nil) {
        self.id = id
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
        self.coordinate = coordinate
        self.placeName = placeName
    }

    public var duration: TimeInterval { departedAt.timeIntervalSince(arrivedAt) }
}

/// 位置の点列から「とどまった場所」を見つける。
/// 半径 radius 以内に minimumStay 以上いたら訪問、そこから離れたら訪問の終わり。
public struct VisitDetector: Sendable {
    public var radius: Double
    public var minimumStay: TimeInterval
    private var anchor: (coordinate: GeoCoordinate, since: Date, count: Int, sumLat: Double, sumLon: Double)?
    private var lastInside: Date?
    public private(set) var isVisiting = false

    public init(radius: Double = 60, minimumStay: TimeInterval = 5 * 60) {
        self.radius = radius
        self.minimumStay = minimumStay
    }

    /// サンプルを渡す。訪問が終わったときに記録を返す。
    public mutating func add(_ sample: LocationSample) -> VisitRecord? {
        guard sample.isAccurateEnough else { return nil }
        guard let a = anchor else {
            anchor = (sample.coordinate, sample.timestamp, 1, sample.coordinate.latitude, sample.coordinate.longitude)
            lastInside = sample.timestamp
            return nil
        }
        let center = GeoCoordinate(latitude: a.sumLat / Double(a.count), longitude: a.sumLon / Double(a.count))
        if Geo.distance(center, sample.coordinate) <= radius {
            anchor = (a.coordinate, a.since, a.count + 1, a.sumLat + sample.coordinate.latitude, a.sumLon + sample.coordinate.longitude)
            lastInside = sample.timestamp
            if sample.timestamp.timeIntervalSince(a.since) >= minimumStay { isVisiting = true }
            return nil
        }
        // 離れた
        var finished: VisitRecord?
        if isVisiting, let end = lastInside {
            finished = VisitRecord(arrivedAt: a.since, departedAt: end, coordinate: center)
        }
        isVisiting = false
        anchor = (sample.coordinate, sample.timestamp, 1, sample.coordinate.latitude, sample.coordinate.longitude)
        lastInside = sample.timestamp
        return finished
    }

    /// 記録を終えるとき（アプリ終了など）に、進行中の訪問を確定する。
    public mutating func flush() -> VisitRecord? {
        defer { anchor = nil; isVisiting = false }
        guard isVisiting, let a = anchor, let end = lastInside else { return nil }
        let center = GeoCoordinate(latitude: a.sumLat / Double(a.count), longitude: a.sumLon / Double(a.count))
        return VisitRecord(arrivedAt: a.since, departedAt: end, coordinate: center)
    }
}

/// 物体検出の記録（危険度つき）
public struct DetectionLogEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var time: Date
    public var label: DetectionLabel
    public var hazard: HazardLevel

    public init(id: UUID = UUID(), time: Date, label: DetectionLabel, hazard: HazardLevel) {
        self.id = id
        self.time = time
        self.label = label
        self.hazard = hazard
    }
}

/// 利用状況（端末内のみ）
public struct UsageStats: Codable, Hashable, Sendable {
    public var launches: Int = 0
    public var hudSeconds: Double = 0
    /// プリセット名 → 表示秒数
    public var presetSeconds: [String: Double] = [:]
    /// コマンド → 回数
    public var commandCounts: [String: Int] = [:]
    /// 音声で実行した回数
    public var voiceCommands: Int = 0
    public var navigationCount: Int = 0
    public var navigationDistance: Double = 0
    public var since: Date = Date()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case launches, hudSeconds, presetSeconds, commandCounts, voiceCommands, navigationCount, navigationDistance, since
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launches = c.value(.launches, default: 0)
        hudSeconds = c.value(.hudSeconds, default: 0)
        presetSeconds = c.value(.presetSeconds, default: [:])
        commandCounts = c.value(.commandCounts, default: [:])
        voiceCommands = c.value(.voiceCommands, default: 0)
        navigationCount = c.value(.navigationCount, default: 0)
        navigationDistance = c.value(.navigationDistance, default: 0)
        since = c.value(.since, default: Date())
    }

    public mutating func recordHUD(seconds: Double, preset: String) {
        guard seconds > 0, seconds < 3600 else { return }
        hudSeconds += seconds
        presetSeconds[preset, default: 0] += seconds
    }

    public mutating func recordCommand(_ summary: String, viaVoice: Bool) {
        commandCounts[summary, default: 0] += 1
        if viaVoice { voiceCommands += 1 }
    }

    public mutating func recordNavigation(distance: Double) {
        navigationCount += 1
        navigationDistance += distance
    }

    public func topPresets(_ n: Int = 3) -> [(name: String, seconds: Double)] {
        presetSeconds.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
    }

    public func topCommands(_ n: Int = 5) -> [(name: String, count: Int)] {
        commandCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
    }

    /// AI に渡す要約（位置は含めない）
    public var summaryText: String {
        var lines = [
            "起動回数: \(launches)回",
            "HUD表示時間: \(HUDFormat.duration(hudSeconds))",
            "ナビ: \(navigationCount)回・\(HUDFormat.distance(navigationDistance))",
            "音声コマンド: \(voiceCommands)回",
        ]
        if !presetSeconds.isEmpty {
            lines.append("よく使うプリセット: " + topPresets().map { "\($0.name)(\(HUDFormat.duration($0.seconds)))" }.joined(separator: "、"))
        }
        if !commandCounts.isEmpty {
            lines.append("よく使う操作: " + topCommands().map { "\($0.name)×\($0.count)" }.joined(separator: "、"))
        }
        return lines.joined(separator: "\n")
    }
}
