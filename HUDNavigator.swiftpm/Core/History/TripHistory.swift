import Foundation

/// 1回の移動の記録。位置の点列は設定で保存する場合のみ。
public struct TripRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    /// m
    public var distance: Double
    /// m/s
    public var averageSpeed: Double
    public var maxSpeed: Double
    public var destinationName: String?
    public var transport: TransportMode?
    public var points: [GeoCoordinate]
    public var detectionCount: Int

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, distance: Double, averageSpeed: Double, maxSpeed: Double, destinationName: String? = nil, transport: TransportMode? = nil, points: [GeoCoordinate] = [], detectionCount: Int = 0) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distance = distance
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.destinationName = destinationName
        self.transport = transport
        self.points = points
        self.detectionCount = detectionCount
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

/// 位置サンプルを受け取り、移動距離・速度を集計する。
public struct TripRecorder: Sendable {
    public private(set) var startedAt: Date?
    public private(set) var distance: Double = 0
    public private(set) var maxSpeed: Double = 0
    public private(set) var points: [GeoCoordinate] = []
    public private(set) var detectionCount = 0
    private var last: LocationSample?
    private var movingTime: TimeInterval = 0
    public var keepsPoints: Bool

    public init(keepsPoints: Bool) {
        self.keepsPoints = keepsPoints
    }

    public var isRecording: Bool { startedAt != nil }

    public mutating func start(at date: Date) {
        startedAt = date
        distance = 0
        maxSpeed = 0
        points = []
        detectionCount = 0
        last = nil
        movingTime = 0
    }

    public mutating func add(_ sample: LocationSample) {
        guard isRecording, sample.isAccurateEnough else { return }
        if let prev = last {
            let d = Geo.distance(prev.coordinate, sample.coordinate)
            let dt = sample.timestamp.timeIntervalSince(prev.timestamp)
            guard dt > 0 else { return }
            let impliedSpeed = d / dt
            // GPS の飛び（時速150km以上相当）は捨てる
            guard impliedSpeed < 42 else { return }
            // 静止中のふらつき（精度より小さい移動）は数えない
            if d >= min(sample.horizontalAccuracy, 15) * 0.5 {
                distance += d
                movingTime += dt
                if keepsPoints { points.append(sample.coordinate) }
                last = sample
            }
            if sample.hasValidSpeed { maxSpeed = max(maxSpeed, sample.speed) }
        } else {
            last = sample
            if keepsPoints { points.append(sample.coordinate) }
        }
    }

    public mutating func addDetections(_ count: Int) {
        detectionCount += count
    }

    public mutating func finish(at date: Date, destinationName: String?, transport: TransportMode?) -> TripRecord? {
        guard let start = startedAt else { return nil }
        defer { startedAt = nil; last = nil }
        let duration = date.timeIntervalSince(start)
        guard duration > 5 || distance > 10 else { return nil }
        let avg = movingTime > 0 ? distance / movingTime : 0
        return TripRecord(
            startedAt: start, endedAt: date, distance: distance, averageSpeed: avg, maxSpeed: maxSpeed,
            destinationName: destinationName, transport: transport,
            points: keepsPoints ? Geo.downsample(points, minSpacing: 10) : [],
            detectionCount: detectionCount
        )
    }
}

public enum StatsPeriod: String, CaseIterable, Sendable {
    case day, week, month

    public var displayName: String {
        switch self {
        case .day: return "日別"
        case .week: return "週別"
        case .month: return "月別"
        }
    }
}

public struct StatsBucket: Hashable, Identifiable, Sendable {
    public var id: Date { start }
    public var start: Date
    public var tripCount: Int
    public var distance: Double
    public var duration: TimeInterval
    public var averageSpeed: Double
    public var maxSpeed: Double
}

public enum HistoryStats {
    public static func buckets(_ trips: [TripRecord], period: StatsPeriod, calendar: Calendar = .current) -> [StatsBucket] {
        var groups: [Date: [TripRecord]] = [:]
        for trip in trips {
            let start: Date
            switch period {
            case .day: start = calendar.startOfDay(for: trip.startedAt)
            case .week: start = calendar.dateInterval(of: .weekOfYear, for: trip.startedAt)?.start ?? calendar.startOfDay(for: trip.startedAt)
            case .month: start = calendar.dateInterval(of: .month, for: trip.startedAt)?.start ?? calendar.startOfDay(for: trip.startedAt)
            }
            groups[start, default: []].append(trip)
        }
        return groups.map { start, list in
            let distance = list.reduce(0) { $0 + $1.distance }
            let duration = list.reduce(0) { $0 + $1.duration }
            return StatsBucket(
                start: start,
                tripCount: list.count,
                distance: distance,
                duration: duration,
                averageSpeed: duration > 0 ? distance / duration : 0,
                maxSpeed: list.map(\.maxSpeed).max() ?? 0
            )
        }.sorted { $0.start < $1.start }
    }

    /// 保存期間を過ぎた記録を除く。
    public static func pruned(_ trips: [TripRecord], retentionDays: Int, now: Date) -> [TripRecord] {
        guard retentionDays > 0 else { return trips }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return trips.filter { $0.startedAt >= cutoff }
    }

    /// AI に渡すための要約（位置は含めない）。
    public static func summaryText(_ trips: [TripRecord], calendar: Calendar = .current) -> String {
        guard !trips.isEmpty else { return "移動記録はありません。" }
        let total = trips.reduce(0) { $0 + $1.distance }
        let time = trips.reduce(0) { $0 + $1.duration }
        let weekly = buckets(trips, period: .week, calendar: calendar)
        var lines = [
            "記録数: \(trips.count)件",
            "合計距離: \(HUDFormat.distance(total))",
            "合計時間: \(HUDFormat.duration(time))",
            "平均速度: 時速\(HUDFormat.speed(time > 0 ? total / time : 0, unit: .kilometersPerHour))km",
        ]
        for b in weekly.suffix(6) {
            lines.append("週(\(HUDFormat.date(b.start, calendar: calendar))〜): \(b.tripCount)件 \(HUDFormat.distance(b.distance))")
        }
        return lines.joined(separator: "\n")
    }
}
