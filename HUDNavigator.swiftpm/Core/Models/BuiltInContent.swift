import Foundation

/// 組み込みテーマ（7種）とプリセット（7種）。
/// UUID は固定値にして、端末間でエクスポート／インポートしても同じものとして扱えるようにする。
public enum BuiltInContent {
    public static let defaultThemeKey = "apple"
    public static let defaultPresetKey = "walkNav"

    // MARK: - テーマ

    public static let themes: [Theme] = [
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Apple風",
            style: PanelStyle(
                textColor: .white,
                secondaryTextColor: ColorToken(hex: "#C7CDD6")!,
                accentColor: ColorToken(hex: "#64D2FF")!,
                backgroundColor: ColorToken(hex: "#1C1C1E")!,
                backgroundOpacity: 0.35,
                fontDesign: .rounded,
                fontScale: 1.0,
                fontWeight: .semibold,
                borderWidth: 1,
                borderColor: ColorToken.white.withAlpha(0.22),
                cornerRadius: 18,
                shadowRadius: 0,
                glowRadius: 0,
                glowColor: ColorToken(hex: "#64D2FF")!,
                animation: .smooth
            ),
            isBuiltIn: true,
            key: "apple"
        ),
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            name: "ミニマル",
            style: PanelStyle(
                textColor: .white,
                secondaryTextColor: ColorToken(hex: "#D0D0D0")!,
                accentColor: .white,
                backgroundColor: .black,
                backgroundOpacity: 0,
                fontDesign: .standard,
                fontScale: 1.0,
                fontWeight: .medium,
                borderWidth: 0,
                borderColor: .clear,
                cornerRadius: 0,
                shadowRadius: 0,
                glowRadius: 0,
                glowColor: .white,
                animation: .none
            ),
            isBuiltIn: true,
            key: "minimal"
        ),
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
            name: "サイバーパンク",
            style: PanelStyle(
                textColor: ColorToken(hex: "#FCEE0A")!,
                secondaryTextColor: ColorToken(hex: "#00F0FF")!,
                accentColor: ColorToken(hex: "#FF2A6D")!,
                backgroundColor: ColorToken(hex: "#120024")!,
                backgroundOpacity: 0.4,
                fontDesign: .monospaced,
                fontScale: 1.0,
                fontWeight: .bold,
                borderWidth: 2,
                borderColor: ColorToken(hex: "#FF2A6D")!,
                cornerRadius: 4,
                shadowRadius: 0,
                glowRadius: 8,
                glowColor: ColorToken(hex: "#FF2A6D")!,
                animation: .smooth
            ),
            warningColor: ColorToken(hex: "#FCEE0A")!,
            dangerColor: ColorToken(hex: "#FF2A6D")!,
            isBuiltIn: true,
            key: "cyberpunk"
        ),
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!,
            name: "ネオン",
            style: PanelStyle(
                textColor: ColorToken(hex: "#E8FFFF")!,
                secondaryTextColor: ColorToken(hex: "#7DF9FF")!,
                accentColor: ColorToken(hex: "#39FF14")!,
                backgroundColor: .black,
                backgroundOpacity: 0.2,
                fontDesign: .rounded,
                fontScale: 1.0,
                fontWeight: .semibold,
                borderWidth: 1.5,
                borderColor: ColorToken(hex: "#7DF9FF")!,
                cornerRadius: 22,
                shadowRadius: 0,
                glowRadius: 12,
                glowColor: ColorToken(hex: "#7DF9FF")!,
                animation: .smooth
            ),
            isBuiltIn: true,
            key: "neon"
        ),
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!,
            name: "モノクロ",
            style: PanelStyle(
                textColor: .white,
                secondaryTextColor: ColorToken(hex: "#BDBDBD")!,
                accentColor: .white,
                backgroundColor: ColorToken(hex: "#202020")!,
                backgroundOpacity: 0.3,
                fontDesign: .standard,
                fontScale: 1.0,
                fontWeight: .bold,
                borderWidth: 1,
                borderColor: ColorToken.white.withAlpha(0.5),
                cornerRadius: 8,
                shadowRadius: 0,
                glowRadius: 0,
                glowColor: .white,
                animation: .none
            ),
            warningColor: .white,
            dangerColor: .white,
            isBuiltIn: true,
            key: "mono"
        ),
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A6")!,
            name: "ナビゲーション特化",
            style: PanelStyle(
                textColor: .white,
                secondaryTextColor: ColorToken(hex: "#A8F0C6")!,
                accentColor: ColorToken(hex: "#5CFF8A")!,
                backgroundColor: ColorToken(hex: "#002914")!,
                backgroundOpacity: 0.35,
                fontDesign: .rounded,
                fontScale: 1.15,
                fontWeight: .bold,
                borderWidth: 1,
                borderColor: ColorToken(hex: "#5CFF8A")!.withAlpha(0.5),
                cornerRadius: 16,
                shadowRadius: 0,
                glowRadius: 4,
                glowColor: ColorToken(hex: "#5CFF8A")!,
                animation: .subtle
            ),
            isBuiltIn: true,
            key: "navigation"
        ),
        Theme(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A7")!,
            name: "情報表示特化",
            style: PanelStyle(
                textColor: .white,
                secondaryTextColor: ColorToken(hex: "#B0C4DE")!,
                accentColor: ColorToken(hex: "#FFD84A")!,
                backgroundColor: ColorToken(hex: "#0B1A2E")!,
                backgroundOpacity: 0.4,
                fontDesign: .standard,
                fontScale: 0.9,
                fontWeight: .medium,
                borderWidth: 1,
                borderColor: ColorToken(hex: "#B0C4DE")!.withAlpha(0.35),
                cornerRadius: 10,
                shadowRadius: 0,
                glowRadius: 0,
                glowColor: ColorToken(hex: "#FFD84A")!,
                animation: .subtle
            ),
            isBuiltIn: true,
            key: "info"
        ),
    ]

    public static func theme(key: String) -> Theme? {
        themes.first { $0.key == key }
    }

    // MARK: - プリセット

    private static func panel(_ kind: WidgetKind, _ x: Double, _ y: Double, _ w: Double? = nil, _ h: Double? = nil, z: Int = 0, config: WidgetConfig = WidgetConfig()) -> HUDPanel {
        let size = kind.defaultSize
        return HUDPanel(
            id: UUID(),
            widget: kind,
            config: config,
            frame: NormalizedRect(x: x, y: y, width: w ?? size.width, height: h ?? size.height),
            zIndex: z
        )
    }

    /// 組み込みプリセットを新しく生成する（パネルIDは毎回新規）。
    public static func makePresets() -> [Preset] {
        [
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                name: "徒歩ナビ",
                symbol: "figure.walk",
                layout: HUDLayout(name: "徒歩ナビ", panels: [
                    panel(.nextTurn, 0.37, 0.04, 0.26, 0.14),
                    panel(.eta, 0.04, 0.04),
                    panel(.speed, 0.83, 0.04, 0.13, 0.12),
                    panel(.miniMap, 0.76, 0.62, 0.21, 0.32),
                    panel(.clock, 0.04, 0.86, 0.14, 0.09),
                ]),
                themeRef: "navigation",
                features: FeatureToggles(voiceGuidance: true, objectDetection: false, hazardAlerts: false, reduceWhileMoving: true),
                isBuiltIn: true,
                key: "walkNav"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
                name: "旅行",
                symbol: "airplane",
                layout: HUDLayout(name: "旅行", panels: [
                    panel(.nextTurn, 0.37, 0.04, 0.26, 0.14),
                    panel(.weather, 0.04, 0.04),
                    panel(.clock, 0.83, 0.04, 0.13, 0.09),
                    panel(.compass, 0.04, 0.78, 0.11, 0.15),
                    panel(.miniMap, 0.76, 0.62, 0.21, 0.32),
                    panel(.eta, 0.40, 0.86, 0.20, 0.09),
                ]),
                themeRef: "apple",
                isBuiltIn: true,
                key: "travel"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!,
                name: "日常生活",
                symbol: "sun.max",
                layout: HUDLayout(name: "日常生活", panels: [
                    panel(.clock, 0.04, 0.04),
                    panel(.date, 0.04, 0.15),
                    panel(.weather, 0.78, 0.04, 0.18, 0.12),
                    panel(.battery, 0.84, 0.88, 0.12, 0.08),
                    panel(.notifications, 0.33, 0.86, 0.34, 0.10),
                ]),
                themeRef: "apple",
                features: FeatureToggles(voiceGuidance: false),
                isBuiltIn: true,
                key: "daily"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!,
                name: "情報表示",
                symbol: "info.circle",
                layout: HUDLayout(name: "情報表示", panels: [
                    panel(.clock, 0.04, 0.04),
                    panel(.date, 0.21, 0.04),
                    panel(.weather, 0.04, 0.16),
                    panel(.temperature, 0.25, 0.16),
                    panel(.precipitation, 0.04, 0.30),
                    panel(.airQuality, 0.17, 0.30),
                    panel(.battery, 0.84, 0.04),
                    panel(.gpsStatus, 0.82, 0.14),
                    panel(.sensors, 0.76, 0.76),
                ]),
                themeRef: "info",
                features: FeatureToggles(voiceGuidance: false),
                isBuiltIn: true,
                key: "info"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!,
                name: "デスクワーク",
                symbol: "desktopcomputer",
                layout: HUDLayout(name: "デスクワーク", panels: [
                    panel(.clock, 0.80, 0.04, 0.16, 0.10, config: WidgetConfig(showsSeconds: true)),
                    panel(.notifications, 0.62, 0.86, 0.34, 0.10),
                    panel(.battery, 0.04, 0.88),
                ]),
                themeRef: "minimal",
                features: FeatureToggles(voiceGuidance: false, reduceWhileMoving: false),
                isBuiltIn: true,
                key: "desk"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B6")!,
                name: "ミニマル",
                symbol: "circle.dashed",
                layout: HUDLayout(name: "ミニマル", panels: [
                    panel(.clock, 0.42, 0.04, 0.16, 0.09),
                    panel(.nextTurn, 0.40, 0.84, 0.20, 0.11, config: WidgetConfig(compact: true)),
                ]),
                themeRef: "minimal",
                isBuiltIn: true,
                key: "minimal"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B7")!,
                name: "カスタム",
                symbol: "slider.horizontal.3",
                layout: HUDLayout(name: "カスタム", panels: [
                    panel(.clock, 0.04, 0.04),
                    panel(.customText, 0.40, 0.45, 0.20, 0.08, config: WidgetConfig(text: "HUD Navigator")),
                ]),
                themeRef: "apple",
                features: FeatureToggles(voiceGuidance: false),
                isBuiltIn: true,
                key: "custom"
            ),
        ]
    }

    /// 音声コマンドで使うプリセット名の別名。
    public static let presetAliases: [String: [String]] = [
        "walkNav": ["徒歩ナビ", "とほなび", "徒歩", "ウォーキング", "歩き"],
        "travel": ["旅行", "りょこう", "トラベル", "観光"],
        "daily": ["日常生活", "日常", "にちじょう", "普段"],
        "info": ["情報表示", "情報", "じょうほう", "インフォ"],
        "desk": ["デスクワーク", "デスク", "仕事", "作業"],
        "minimal": ["ミニマル", "みにまる", "シンプル"],
        "custom": ["カスタム", "かすたむ"],
    ]

    public static let themeAliases: [String: [String]] = [
        "apple": ["アップル", "apple", "あっぷる", "標準"],
        "minimal": ["ミニマル", "みにまる", "シンプル"],
        "cyberpunk": ["サイバーパンク", "さいばーぱんく", "サイバー"],
        "neon": ["ネオン", "ねおん"],
        "mono": ["モノクロ", "ものくろ", "白黒"],
        "navigation": ["ナビゲーション", "ナビ特化", "ナビ"],
        "info": ["情報表示", "情報特化", "情報"],
    ]
}
