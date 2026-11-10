import SwiftUI
import UIKit

extension Color {
    init(_ token: ColorToken) {
        self.init(.sRGB, red: token.red, green: token.green, blue: token.blue, opacity: token.alpha)
    }
}

extension ColorToken {
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        } else {
            self.init(red: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    var color: Color { Color(self) }
}

extension HUDFontDesign {
    var swiftUI: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .serif: return .serif
        }
    }
}

extension HUDFontWeight {
    var swiftUI: Font.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
}

extension HUDAnimationStyle {
    var animation: Animation? {
        switch self {
        case .none: return nil
        case .subtle: return .easeOut(duration: 0.2)
        case .smooth: return .smooth(duration: 0.35)
        case .pulse: return .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
        }
    }
}

/// HUDパネル内の文字サイズを決める情報。
struct HUDTypography {
    /// パネルのピクセル高さ
    var panelHeight: CGFloat
    /// キャンバスの高さ（最小文字サイズの換算用）
    var canvasHeight: CGFloat
    var style: PanelStyle
    var minimumFontPixels: Double
    /// 文字の倍率（音声コマンド「文字を大きく」・HUD 編集の設定）
    var textScale: Double = 1

    /// 主表示の文字サイズ
    var primarySize: CGFloat { size(0.46) }
    var secondarySize: CGFloat { size(0.22) }
    var iconSize: CGFloat { size(0.36) }

    func size(_ fraction: CGFloat) -> CGFloat {
        let base = panelHeight * fraction * CGFloat(style.fontScale) * CGFloat(textScale)
        let minimum = CGFloat(minimumFontPixels * textScale) * (canvasHeight / 1080) * min(1, fraction / 0.22)
        return max(base, minimum, 8)
    }

    func font(_ fraction: CGFloat, weight: Font.Weight? = nil) -> Font {
        .system(size: size(fraction), weight: weight ?? style.fontWeight.swiftUI, design: style.fontDesign.swiftUI)
    }

    var primary: Font { font(0.46) }
    var secondary: Font { font(0.22, weight: .medium) }
}

/// 操作画面（端末側）で使う共通の見た目。
/// HUD と同じ「黒＋シアン」を基調にした、暗い所でもまぶしくないデザイン。
enum UIStyle {
    static let accent = Color(ColorToken.cyan)
    static let success = Color(ColorToken.green)
    static let warning = Color(ColorToken.yellow)
    static let danger = Color(ColorToken.red)
    /// 画面の地の色（ほぼ黒・わずかに青）
    static let base = Color(red: 0.02, green: 0.027, blue: 0.04)
    static let baseRaised = Color(red: 0.043, green: 0.07, blue: 0.125)
    /// カード・タイルの面
    static let cardBackground = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let fieldBackground = Color.white.opacity(0.08)
    static let cardRadius: CGFloat = 22
    static let tileRadius: CGFloat = 18
}

/// 画面の背景：黒から濃い紺へのグラデーション＋上の方にうっすらシアンの光
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [UIStyle.base, UIStyle.baseRaised], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [UIStyle.accent.opacity(0.16), .clear], center: .init(x: 0.85, y: -0.05), startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 画面全体の背景（スクロール画面・フォーム共通）
    func appBackground() -> some View {
        scrollContentBackground(.hidden).background(AppBackground())
    }

    /// カードの面（ガラス風：薄い面＋細い縁）
    func cardSurface(radius: CGFloat = UIStyle.cardRadius, highlighted: Bool = false) -> some View {
        background(highlighted ? UIStyle.accent.opacity(0.14) : UIStyle.cardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(highlighted ? UIStyle.accent.opacity(0.6) : UIStyle.cardStroke, lineWidth: 1))
    }
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    Image(systemName: systemImage ?? "circle")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(UIStyle.accent)
                        .frame(width: 26, height: 26)
                        .background(UIStyle.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// 主要な操作のボタン（シアンの面に黒い文字）
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.subheadline : Font.headline).weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 8 : 13)
            .background(UIStyle.accent.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .shadow(color: UIStyle.accent.opacity(isEnabled ? 0.35 : 0), radius: configuration.isPressed ? 2 : 10, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 補助的な操作のボタン（薄い面にシアンの文字）
struct SecondaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font((compact ? Font.subheadline : Font.headline).weight(.medium))
            .foregroundStyle(UIStyle.accent)
            .padding(.horizontal, compact ? 14 : 18)
            .padding(.vertical, compact ? 8 : 13)
            .background(UIStyle.fieldBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(UIStyle.cardStroke, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryAction: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(compact: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryAction: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var secondaryCompact: SecondaryButtonStyle { SecondaryButtonStyle(compact: true) }
}

/// 状態を表す小さなラベル（接続中・オフ など）
struct StatusChip: View {
    var text: String
    var systemImage: String?
    var color: Color = UIStyle.accent
    var showsDot = false

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.8), radius: 4)
            }
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// 選べる丸いラベル（プリセット・カテゴリなど）
struct SelectablePill: View {
    var title: String
    var systemImage: String?
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).lineLimit(1)
        }
        .font(.subheadline.weight(isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? Color.black : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isSelected ? UIStyle.accent : UIStyle.fieldBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : UIStyle.cardStroke, lineWidth: 1))
    }
}

/// 押せるタイル（アイコン＋名前＋状態）。オンのときはシアンに光る。
struct ActionTile: View {
    var title: String
    var subtitle: String?
    var systemImage: String
    var isOn: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isOn ? Color.black : UIStyle.accent)
                    .frame(width: 38, height: 38)
                    .background(isOn ? UIStyle.accent : UIStyle.accent.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(isOn ? UIStyle.accent : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .cardSurface(radius: UIStyle.tileRadius, highlighted: isOn)
            .contentShape(RoundedRectangle(cornerRadius: UIStyle.tileRadius))
        }
        .buttonStyle(TilePressStyle())
    }
}

struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 数値の小さなタイル（電池・温度・GPS など）
struct StatTile: View {
    var title: String
    var value: String
    var detail: String?
    var systemImage: String
    var tint: Color = UIStyle.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .cardSurface(radius: UIStyle.tileRadius)
    }
}

/// 見出し（カードの外に置く小さなタイトル）
struct SectionTitle: View {
    var text: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(text).font(.title3.weight(.bold))
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action).font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 設定の一覧に使う色付きの四角いアイコン
struct SettingsIcon: View {
    var systemImage: String
    var color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 「実験機能・安全装置ではない」などの注意表示。
struct NoticeBanner: View {
    var text: String
    var systemImage: String = "exclamationmark.triangle"
    var color: Color = UIStyle.warning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage).font(.footnote.weight(.bold))
            Text(text).font(.footnote)
        }
        .foregroundStyle(color)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

/// ColorToken を編集する ColorPicker。
struct TokenColorPicker: View {
    var title: String
    @Binding var token: ColorToken
    var supportsOpacity = true

    var body: some View {
        ColorPicker(title, selection: Binding(
            get: { Color(token) },
            set: { token = ColorToken($0) }
        ), supportsOpacity: supportsOpacity)
    }
}

/// 任意の値（nil = テーマに従う）の ColorToken を編集する。
struct OptionalTokenColorPicker: View {
    var title: String
    @Binding var token: ColorToken?
    var fallback: ColorToken

    var body: some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { Color(token ?? fallback) },
                set: { token = ColorToken($0) }
            ))
            if token != nil {
                Button {
                    token = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("テーマに戻す")
            }
        }
    }
}
