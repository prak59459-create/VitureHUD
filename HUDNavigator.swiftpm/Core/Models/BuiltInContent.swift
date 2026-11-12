import Foundation

/// 組み込みテーマ（7種）とプリセット（12種）。
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
                layout: HUDLayout(name: "デスクワーク", panels: deskPanels()),
                themeRef: "apple",
                features: workFeatures,
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
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B8")!,
                name: "ブラウザ",
                symbol: "globe",
                layout: HUDLayout(name: "ブラウザ", panels: [
                    panel(.webPage, 0.14, 0.10, 0.72, 0.80),
                    panel(.clock, 0.03, 0.03, 0.10, 0.07),
                    panel(.battery, 0.87, 0.03, 0.10, 0.07, config: WidgetConfig(showsLabel: false)),
                ]),
                themeRef: "apple",
                features: workFeatures,
                isBuiltIn: true,
                key: "browser"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B9")!,
                name: "発表・会議",
                symbol: "person.wave.2",
                layout: HUDLayout(name: "発表・会議", panels: [
                    panel(.teleprompter, 0.18, 0.05, 0.64, 0.30),
                    panel(.timer, 0.04, 0.05, 0.13, 0.11),
                    panel(.clock, 0.84, 0.05, 0.12, 0.09),
                    panel(.notes, 0.04, 0.56, 0.24, 0.36),
                ]),
                themeRef: "apple",
                features: workFeatures,
                isBuiltIn: true,
                key: "presentation"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BA")!,
                name: "集中・勉強",
                symbol: "timer",
                layout: HUDLayout(name: "集中・勉強", panels: [
                    panel(.focusTimer, 0.40, 0.04, 0.20, 0.15),
                    panel(.todo, 0.04, 0.28, 0.22, 0.36),
                    panel(.notes, 0.74, 0.28, 0.22, 0.36),
                    panel(.clock, 0.84, 0.04, 0.12, 0.09),
                ]),
                themeRef: "minimal",
                features: workFeatures,
                isBuiltIn: true,
                key: "focus"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
                name: "運動",
                symbol: "figure.run",
                layout: HUDLayout(name: "運動", panels: [
                    panel(.heartRate, 0.04, 0.04, 0.14, 0.11),
                    panel(.timer, 0.42, 0.04, 0.16, 0.12),
                    panel(.speed, 0.82, 0.04, 0.14, 0.13),
                    panel(.tripDistance, 0.04, 0.84, 0.15, 0.10),
                    panel(.steps, 0.24, 0.84, 0.17, 0.10),
                    panel(.clock, 0.84, 0.86, 0.12, 0.09),
                ]),
                themeRef: "navigation",
                features: FeatureToggles(voiceGuidance: false, reduceWhileMoving: false),
                isBuiltIn: true,
                key: "workout"
            ),
            Preset(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BC")!,
                name: "料理・家事",
                symbol: "frying.pan",
                layout: HUDLayout(name: "料理・家事", panels: [
                    panel(.timer, 0.04, 0.04, 0.20, 0.15),
                    panel(.clock, 0.42, 0.04, 0.16, 0.10),
                    panel(.notes, 0.72, 0.04, 0.24, 0.50),
                    panel(.todo, 0.04, 0.56, 0.22, 0.36),
                ]),
                themeRef: "apple",
                features: workFeatures,
                isBuiltIn: true,
                key: "kitchen"
            ),
        ]
    }

    /// 机で使うプリセット：音声案内なし・移動中の省略なし（位置情報を使わない）
    static let workFeatures = FeatureToggles(voiceGuidance: false, reduceWhileMoving: false)

    /// デスクワーク：中央は空けて（実際の画面や手元が見えるように）、左右に並べる
    static func deskPanels() -> [HUDPanel] {
        [
            panel(.focusTimer, 0.04, 0.04, 0.18, 0.13),
            panel(.todo, 0.04, 0.20, 0.22, 0.34),
            panel(.clock, 0.82, 0.04, 0.14, 0.09),
            panel(.calendar, 0.74, 0.16, 0.22, 0.28),
            panel(.notes, 0.74, 0.47, 0.22, 0.36),
            panel(.notifications, 0.33, 0.87, 0.34, 0.09),
            panel(.battery, 0.04, 0.88, 0.11, 0.07),
        ]
    }

    /// 以前の「デスクワーク」（時計・通知・電池だけ）のまま変えていなければ true。新しい配置に入れ替えてよい。
    public static func isLegacyDeskLayout(_ layout: HUDLayout) -> Bool {
        layout.panels.count == 3 && Set(layout.panels.map(\.widget)) == [.clock, .notifications, .battery]
    }

    /// プリセットの短い説明（選ぶ画面に出す）
    public static func presetDescription(key: String?) -> String {
        switch key {
        case "walkNav": return "曲がり角・到着時刻・地図"
        case "travel": return "天気・方位・地図で街歩き"
        case "daily": return "時計・天気・通知"
        case "info": return "天気や端末の情報を一覧"
        case "desk": return "やること・予定・メモ・集中タイマー"
        case "minimal": return "時計と曲がり角だけ"
        case "custom": return "自由に作るための白紙"
        case "browser": return "ウェブページを大きく表示"
        case "presentation": return "台本・タイマー・メモ"
        case "focus": return "ポモドーロで集中"
        case "workout": return "心拍・速度・距離・歩数"
        case "kitchen": return "タイマーとレシピのメモ"
        default: return "自分で作ったプリセット"
        }
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
        "browser": ["ブラウザ", "ウェブ", "ネット閲覧"],
        "presentation": ["発表", "プレゼン", "会議", "スピーチ"],
        "focus": ["集中", "勉強", "読書"],
        "workout": ["運動", "ランニング", "ワークアウト", "トレーニング", "ジョギング"],
        "kitchen": ["料理", "キッチン", "家事"],
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
