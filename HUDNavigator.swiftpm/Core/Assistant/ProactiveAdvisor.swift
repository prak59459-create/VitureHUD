import Foundation

/// 状況からの提案（「AIからの提案」通知）。端末内のルールで判断する。
public struct Suggestion: Hashable, Sendable {
    public var key: String
    public var title: String
    public var message: String
    /// 提案に添える操作（ボタン・音声で実行できる）
    public var action: AppCommand?
}

public struct AdvisorInput: Sendable {
    public var now: Date
    public var weather: WeatherSnapshot?
    public var batteryLevel: Double
    public var isCharging: Bool
    public var thermal: ThermalLevel
    public var movement: MovementState
    /// 歩き続けている時間（秒）
    public var continuousMovingSeconds: TimeInterval
    public var justArrived: Bool
    public var isHUDVisible: Bool
    public var cameraActive: Bool
    public var activePresetKey: String?

    public init(now: Date, weather: WeatherSnapshot? = nil, batteryLevel: Double = -1, isCharging: Bool = false, thermal: ThermalLevel = .nominal, movement: MovementState = .unknown, continuousMovingSeconds: TimeInterval = 0, justArrived: Bool = false, isHUDVisible: Bool = false, cameraActive: Bool = false, activePresetKey: String? = nil) {
        self.now = now
        self.weather = weather
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.thermal = thermal
        self.movement = movement
        self.continuousMovingSeconds = continuousMovingSeconds
        self.justArrived = justArrived
        self.isHUDVisible = isHUDVisible
        self.cameraActive = cameraActive
        self.activePresetKey = activePresetKey
    }
}

public struct ProactiveAdvisor: Sendable {
    public var settings: ProactiveSettings
    private var lastFired: [String: Date] = [:]

    public init(settings: ProactiveSettings) {
        self.settings = settings
    }

    /// 提案を作る。同じ提案は cooldown の間は出さない。
    public mutating func evaluate(_ input: AdvisorInput) -> [Suggestion] {
        guard settings.enabled else { return [] }
        var out: [(Suggestion, TimeInterval)] = []

        if settings.weatherTips, let w = input.weather {
            if let rain = w.rainExpected(withinHours: 2, threshold: 60, after: input.now) {
                let when = HUDFormat.clock(rain.time)
                out.append((Suggestion(key: "rain", title: "雨が降りそうです", message: "\(when)ごろ降水確率\(Int(rain.precipitationProbability ?? 0))%。傘をお持ちください。", action: .showWidget(.hourlyForecast)), 3 * 3600))
            }
            if let uv = w.uvIndex, uv >= 6 {
                out.append((Suggestion(key: "uv", title: "紫外線が強いです", message: "UV指数 \(Int(uv.rounded()))。日焼け対策をおすすめします。", action: nil), 4 * 3600))
            }
            if let t = w.temperature, t >= 31 {
                out.append((Suggestion(key: "heat", title: "暑さに注意", message: "気温\(Int(t.rounded()))度。こまめに水分をとってください。", action: nil), 2 * 3600))
            } else if let t = w.temperature, t <= 3 {
                out.append((Suggestion(key: "cold", title: "寒さに注意", message: "気温\(Int(t.rounded()))度。路面の凍結にも気をつけてください。", action: nil), 3 * 3600))
            }
        }

        if settings.batteryTips, input.batteryLevel >= 0, !input.isCharging {
            if input.batteryLevel <= 0.3 && input.cameraActive {
                out.append((Suggestion(key: "battery-camera", title: "電池を長持ちさせるには", message: "カメラ背景をやめて黒背景にすると電池の減りを抑えられます。", action: .setBackground(.black)), 2 * 3600))
            } else if input.batteryLevel <= 0.3 && input.isHUDVisible && input.activePresetKey != "minimal" {
                out.append((Suggestion(key: "battery-minimal", title: "電池が少なくなっています", message: "ミニマルプリセットにすると表示を減らせます。", action: .applyPreset(key: "minimal")), 2 * 3600))
            }
        }

        if input.thermal >= .serious && input.cameraActive {
            out.append((Suggestion(key: "thermal", title: "端末が熱くなっています", message: "カメラ背景と物体認識を止めることをおすすめします。", action: .setBackground(.black)), 1800))
        }

        if settings.breakReminders, input.movement.isMoving, input.continuousMovingSeconds >= 60 * 60 {
            let minutes = Int(input.continuousMovingSeconds / 60)
            out.append((Suggestion(key: "break", title: "休憩しませんか", message: "\(minutes)分歩き続けています。安全な場所で一休みしましょう。", action: nil), 45 * 60))
        }

        if settings.nearbyTips, input.justArrived {
            out.append((Suggestion(key: "arrived-nearby", title: "到着しました", message: "近くのカフェやトイレを探せます。「近くのカフェを探して」と話しかけてください。", action: .searchNearby(.cafe)), 30 * 60))
        }

        var result: [Suggestion] = []
        for (s, cooldown) in out {
            if let last = lastFired[s.key], input.now.timeIntervalSince(last) < cooldown { continue }
            lastFired[s.key] = input.now
            result.append(s)
        }
        return result
    }
}
