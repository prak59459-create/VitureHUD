import Foundation

public struct GuidanceAnnouncement: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case start, maneuver, eta, reroute, arrival, offRoute }
    public var kind: Kind
    public var text: String
    public var stepIndex: Int?

    public init(kind: Kind, text: String, stepIndex: Int? = nil) {
        self.kind = kind
        self.text = text
        self.stepIndex = stepIndex
    }
}

/// いつ何を読み上げるかを決める（同じ案内を繰り返さない）。
public struct GuidancePlanner: Sendable {
    public var frequency: GuidanceFrequency
    public var announcesETA: Bool
    public let transport: TransportMode
    private var spoken: Set<String> = []
    private var lastETAAnnouncement: Date?
    private var hasAnnouncedArrival = false
    private var hasAnnouncedStart = false

    public init(transport: TransportMode, frequency: GuidanceFrequency = .normal, announcesETA: Bool = true) {
        self.transport = transport
        self.frequency = frequency
        self.announcesETA = announcesETA
    }

    /// 曲がり角の何メートル手前で案内するか（遠い順）。
    public var thresholds: [Double] {
        switch (transport, frequency) {
        case (.walking, .low): return [40]
        case (.walking, .normal): return [120, 40]
        case (.walking, .high): return [200, 100, 40, 15]
        case (.automobile, .low): return [300]
        case (.automobile, .normal): return [1000, 300, 80]
        case (.automobile, .high): return [2000, 1000, 500, 200, 60]
        case (.transit, _): return [100]
        }
    }

    /// ETA を定期的に読み上げる間隔（秒）。
    public var etaInterval: TimeInterval {
        switch frequency {
        case .low: return 15 * 60
        case .normal: return 8 * 60
        case .high: return 4 * 60
        }
    }

    public mutating func startAnnouncement(route: NavRoute, now: Date) -> GuidanceAnnouncement {
        hasAnnouncedStart = true
        lastETAAnnouncement = now
        let eta = now.addingTimeInterval(route.expectedTravelTime)
        return GuidanceAnnouncement(
            kind: .start,
            text: "\(route.destinationName)までの案内を開始します。\(HUDFormat.spokenDistance(route.distance))、約\(HUDFormat.duration(route.expectedTravelTime))、到着予定は\(HUDFormat.spokenClock(eta))です。"
        )
    }

    public mutating func rerouteAnnouncement(route: NavRoute) -> GuidanceAnnouncement {
        spoken.removeAll()
        return GuidanceAnnouncement(kind: .reroute, text: "ルートを再検索しました。残り\(HUDFormat.spokenDistance(route.distance))です。")
    }

    /// 進捗ごとに呼ぶ。読み上げるものがあれば返す（1回の呼び出しで最大1件）。
    public mutating func announcements(for progress: RouteProgress, route: NavRoute, now: Date) -> [GuidanceAnnouncement] {
        if progress.hasArrived {
            guard !hasAnnouncedArrival else { return [] }
            hasAnnouncedArrival = true
            return [GuidanceAnnouncement(kind: .arrival, text: "目的地、\(route.destinationName)に到着しました。案内を終了します。")]
        }
        if progress.isOffRoute {
            let key = "offroute"
            if !spoken.contains(key) {
                spoken.insert(key)
                return [GuidanceAnnouncement(kind: .offRoute, text: "ルートから外れました。ルートを再検索します。")]
            }
            return []
        } else {
            spoken.remove("offroute")
        }

        if let index = progress.nextStepIndex, let distance = progress.distanceToNextManeuver, index < route.steps.count {
            let step = route.steps[index]
            // 一番近い未読の閾値を探す
            let candidates = thresholds.filter { distance <= $0 }
            if let threshold = candidates.min() {
                let key = "\(index)-\(Int(threshold))"
                if !spoken.contains(key) {
                    // より遠い閾値も既読扱いにする（GPS の飛びで二重に読まない）
                    for t in thresholds where t >= threshold { spoken.insert("\(index)-\(Int(t))") }
                    return [GuidanceAnnouncement(kind: .maneuver, text: maneuverText(step: step, distance: distance), stepIndex: index)]
                }
            }
        }

        if announcesETA, let last = lastETAAnnouncement, now.timeIntervalSince(last) >= etaInterval {
            lastETAAnnouncement = now
            let eta = progress.eta(from: now)
            return [GuidanceAnnouncement(kind: .eta, text: "残り\(HUDFormat.spokenDistance(progress.remainingDistance))、到着予定は\(HUDFormat.spokenClock(eta))です。")]
        }
        return []
    }

    public func maneuverText(step: NavStep, distance: Double) -> String {
        let near = distance < 25
        let prefix = near ? "まもなく" : "\(HUDFormat.spokenDistance(distance))先、"
        switch step.maneuver {
        case .arrive:
            return near ? "まもなく目的地です。" : "\(HUDFormat.spokenDistance(distance))先、目的地です。"
        case .unknown, .straight, .depart:
            let body = step.instruction.isEmpty ? "直進です。" : step.instruction
            return prefix + body
        default:
            if let road = step.roadName {
                return prefix + "\(step.maneuver.spokenName)、\(road)です。"
            }
            return prefix + "\(step.maneuver.spokenName)です。"
        }
    }
}
