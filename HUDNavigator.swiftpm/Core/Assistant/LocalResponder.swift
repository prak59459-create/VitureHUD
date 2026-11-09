import Foundation

/// 端末内で答えられる状態の問い合わせへの返答を作る。
public struct AssistantContext: Sendable {
    public var now: Date
    public var batteryLevel: Double?
    public var isCharging: Bool
    public var speedMetersPerSecond: Double?
    public var speedUnit: SpeedUnit
    public var navigationDestination: String?
    public var remainingDistance: Double?
    public var remainingTime: Double?
    public var weatherSummary: String?
    public var placeName: String?
    public var headingDegrees: Double?
    public var isOnline: Bool

    public init(
        now: Date = Date(),
        batteryLevel: Double? = nil,
        isCharging: Bool = false,
        speedMetersPerSecond: Double? = nil,
        speedUnit: SpeedUnit = .kilometersPerHour,
        navigationDestination: String? = nil,
        remainingDistance: Double? = nil,
        remainingTime: Double? = nil,
        weatherSummary: String? = nil,
        placeName: String? = nil,
        headingDegrees: Double? = nil,
        isOnline: Bool = true
    ) {
        self.now = now
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.speedMetersPerSecond = speedMetersPerSecond
        self.speedUnit = speedUnit
        self.navigationDestination = navigationDestination
        self.remainingDistance = remainingDistance
        self.remainingTime = remainingTime
        self.weatherSummary = weatherSummary
        self.placeName = placeName
        self.headingDegrees = headingDegrees
        self.isOnline = isOnline
    }
}

public enum LocalResponder {
    public static func respond(to topic: StatusTopic, context c: AssistantContext) -> String {
        switch topic {
        case .time:
            return "現在の時刻は\(HUDFormat.spokenClock(c.now))です。"
        case .date:
            return "今日は\(HUDFormat.date(c.now))です。"
        case .battery:
            guard let level = c.batteryLevel, level >= 0 else { return "バッテリー残量を取得できません。" }
            return "バッテリー残量は\(HUDFormat.percent(level))です。" + (c.isCharging ? "充電中です。" : "")
        case .speed:
            guard let v = c.speedMetersPerSecond, v >= 0 else { return "速度を取得できません。位置情報の精度が低い可能性があります。" }
            return "現在の速度は時速約\(HUDFormat.speed(v, unit: .kilometersPerHour))キロメートルです。"
        case .eta:
            guard let t = c.remainingTime, let dest = c.navigationDestination else { return "現在ナビゲーションは行っていません。" }
            return "\(dest)への到着予定は\(HUDFormat.spokenClock(c.now.addingTimeInterval(t)))、あと約\(HUDFormat.duration(t))です。"
        case .remainingDistance:
            guard let d = c.remainingDistance, let dest = c.navigationDestination else { return "現在ナビゲーションは行っていません。" }
            return "\(dest)まで残り\(HUDFormat.spokenDistance(d))です。"
        case .weather:
            guard let w = c.weatherSummary else {
                return c.isOnline ? "天気情報をまだ取得していません。" : "オフラインのため天気情報を取得できません。"
            }
            return w
        case .location:
            guard let name = c.placeName else { return "現在地の地名を取得できません。" }
            return "現在地は\(name)付近です。"
        case .heading:
            guard let h = c.headingDegrees, h >= 0 else { return "方角を取得できません。" }
            return "いま\(Geo.cardinalName(h))を向いています。"
        }
    }

    /// クラウドAIを使えないときの返答。
    public static func fallbackAnswer(for question: String, cloudAvailable: Bool, isOnline: Bool) -> String {
        if !cloudAvailable {
            return "その質問には端末内では答えられません。設定でクラウドAIを有効にすると、会話形式で答えられます。使える音声コマンドの例：「黒背景にして」「速度を表示して」「東京駅までナビして」。"
        }
        if !isOnline {
            return "オフラインのためAIに質問できません。音声コマンドは使えます。"
        }
        return "AIに問い合わせています。"
    }

    /// 音声コマンドの使い方の例。
    public static let commandExamples: [String] = [
        "黒背景にして / カメラにして",
        "徒歩ナビモードにして / ミニマルモードにして",
        "東京駅までナビして",
        "近くのコンビニを探して",
        "ナビを終了して",
        "地図を大きくして / 地図を3Dにして",
        "速度を表示して / 時計を消して",
        "音声案内をオフにして",
        "今何時？ / あと何分？ / バッテリーは？",
        "HUDを開始して / HUDを編集",
    ]
}
