import Foundation

public enum DisplayOutputPreference: String, Codable, CaseIterable, Sendable {
    /// 独立外部画面が使えれば使い、使えなければミラー。
    case automatic
    /// 常にミラー（端末画面＝HUD）。
    case mirrorOnly

    public var displayName: String {
        switch self {
        case .automatic: return "自動（独立表示を優先）"
        case .mirrorOnly: return "ミラーのみ"
        }
    }
}

public enum MapEngine: String, Codable, CaseIterable, Sendable {
    case appleMapKit
    case googleMaps

    public var displayName: String {
        switch self {
        case .appleMapKit: return "Apple マップ（MapKit）"
        case .googleMaps: return "Google Maps（未対応・将来対応）"
        }
    }

    /// 現在のビルドで使えるか。Google Maps は APIキー・課金の確認が必要なため未実装。
    public var isAvailable: Bool { self == .appleMapKit }
}

public enum MapOrientation: String, Codable, CaseIterable, Sendable {
    case headingUp, northUp

    public var displayName: String {
        switch self {
        case .headingUp: return "進行方向が上"
        case .northUp: return "北が上"
        }
    }
}

public enum TransportMode: String, Codable, CaseIterable, Sendable {
    case walking, automobile, transit

    public var displayName: String {
        switch self {
        case .walking: return "徒歩"
        case .automobile: return "自動車"
        case .transit: return "公共交通"
        }
    }

    public var systemImage: String {
        switch self {
        case .walking: return "figure.walk"
        case .automobile: return "car"
        case .transit: return "tram"
        }
    }
}

public enum GuidanceFrequency: String, Codable, CaseIterable, Sendable {
    case low, normal, high

    public var displayName: String {
        switch self {
        case .low: return "少なめ"
        case .normal: return "標準"
        case .high: return "多め"
        }
    }
}

public struct MapSettings: Codable, Hashable, Sendable {
    public var engine: MapEngine = .appleMapKit
    public var use3D: Bool = false
    public var orientation: MapOrientation = .headingUp
    public var followsUser: Bool = true
    public var defaultTransport: TransportMode = .walking
    public var showsTraffic: Bool = false
    public init() {}
}

public struct VoiceSettings: Codable, Hashable, Sendable {
    public var guidanceEnabled: Bool = true
    /// 0.0〜1.0
    public var volume: Double = 0.9
    /// AVSpeechUtterance の速度（0.3〜0.65 程度）
    public var rate: Double = 0.5
    public var pitch: Double = 1.0
    public var voiceIdentifier: String? = nil
    public var frequency: GuidanceFrequency = .normal
    public var announceETA: Bool = true
    public init() {}
}

public enum AlertCategory: String, Codable, CaseIterable, Sendable {
    case navigation, arrival, reroute, hazard, weather, nearby, battery, connection, assistant, system

    public var displayName: String {
        switch self {
        case .navigation: return "ナビゲーション"
        case .arrival: return "目的地到着"
        case .reroute: return "ルート変更"
        case .hazard: return "危険検知"
        case .weather: return "天気"
        case .nearby: return "周辺施設"
        case .battery: return "バッテリー"
        case .connection: return "接続状態"
        case .assistant: return "AIからの提案"
        case .system: return "システム"
        }
    }
}

public struct AlertChannelSettings: Codable, Hashable, Sendable {
    public var showsBanner: Bool
    public var speaks: Bool
    public var playsSound: Bool

    public init(showsBanner: Bool = true, speaks: Bool = false, playsSound: Bool = false) {
        self.showsBanner = showsBanner
        self.speaks = speaks
        self.playsSound = playsSound
    }
}

public struct NotificationSettings: Codable, Hashable, Sendable {
    public var channels: [AlertCategory: AlertChannelSettings]
    /// 同じ種類の通知を繰り返さない間隔（秒）。
    public var cooldownSeconds: Double = 20

    public init() {
        var c: [AlertCategory: AlertChannelSettings] = [:]
        for category in AlertCategory.allCases {
            switch category {
            case .hazard: c[category] = AlertChannelSettings(showsBanner: true, speaks: true, playsSound: true)
            case .arrival, .reroute: c[category] = AlertChannelSettings(showsBanner: true, speaks: true, playsSound: false)
            case .navigation: c[category] = AlertChannelSettings(showsBanner: false, speaks: true, playsSound: false)
            case .battery, .connection: c[category] = AlertChannelSettings(showsBanner: true, speaks: false, playsSound: true)
            default: c[category] = AlertChannelSettings()
            }
        }
        channels = c
    }

    public func channel(for category: AlertCategory) -> AlertChannelSettings {
        channels[category] ?? AlertChannelSettings()
    }

