import Foundation

public enum BackgroundMode: String, Codable, CaseIterable, Sendable {
    case black, camera

    public var displayName: String {
        switch self {
        case .black: return "黒背景"
        case .camera: return "カメラ"
        }
    }

    public var toggled: BackgroundMode { self == .black ? .camera : .black }
}

/// プリセットで切り替える機能のON/OFF。
public struct FeatureToggles: Codable, Hashable, Sendable {
    public var voiceGuidance: Bool
    public var objectDetection: Bool
    public var hazardAlerts: Bool
    /// 移動中は情報量を減らす（安全のため既定ON）。
    public var reduceWhileMoving: Bool

    public init(voiceGuidance: Bool = true, objectDetection: Bool = false, hazardAlerts: Bool = false, reduceWhileMoving: Bool = true) {
        self.voiceGuidance = voiceGuidance
        self.objectDetection = objectDetection
        self.hazardAlerts = hazardAlerts
        self.reduceWhileMoving = reduceWhileMoving
    }

    enum CodingKeys: String, CodingKey {
        case voiceGuidance, objectDetection, hazardAlerts, reduceWhileMoving
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureToggles()
        voiceGuidance = c.value(.voiceGuidance, default: d.voiceGuidance)
        objectDetection = c.value(.objectDetection, default: d.objectDetection)
        hazardAlerts = c.value(.hazardAlerts, default: d.hazardAlerts)
        reduceWhileMoving = c.value(.reduceWhileMoving, default: d.reduceWhileMoving)
    }
}

public struct Preset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var layout: HUDLayout
    /// テーマの key（組み込み）または id 文字列（ユーザーテーマ）。
    public var themeRef: String
    public var background: BackgroundMode
    public var features: FeatureToggles
    public var isBuiltIn: Bool
    public var key: String?

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "square.grid.2x2",
        layout: HUDLayout,
        themeRef: String,
        background: BackgroundMode = .black,
        features: FeatureToggles = FeatureToggles(),
        isBuiltIn: Bool = false,
        key: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.layout = layout
        self.themeRef = themeRef
        self.background = background
        self.features = features
        self.isBuiltIn = isBuiltIn
        self.key = key
    }

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, layout, themeRef, background, features, isBuiltIn, key
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "プリセット")
        symbol = c.value(.symbol, default: "square.grid.2x2")
        layout = c.value(.layout, default: HUDLayout(name: "レイアウト", panels: []))
        themeRef = c.value(.themeRef, default: BuiltInContent.defaultThemeKey)
        background = c.value(.background, default: .black)
        features = c.value(.features, default: FeatureToggles())
        isBuiltIn = c.value(.isBuiltIn, default: false)
        key = c.value(.key, default: nil)
    }

    public func duplicated(name newName: String? = nil) -> Preset {
        var copy = self
        copy.id = UUID()
        copy.name = newName ?? "\(name) のコピー"
        copy.isBuiltIn = false
        copy.key = nil
        copy.layout.id = UUID()
        copy.layout.panels = layout.panels.map { panel in
            var p = panel
            p.id = UUID()
            return p
        }
        return copy
    }
}

/// 目的地のお気に入り。
public struct FavoritePlace: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var coordinate: GeoCoordinate

    public init(id: UUID = UUID(), name: String, address: String = "", coordinate: GeoCoordinate) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
    }
}
