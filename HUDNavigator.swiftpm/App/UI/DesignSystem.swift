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
enum UIStyle {
    static let accent = Color(ColorToken.cyan)
    static let warning = Color(ColorToken.yellow)
    static let danger = Color(ColorToken.red)
    static let cardBackground = Color(.secondarySystemBackground)
}

struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Label(title, systemImage: systemImage ?? "circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(UIStyle.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 「実験機能・安全装置ではない」などの注意表示。
struct NoticeBanner: View {
    var text: String
    var systemImage: String = "exclamationmark.triangle"
    var color: Color = UIStyle.warning

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
