import Foundation

public enum ThermalLevel: Int, Codable, Comparable, Sendable {
    case nominal = 0, fair, serious, critical

    public static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .nominal: return "正常"
        case .fair: return "やや高い"
        case .serious: return "高温"
        case .critical: return "危険な高温"
        }
    }
}

public enum LocationAccuracyLevel: String, Codable, Sendable {
    case best, navigation, tenMeters, hundredMeters
}

public enum PowerQuality: Int, Codable, Comparable, Sendable {
    case normal = 0, saver, critical

    public static func < (lhs: PowerQuality, rhs: PowerQuality) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
        switch self {
        case .normal: return "通常"
        case .saver: return "節約"
        case .critical: return "高温・低残量"
        }
    }
}

public struct PowerState: Hashable, Sendable {
    public var thermal: ThermalLevel
    /// 0〜1、不明なら -1
    public var batteryLevel: Double
    public var isCharging: Bool
    public var isLowPowerMode: Bool

    public init(thermal: ThermalLevel = .nominal, batteryLevel: Double = -1, isCharging: Bool = false, isLowPowerMode: Bool = false) {
        self.thermal = thermal
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
    }
}

/// 各サービスの更新頻度・品質。
public struct PowerProfile: Hashable, Sendable {
    public var quality: PowerQuality
    public var cameraFPS: Int
    public var cameraMaxHeight: Int
    public var inferenceFPS: Double
    public var locationAccuracy: LocationAccuracyLevel
    public var motionHz: Double
    public var miniMapUpdateInterval: TimeInterval
    public var allowsGlowEffects: Bool
    /// ユーザーに伝えるべき提案（nil なら不要）
    public var suggestion: String?
}

public enum PowerPolicy {
    public static func quality(for state: PowerState, automatic: Bool) -> PowerQuality {
        guard automatic else { return .normal }
        if state.thermal >= .serious { return .critical }
        if state.batteryLevel >= 0 && state.batteryLevel <= 0.10 && !state.isCharging { return .critical }
        if state.thermal == .fair || state.isLowPowerMode { return .saver }
        if state.batteryLevel >= 0 && state.batteryLevel <= 0.25 && !state.isCharging { return .saver }
        return .normal
    }

    public static func profile(for state: PowerState, automatic: Bool = true, requestedInferenceFPS: Double = 8) -> PowerProfile {
        let q = quality(for: state, automatic: automatic)
        switch q {
        case .normal:
            return PowerProfile(
                quality: q, cameraFPS: 30, cameraMaxHeight: 1080, inferenceFPS: min(requestedInferenceFPS, 10),
                locationAccuracy: .best, motionHz: 30, miniMapUpdateInterval: 1, allowsGlowEffects: true, suggestion: nil
            )
        case .saver:
            var suggestion: String?
            if state.thermal == .fair { suggestion = "端末の温度が上がっています。カメラや物体認識の負荷を下げています。" }
            else if !state.isLowPowerMode && state.batteryLevel >= 0 && state.batteryLevel <= 0.25 {
                suggestion = "バッテリー残量が少なくなっています。設定アプリで低電力モードをオンにすることをおすすめします。"
            }
            return PowerProfile(
                quality: q, cameraFPS: 24, cameraMaxHeight: 720, inferenceFPS: min(requestedInferenceFPS, 5),
                locationAccuracy: .navigation, motionHz: 10, miniMapUpdateInterval: 2, allowsGlowEffects: false, suggestion: suggestion
            )
        case .critical:
            let suggestion = state.thermal >= .serious
                ? "端末が高温です。カメラと物体認識を停止することをおすすめします。"
                : "バッテリー残量がわずかです。カメラと物体認識を停止し、充電してください。"
            return PowerProfile(
                quality: q, cameraFPS: 15, cameraMaxHeight: 720, inferenceFPS: min(requestedInferenceFPS, 2),
                locationAccuracy: .tenMeters, motionHz: 5, miniMapUpdateInterval: 5, allowsGlowEffects: false, suggestion: suggestion
            )
        }
    }
}

/// 移動状態の推定（速度と端末の動きから）。
public enum MovementState: String, Codable, Sendable {
    case stationary, walking, running, cycling, vehicle, unknown

    public var displayName: String {
        switch self {
        case .stationary: return "停止中"
        case .walking: return "徒歩"
        case .running: return "走行（ランニング）"
        case .cycling: return "自転車"
        case .vehicle: return "乗り物"
        case .unknown: return "不明"
        }
    }

    public var isMoving: Bool { self != .stationary && self != .unknown }

    /// 速度（m/s）から推定。歩行者向けアプリなので境界は保守的に。
    public static func estimate(speed: Double?, accelerationVariance: Double?) -> MovementState {
        if let v = speed, v >= 0 {
            if v < 0.4 {
                if let a = accelerationVariance, a > 0.02 { return .walking }
                return .stationary
            }
            if v < 2.2 { return .walking }
            if v < 4.0 { return .running }
            if v < 7.0 { return .cycling }
            return .vehicle
        }
        if let a = accelerationVariance {
            return a > 0.02 ? .walking : .stationary
        }
        return .unknown
    }
}

/// 乗り物の速度が続いたら HUD を最小化する（運転中の利用を前提としないため）。
public struct VehicleSpeedGuard: Sendable {
    public var thresholdSpeed: Double = 5.6 // 約20km/h
    public var requiredDuration: TimeInterval = 15
    private var since: Date?

    public init() {}

    /// 戻り値：HUDを最小化すべきか
    public mutating func update(speed: Double?, at now: Date) -> Bool {
        guard let v = speed, v >= thresholdSpeed else {
            since = nil
            return false
        }
        if let s = since { return now.timeIntervalSince(s) >= requiredDuration }
        since = now
        return false
    }
}