    enum CodingKeys: String, CodingKey { case channels, cooldownSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotificationSettings()
        // 辞書は文字列キーで保存する（enum キーの辞書は配列形式になるため）。
        let raw: [String: AlertChannelSettings] = c.value(.channels, default: [:])
        var merged = d.channels
        for (key, value) in raw {
            if let category = AlertCategory(rawValue: key) { merged[category] = value }
        }
        channels = merged
        cooldownSeconds = c.value(.cooldownSeconds, default: d.cooldownSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var raw: [String: AlertChannelSettings] = [:]
        for (key, value) in channels { raw[key.rawValue] = value }
        try c.encode(raw, forKey: .channels)
        try c.encode(cooldownSeconds, forKey: .cooldownSeconds)
    }
}

public struct CameraSettings: Codable, Hashable, Sendable {
    /// 露出補正（-2.0〜2.0 EV）
    public var exposureBias: Double = 0
    /// ズーム倍率（1.0〜4.0）
    public var zoom: Double = 1
    /// コントラスト（0.5〜1.5、1.0 で無加工）
    public var contrast: Double = 1
    public var prefersUltraWide: Bool = false
    public init() {}
}

public struct DetectionSettings: Codable, Hashable, Sendable {
    public var enabled: Bool = false
    public var minimumConfidence: Double = 0.5
    /// 1秒あたりの推論回数（省電力のため間引く）
    public var inferenceFPS: Double = 8
    public var detectsPeople: Bool = true
    public var detectsAnimals: Bool = true
    public var usesCustomModel: Bool = true
    public var showsLabels: Bool = true
    public var showsConfidence: Bool = true
    public var showsDistanceEstimate: Bool = false
    public var hazardAlertsEnabled: Bool = false
    /// 初回同意（実験機能・安全装置ではない）を取ったか
    public var hasAcceptedDisclaimer: Bool = false
    public init() {}
}

public enum AssistantProviderKind: String, Codable, CaseIterable, Sendable {
    case localOnly
    case gemini
    case anthropic
    case openAICompatible

    public var displayName: String {
        switch self {
        case .localOnly: return "端末内のみ（無料・オフライン）"
        case .gemini: return "Google Gemini（APIキーが必要）"
        case .anthropic: return "Anthropic Claude（APIキー・従量課金）"
        case .openAICompatible: return "OpenAI 互換API（APIキーが必要）"
        }
    }

    public var defaultModel: String {
        switch self {
        case .localOnly: return ""
        case .gemini: return "gemini-2.5-flash"
        case .anthropic: return "claude-opus-5-5"
        case .openAICompatible: return "gpt-4o-mini"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .localOnly: return ""
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .anthropic: return "https://api.anthropic.com"
        case .openAICompatible: return "https://api.openai.com/v1"
        }
    }

    public var isCloud: Bool { self != .localOnly }
}

public struct AssistantSettings: Codable, Hashable, Sendable {
    public var provider: AssistantProviderKind = .localOnly
    public var model: String = ""
    public var baseURL: String = ""
    /// クラウド送信の同意（送信内容を確認したうえで ON にする）
    public var cloudConsentGiven: Bool = false
    /// 位置情報（丸めた地名レベル）を AI に送ってよいか
    public var sharesApproximateLocation: Bool = false
    public var speaksResponses: Bool = true
    /// 音声認識を端末内だけで行う（音声を外部に送らない）
    public var requiresOnDeviceSpeech: Bool = true
    public init() {}

    public var effectiveModel: String { model.isEmpty ? provider.defaultModel : model }
    public var effectiveBaseURL: String { baseURL.isEmpty ? provider.defaultBaseURL : baseURL }
}

public struct HistorySettings: Codable, Hashable, Sendable {
    /// 既定 OFF（プライバシー）
    public var enabled: Bool = false
    public var recordsRoutePoints: Bool = false
    public var recordsDetections: Bool = false
    public var retentionDays: Int = 90
    public init() {}
}

public struct PrivacySettings: Codable, Hashable, Sendable {
    /// 実機テストレポート等を書き出すとき位置を丸める
    public var roundsExportedLocations: Bool = true
    public var weatherEnabled: Bool = true
    public init() {}
}

public struct PowerSettings: Codable, Hashable, Sendable {
    public var automaticPowerSaving: Bool = true
    /// 端末画面を暗くする（iPhone で外部画面使用中）
    public var dimsDeviceScreenWhenExternal: Bool = true
    public var keepsScreenAwake: Bool = true
    public init() {}
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var displayOutput: DisplayOutputPreference = .automatic
    /// グラスを接続したら自動で HUD を表示する（ミラー表示の場合）
    public var autoStartHUDOnConnect: Bool = true
    public var map = MapSettings()
    public var voice = VoiceSettings()
    public var notifications = NotificationSettings()
    public var camera = CameraSettings()
    public var detection = DetectionSettings()
    public var assistant = AssistantSettings()
    public var history = HistorySettings()
    public var privacy = PrivacySettings()
    public var power = PowerSettings()
    public var selectedPresetID: UUID? = nil
    public var hasCompletedOnboarding: Bool = false
    public var showsMetricsOverlay: Bool = false

    public init() {}

    /// 欠けた項目を既定値で補って読み込む（前方互換）。
    public static func decodeMergingDefaults(from data: Data) throws -> AppSettings {
        try JSONMerge.decode(AppSettings.self, from: data, defaults: AppSettings())
    }
}

/// 既定値の JSON に保存済み JSON を上書き合成してからデコードする。
/// ネストした設定に項目が増えても、古いファイルを読み込める。
public enum JSONMerge {
    public static func decode<T: Codable>(_ type: T.Type, from data: Data, defaults: T) throws -> T {
        let defaultData = try HUDJSON.encode(defaults, pretty: false)
        guard
            let base = try JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
            let stored = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return try HUDJSON.decode(type, from: data)
        }
        let merged = merge(base, stored)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try HUDJSON.decode(type, from: mergedData)
    }

    static func merge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let baseDict = base[key] as? [String: Any], let overlayDict = value as? [String: Any] {
                result[key] = merge(baseDict, overlayDict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
