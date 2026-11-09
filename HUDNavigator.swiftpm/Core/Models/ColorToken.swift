import Foundation

/// RGBA の色（0.0〜1.0）。テーマの保存・共有のため JSON では "#RRGGBBAA" 文字列にする。
public struct ColorToken: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    /// 各チャンネルは 8bit（1/255 刻み）に揃える。JSON（16進数）との往復で値が変わらないようにするため。
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        func q(_ v: Double) -> Double { (v.clamped(to: 0...1) * 255).rounded() / 255 }
        self.red = q(red)
        self.green = q(green)
        self.blue = q(blue)
        self.alpha = q(alpha)
    }

    /// "#RGB", "#RRGGBB", "#RRGGBBAA"（# は省略可）
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        if text.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255,
                alpha: 1
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    public var hexString: String {
        func byte(_ v: Double) -> String {
            let b = Int((v * 255).rounded()).clamped(to: 0...255)
            let s = String(b, radix: 16, uppercase: true)
            return s.count == 1 ? "0" + s : s
        }
        let base = "#" + byte(red) + byte(green) + byte(blue)
        return alpha >= 0.999 ? base : base + byte(alpha)
    }

    public func withAlpha(_ value: Double) -> ColorToken {
        ColorToken(red: red, green: green, blue: blue, alpha: value)
    }

    /// 相対輝度（WCAG）。
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// コントラスト比（1〜21）。
    public func contrastRatio(with other: ColorToken) -> Double {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// VITURE（加算合成型の光学透過）での見え方の目安。
    /// 黒は透明になるため、暗い色は「薄く」しか見えない。輝度×不透明度が低いと見えにくい。
    public var glassVisibility: Double {
        let maxChannel = max(red, green, blue)
        return maxChannel * alpha
    }

    public static let black = ColorToken(red: 0, green: 0, blue: 0)
    public static let white = ColorToken(red: 1, green: 1, blue: 1)
    public static let clear = ColorToken(red: 0, green: 0, blue: 0, alpha: 0)
    public static let cyan = ColorToken(hex: "#5AE4FF")!
    public static let green = ColorToken(hex: "#5CFF8A")!
    public static let yellow = ColorToken(hex: "#FFD84A")!
    public static let orange = ColorToken(hex: "#FF9F3A")!
    public static let red = ColorToken(hex: "#FF4D4D")!
    public static let magenta = ColorToken(hex: "#FF4DF0")!
    public static let gray = ColorToken(hex: "#B8C0CC")!
}

extension ColorToken: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let color = ColorToken(hex: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid color: \(text)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}
