import Foundation

/// 連続フレームの検出結果に追跡IDを付ける（IoU による単純な対応付け）。
public struct ObjectTracker: Sendable {
    public struct Track: Hashable, Sendable {
        public var id: Int
        public var label: DetectionLabel
        public var history: [(time: Date, box: NormalizedRect)]
        public var lastSeen: Date

        public static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id && lhs.lastSeen == rhs.lastSeen }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    public var iouThreshold: Double = 0.3
    public var maxAge: TimeInterval = 1.0
    public var maxHistory: Int = 12
    public private(set) var tracks: [Int: Track] = [:]
    private var nextID = 1

    public init() {}

    public mutating func update(_ detections: [Detection], at time: Date) -> [Detection] {
        var assigned: [Detection] = []
        var used = Set<Int>()
        // 信頼度の高い順に対応付け
        for det in detections.sorted(by: { $0.confidence > $1.confidence }) {
            var bestID: Int?
            var bestIoU = iouThreshold
            for (id, track) in tracks where !used.contains(id) && track.label == det.label {
                guard let last = track.history.last else { continue }
                let v = last.box.iou(det.box)
                if v > bestIoU { bestIoU = v; bestID = id }
            }
            var d = det
            if let id = bestID, var track = tracks[id] {
                track.history.append((time, det.box))
                if track.history.count > maxHistory { track.history.removeFirst(track.history.count - maxHistory) }
                track.lastSeen = time
                tracks[id] = track
                used.insert(id)
                d.trackID = id
            } else {
                let id = nextID
                nextID += 1
                tracks[id] = Track(id: id, label: det.label, history: [(time, det.box)], lastSeen: time)
                used.insert(id)
                d.trackID = id
            }
            assigned.append(d)
        }
        // 古い追跡を削除
        tracks = tracks.filter { time.timeIntervalSince($0.value.lastSeen) <= maxAge }
        return assigned
    }

    public func track(_ id: Int) -> Track? { tracks[id] }

    public mutating func reset() {
        tracks.removeAll()
    }
}

public enum HazardLevel: Int, Codable, Comparable, CaseIterable, Sendable {
    case none = 0, low, medium, high

    public static func < (lhs: HazardLevel, rhs: HazardLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .none: return "なし"
        case .low: return "注意"
        case .medium: return "警戒"
        case .high: return "危険"
        }
    }
}

public struct HazardAssessment: Hashable, Sendable {
    public var trackID: Int
    public var label: DetectionLabel
    public var level: HazardLevel
    /// 接触までの時間の推定（秒）。枠の拡大率から計算した目安。
    public var timeToContact: Double?
    /// 画面中央（進行方向）への近さ 0〜1
    public var centrality: Double
    public var box: NormalizedRect
    public var reason: String
}

/// 枠の拡大速度から「近づいてくる物体」を推定する（実験機能・安全装置ではない）。
///
/// 物体が近づくと見かけの面積 A は距離 Z の2乗に反比例する（A ∝ 1/Z²）。
/// 接触までの時間 τ = Z / (−dZ/dt) は τ ≈ 2A / (dA/dt) で近似できる。
/// カメラ自体が動く・枠がぶれる・検出漏れがあるため、誤検知・検知漏れを前提とする。
public struct HazardEvaluator: Sendable {
    public struct Configuration: Hashable, Sendable {
        public var highTTC: Double = 1.5
        public var mediumTTC: Double = 3.0
        public var lowTTC: Double = 5.0
        /// これ以上大きく写っている物体は近いとみなす（面積比）
        public var nearAreaRatio: Double = 0.25
        /// 評価に必要な最小履歴数
        public var minHistory: Int = 3
        /// 評価に使う時間幅（秒）
        public var window: TimeInterval = 0.8
        /// 拡大がこれ未満なら接近とみなさない（面積の相対変化/秒）
        public var minGrowthRate: Double = 0.15
        public init() {}
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func assess(tracker: ObjectTracker, now: Date) -> [HazardAssessment] {
        tracker.tracks.values.compactMap { assess(track: $0, now: now) }
            .sorted { $0.level == $1.level ? ($0.timeToContact ?? .infinity) < ($1.timeToContact ?? .infinity) : $0.level > $1.level }
    }

    public func assess(track: ObjectTracker.Track, now: Date) -> HazardAssessment? {
        guard track.label.isMovingHazard, let latest = track.history.last else { return nil }
        guard now.timeIntervalSince(latest.time) < 0.6 else { return nil }
        let recent = track.history.filter { latest.time.timeIntervalSince($0.time) <= configuration.window }
        let box = latest.box
        let center = box.center
        // 進行方向＝画面の中央下寄りを重視
        let dx = abs(center.x - 0.5) * 2
        let dy = abs(center.y - 0.55) * 2
        let centrality = max(0, 1 - sqrt(dx * dx * 0.8 + dy * dy * 0.2))

        var ttc: Double?
        if recent.count >= configuration.minHistory, let first = recent.first {
            let dt = latest.time.timeIntervalSince(first.time)
            let a0 = first.box.area
            let a1 = box.area
            if dt > 0.05, a0 > 0 {
                let rate = (a1 - a0) / dt
                let relative = rate / a1
                if relative > configuration.minGrowthRate {
                    ttc = 2 * a1 / rate
                }
            }
        }

        var level = HazardLevel.none
        var reason = ""
        if let t = ttc {
            if t < configuration.highTTC { level = .high }
            else if t < configuration.mediumTTC { level = .medium }
            else if t < configuration.lowTTC { level = .low }
            reason = "接近中（推定 約\(String(format: "%.1f", t))秒）"
        }
        if box.area >= configuration.nearAreaRatio && centrality > 0.4 {
            level = max(level, .medium)
            if reason.isEmpty { reason = "前方の近くにいます" }
        }
        // 中央から外れているものは1段階下げる
        if centrality < 0.25, level > .none {
            level = HazardLevel(rawValue: level.rawValue - 1) ?? .none
        }
        // 物体の種類で重み付け（歩行者・動物は1段階下げる）
        if track.label.hazardWeight < 0.6, level == .high {
            level = .medium
        }
        guard level > .none else { return nil }
        return HazardAssessment(trackID: track.id, label: track.label, level: level, timeToContact: ttc, centrality: centrality, box: box, reason: reason)
    }
}
