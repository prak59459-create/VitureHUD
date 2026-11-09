import Foundation

public enum AlertPriority: Int, Codable, Comparable, Sendable {
    case info = 0, normal, important, critical

    public static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct HUDAlert: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var category: AlertCategory
    public var title: String
    public var message: String
    public var priority: AlertPriority
    public var createdAt: Date
    /// 表示時間（秒）
    public var duration: TimeInterval
    /// 同じ種類の通知をまとめるためのキー
    public var dedupeKey: String
    /// 読み上げ文（nil なら title + message）
    public var spokenText: String?

    public init(
        id: UUID = UUID(),
        category: AlertCategory,
        title: String,
        message: String = "",
        priority: AlertPriority = .normal,
        createdAt: Date = Date(),
        duration: TimeInterval = 5,
        dedupeKey: String? = nil,
        spokenText: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.message = message
        self.priority = priority
        self.createdAt = createdAt
        self.duration = duration
        self.dedupeKey = dedupeKey ?? "\(category.rawValue):\(title)"
        self.spokenText = spokenText
    }

    public var textToSpeak: String { spokenText ?? (message.isEmpty ? title : "\(title)。\(message)") }

    public func isExpired(at now: Date) -> Bool { now.timeIntervalSince(createdAt) >= duration }
}

public struct AlertDecision: Hashable, Sendable {
    public var showBanner: Bool
    public var speak: Bool
    public var playSound: Bool

    public var isSuppressed: Bool { !showBanner && !speak && !playSound }
}

/// 通知を出すかどうか・どう出すかを決める。
/// - 種類ごとの設定（表示・読み上げ・警告音）
/// - 同じ通知は一定時間繰り返さない（危険警告は短い間隔）
/// - 移動中は重要度の低い通知を抑える
public struct AlertPolicy: Sendable {
    public var settings: NotificationSettings
    private var lastFired: [String: Date] = [:]

    public init(settings: NotificationSettings) {
        self.settings = settings
    }

    public mutating func decide(_ alert: HUDAlert, now: Date, isMoving: Bool) -> AlertDecision {
        let channel = settings.channel(for: alert.category)
        let cooldown: TimeInterval = alert.category == .hazard ? 3 : settings.cooldownSeconds
        if let last = lastFired[alert.dedupeKey], now.timeIntervalSince(last) < cooldown {
            return AlertDecision(showBanner: false, speak: false, playSound: false)
        }
        var decision = AlertDecision(showBanner: channel.showsBanner, speak: channel.speaks, playSound: channel.playsSound)
        if isMoving && alert.priority < .important {
            // 移動中は情報レベルのバナーを出さない（視界を優先）
            if alert.priority == .info { decision.showBanner = false }
            decision.playSound = false
        }
        if alert.priority == .critical {
            decision.showBanner = decision.showBanner || channel.speaks || channel.playsSound
        }
        if !decision.isSuppressed { lastFired[alert.dedupeKey] = now }
        return decision
    }

    /// 表示中の通知の並び（重要度の高い順、同じなら新しい順）。最大件数で切る。
    public static func displayQueue(_ alerts: [HUDAlert], now: Date, limit: Int = 3) -> [HUDAlert] {
        Array(
            alerts.filter { !$0.isExpired(at: now) }
                .sorted { $0.priority == $1.priority ? $0.createdAt > $1.createdAt : $0.priority > $1.priority }
                .prefix(limit)
        )
    }
}
