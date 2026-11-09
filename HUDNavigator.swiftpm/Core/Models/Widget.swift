import Foundation

/// ウィジェットが動作に必要とするサービス。表示中のウィジェットだけサービスを起動する（省電力）。
public enum WidgetRequirement: String, Codable, CaseIterable, Sendable {
    case location, heading, motion, weather, navigation, camera, battery, assistant, alerts, bluetooth
}

public enum WidgetKind: String, Codable, CaseIterable, Sendable {
    case clock
    case date
    case battery
    case speed
    case compass
    case miniMap
    case weather
    case temperature
    case precipitation
    case airQuality
    case tripDistance
    case eta
    case nextTurn
    case notifications
    case gpsStatus
    case sensors
    case assistant
    case detections
    case customText
    case heartRate
    case horizon
    case hourlyForecast
    case nearbyPlaces

    public var displayName: String {
        switch self {
        case .clock: return "時計"
        case .date: return "日付"
        case .battery: return "バッテリー"
        case .speed: return "速度計"
        case .compass: return "コンパス"
        case .miniMap: return "ミニマップ"
        case .weather: return "天気"
        case .temperature: return "気温"
        case .precipitation: return "降水確率"
        case .airQuality: return "空気質"
        case .tripDistance: return "移動距離"
        case .eta: return "到着予想時刻"
        case .nextTurn: return "次の曲がり角"
        case .notifications: return "通知"
        case .gpsStatus: return "GPS状態"
        case .sensors: return "センサー情報"
        case .assistant: return "AIアシスタント"
        case .detections: return "物体検出"
        case .customText: return "テキスト（テンプレート）"
        case .heartRate: return "心拍数"
        case .horizon: return "水平器"
        case .hourlyForecast: return "時間ごとの天気"
        case .nearbyPlaces: return "周辺施設"
        }
    }

    /// SF Symbols 名（アプリ側で使用）。
    public var systemImage: String {
        switch self {
        case .clock: return "clock"
        case .date: return "calendar"
        case .battery: return "battery.75percent"
        case .speed: return "speedometer"
        case .compass: return "location.north.line"
        case .miniMap: return "map"
        case .weather: return "cloud.sun"
        case .temperature: return "thermometer.medium"
        case .precipitation: return "cloud.rain"
        case .airQuality: return "aqi.medium"
        case .tripDistance: return "figure.walk"
        case .eta: return "flag.checkered"
        case .nextTurn: return "arrow.turn.up.right"
        case .notifications: return "bell"
        case .gpsStatus: return "location.circle"
        case .sensors: return "gyroscope"
        case .assistant: return "waveform"
        case .detections: return "viewfinder"
        case .customText: return "textformat"
        case .heartRate: return "heart.fill"
        case .horizon: return "level"
        case .hourlyForecast: return "clock.badge.checkmark"
        case .nearbyPlaces: return "mappin.and.ellipse"
        }
    }

    public var requirements: Set<WidgetRequirement> {
        switch self {
        case .clock, .date, .customText: return []
        case .battery: return [.battery]
        case .speed, .gpsStatus, .tripDistance: return [.location]
        case .compass: return [.heading]
        case .miniMap: return [.location, .heading]
        case .weather, .temperature, .precipitation, .airQuality: return [.location, .weather]
        case .eta, .nextTurn: return [.location, .navigation]
        case .notifications: return [.alerts]
        case .sensors: return [.motion]
        case .assistant: return [.assistant]
        case .detections: return [.camera]
        case .heartRate: return [.bluetooth]
        case .horizon: return [.motion]
        case .hourlyForecast: return [.location, .weather]
        case .nearbyPlaces: return [.location]
        }
    }

    /// 追加時の既定の大きさ（正規化）。
    public var defaultSize: (width: Double, height: Double) {
        switch self {
        case .clock: return (0.16, 0.10)
        case .date: return (0.16, 0.08)
        case .battery: return (0.12, 0.08)
        case .speed: return (0.14, 0.14)
        case .compass: return (0.12, 0.16)
        case .miniMap: return (0.22, 0.30)
        case .weather: return (0.20, 0.12)
        case .temperature, .precipitation, .airQuality: return (0.12, 0.09)
        case .tripDistance: return (0.14, 0.09)
        case .eta: return (0.16, 0.10)
        case .nextTurn: return (0.26, 0.14)
        case .notifications: return (0.34, 0.10)
        case .gpsStatus: return (0.14, 0.08)
        case .sensors: return (0.20, 0.16)
        case .assistant: return (0.34, 0.12)
        case .detections: return (0.18, 0.10)
        case .customText: return (0.20, 0.08)
        case .heartRate: return (0.12, 0.10)
        case .horizon: return (0.14, 0.14)
        case .hourlyForecast: return (0.34, 0.14)
        case .nearbyPlaces: return (0.26, 0.18)
        }
    }
}

public enum SpeedUnit: String, Codable, CaseIterable, Sendable {
    case kilometersPerHour, metersPerSecond

    public var symbol: String {
        switch self {
        case .kilometersPerHour: return "km/h"
        case .metersPerSecond: return "m/s"
        }
    }

    public func convert(metersPerSecond value: Double) -> Double {
        switch self {
        case .kilometersPerHour: return value * 3.6
        case .metersPerSecond: return value
        }
    }
}

/// ウィジェットの設定（種類によって使う項目が異なる）。
public struct WidgetConfig: Codable, Hashable, Sendable {
    public var text: String
    public var showsSeconds: Bool
    public var uses24Hour: Bool
    public var speedUnit: SpeedUnit
    /// ミニマップの表示範囲（メートル）。
    public var mapSpanMeters: Double
    public var showsLabel: Bool
    public var compact: Bool

    public init(
        text: String = "",
        showsSeconds: Bool = false,
        uses24Hour: Bool = true,
        speedUnit: SpeedUnit = .kilometersPerHour,
        mapSpanMeters: Double = 400,
        showsLabel: Bool = true,
        compact: Bool = false
    ) {
        self.text = text
        self.showsSeconds = showsSeconds
        self.uses24Hour = uses24Hour
        self.speedUnit = speedUnit
        self.mapSpanMeters = mapSpanMeters
        self.showsLabel = showsLabel
        self.compact = compact
    }

    enum CodingKeys: String, CodingKey {
        case text, showsSeconds, uses24Hour, speedUnit, mapSpanMeters, showsLabel, compact
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WidgetConfig()
        text = c.value(.text, default: d.text)
        showsSeconds = c.value(.showsSeconds, default: d.showsSeconds)
        uses24Hour = c.value(.uses24Hour, default: d.uses24Hour)
        speedUnit = c.value(.speedUnit, default: d.speedUnit)
        mapSpanMeters = c.value(.mapSpanMeters, default: d.mapSpanMeters)
        showsLabel = c.value(.showsLabel, default: d.showsLabel)
        compact = c.value(.compact, default: d.compact)
    }
}
