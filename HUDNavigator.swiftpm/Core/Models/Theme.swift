import Foundation

public enum HUDFontDesign: String, Codable, CaseIterable, Sendable {
    case standard, rounded, monospaced, serif

    public var displayName: String {
        switch self {
        case .standard: return "標準"
        case .rounded: return "丸ゴシック"
        case .monospaced: return "等幅"
        case .serif: return "明朝"
        }
    }
}

public enum HUDFontWeight: String, Codable, CaseIterable, Sendable {
    case light, regular, medium, semibold, bold, heavy

    public var displayName: String {
        switch self {
        case .light: return "細"
        case .regular: return "標準"
        case .medium: return "中"
        case .semibold: return "やや太"
        case .bold: return "太"
        case .heavy: return "極太"
        }
    }
}

public enum HUDAnimationStyle: String, Codable, CaseIterable, Sendable {
    case none, subtle, smooth, pulse

    public var displayName: String {
        switch self {
        case .none: return "なし"
        case .subtle: return "控えめ"
        case .smooth: return "なめらか"
        case .pulse: return "点滅（警告向け）"
        }
    }
}

/// パネルの見た目。
public struct PanelStyle: Codable, Hashable, Sendable {
    public var textColor: ColorToken
    public var secondaryTextColor: ColorToken
    public var accentColor: ColorToken
    public var backgroundColor: ColorToken
    /// パネル背景の不透明度。VITURE では背景はほぼ見えないため、既定は低め。
    public var backgroundOpacity: Double
    public var fontDesign: HUDFontDesign
    /// パネル高さに対する文字サイズの倍率（1.0 が標準）。
    public var fontScale: Double
    public var fontWeight: HUDFontWeight
    public var borderWidth: Double
    public var borderColor: ColorToken
    public var cornerRadius: Double
    public var shadowRadius: Double
    public var glowRadius: Double
    public var glowColor: ColorToken
    public var animation: HUDAnimationStyle

    public init(
        textColor: ColorToken = .white,
        secondaryTextColor: ColorToken = .gray,
        accentColor: ColorToken = .cyan,
        backgroundColor: ColorToken = .black,
        backgroundOpacity: Double = 0.35,
        fontDesign: HUDFontDesign = .rounded,
        fontScale: Double = 1.0,
        fontWeight: HUDFontWeight = .semibold,
        borderWidth: Double = 1,
        borderColor: ColorToken = ColorToken.white.withAlpha(0.25),
        cornerRadius: Double = 16,
        shadowRadius: Double = 0,
        glowRadius: Double = 0,
        glowColor: ColorToken = .cyan,
        animation: HUDAnimationStyle = .subtle
    ) {
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.backgroundOpacity = backgroundOpacity
        self.fontDesign = fontDesign
        self.fontScale = fontScale
        self.fontWeight = fontWeight
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.glowRadius = glowRadius
        self.glowColor = glowColor
        self.animation = animation
    }

    enum CodingKeys: String, CodingKey {
        case textColor, secondaryTextColor, accentColor, backgroundColor, backgroundOpacity
        case fontDesign, fontScale, fontWeight, borderWidth, borderColor, cornerRadius
        case shadowRadius, glowRadius, glowColor, animation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PanelStyle()
        textColor = c.value(.textColor, default: d.textColor)
        secondaryTextColor = c.value(.secondaryTextColor, default: d.secondaryTextColor)
        accentColor = c.value(.accentColor, default: d.accentColor)
        backgroundColor = c.value(.backgroundColor, default: d.backgroundColor)
        backgroundOpacity = c.value(.backgroundOpacity, default: d.backgroundOpacity)
        fontDesign = c.value(.fontDesign, default: d.fontDesign)
        fontScale = c.value(.fontScale, default: d.fontScale)
        fontWeight = c.value(.fontWeight, default: d.fontWeight)
        borderWidth = c.value(.borderWidth, default: d.borderWidth)
        borderColor = c.value(.borderColor, default: d.borderColor)
        cornerRadius = c.value(.cornerRadius, default: d.cornerRadius)
        shadowRadius = c.value(.shadowRadius, default: d.shadowRadius)
        glowRadius = c.value(.glowRadius, default: d.glowRadius)
        glowColor = c.value(.glowColor, default: d.glowColor)
        animation = c.value(.animation, default: d.animation)
    }
}

/// パネルごとの個別スタイル（nil の項目はテーマに従う）。
public struct PanelStyleOverride: Codable, Hashable, Sendable {
    public var textColor: ColorToken?
    public var secondaryTextColor: ColorToken?
    public var accentColor: ColorToken?
    public var backgroundColor: ColorToken?
    public var backgroundOpacity: Double?
    public var fontDesign: HUDFontDesign?
    public var fontScale: Double?
    public var fontWeight: HUDFontWeight?
    public var borderWidth: Double?
    public var borderColor: ColorToken?
    public var cornerRadius: Double?
    public var shadowRadius: Double?
    public var glowRadius: Double?
    public var glowColor: ColorToken?
    public var animation: HUDAnimationStyle?

    public init() {}

    public var isEmpty: Bool { self == PanelStyleOverride() }

    public func applied(to base: PanelStyle) -> PanelStyle {
        var s = base
        if let v = textColor { s.textColor = v }
        if let v = secondaryTextColor { s.secondaryTextColor = v }
        if let v = accentColor { s.accentColor = v }
        if let v = backgroundColor { s.backgroundColor = v }
        if let v = backgroundOpacity { s.backgroundOpacity = v }
        if let v = fontDesign { s.fontDesign = v }
        if let v = fontScale { s.fontScale = v }
        if let v = fontWeight { s.fontWeight = v }
        if let v = borderWidth { s.borderWidth = v }
        if let v = borderColor { s.borderColor = v }
        if let v = cornerRadius { s.cornerRadius = v }
        if let v = shadowRadius { s.shadowRadius = v }
        if let v = glowRadius { s.glowRadius = v }
        if let v = glowColor { s.glowColor = v }
        if let v = animation { s.animation = v }
        return s
    }
}

public struct Theme: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var style: PanelStyle
    public var warningColor: ColorToken
    public var dangerColor: ColorToken
    public var isBuiltIn: Bool
    /// 組み込みテーマの識別子（音声コマンドやショートカットから指定するため）。
    public var key: String?

    public init(
        id: UUID = UUID(),
        name: String,
        style: PanelStyle,
        warningColor: ColorToken = .yellow,
        dangerColor: ColorToken = .red,
        isBuiltIn: Bool = false,
        key: String? = nil
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.warningColor = warningColor
        self.dangerColor = dangerColor
        self.isBuiltIn = isBuiltIn
        self.key = key
    }

    enum CodingKeys: String, CodingKey {
        case id, name, style, warningColor, dangerColor, isBuiltIn, key
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "テーマ")
        style = c.value(.style, default: PanelStyle())
        warningColor = c.value(.warningColor, default: .yellow)
        dangerColor = c.value(.dangerColor, default: .red)
        isBuiltIn = c.value(.isBuiltIn, default: false)
        key = c.value(.key, default: nil)
    }

    /// 複製（ユーザーテーマとして編集するため）。
    public func duplicated(name newName: String? = nil) -> Theme {
        Theme(name: newName ?? "\(name) のコピー", style: style, warningColor: warningColor, dangerColor: dangerColor)
    }

    /// グラス上で見えにくい色の組み合わせを警告する。
    public var visibilityWarnings: [String] {
        var warnings: [String] = []
        if style.textColor.glassVisibility < 0.55 {
            warnings.append("文字色が暗いため、グラス上では見えにくい可能性があります。")
        }
        if style.accentColor.glassVisibility < 0.45 {
            warnings.append("強調色が暗いため、グラス上では目立ちにくい可能性があります。")
        }
        if style.backgroundOpacity > 0.7 && style.backgroundColor.glassVisibility > 0.5 {
            warnings.append("明るい背景が不透明なため、現実の視界を大きく遮ります。")
        }
        return warnings
    }
}
