import Foundation

/// 画像内の線分（正規化座標・左上原点）
public struct LineSegment: Codable, Hashable, Sendable {
    public var start: HUDPoint
    public var end: HUDPoint

    public init(start: HUDPoint, end: HUDPoint) {
        self.start = start
        self.end = end
    }

    public var length: Double { hypot(end.x - start.x, end.y - start.y) }
    /// 水平からの角度（0〜90度）
    public var angleFromHorizontal: Double {
        let a = atan2(abs(end.y - start.y), abs(end.x - start.x)) * 180 / .pi
        return a
    }
    /// 画面の左側にあって右上へ伸びる（/）なら -1、右側で左上へ伸びる（\）なら +1
    public var side: Int {
        let low = start.y > end.y ? start : end
        let high = start.y > end.y ? end : start
        return high.x > low.x ? -1 : 1
    }
}

/// 路面の線（白線・車線）の候補を、輪郭の点列から選ぶ（実験機能）。
/// 手持ち・胸の位置のカメラでは精度が出にくいため、目安として表示するだけ。
public enum LaneLineFilter {
    public struct Configuration: Sendable {
        /// 画像の下側（この比率より下）だけを見る
        public var horizonY: Double = 0.45
        public var minLength: Double = 0.12
        public var minAngle: Double = 18
        public var maxAngle: Double = 78
        /// 点列のまっすぐさ（端点間距離 / 経路長）
        public var minStraightness: Double = 0.9
        public var maxLines: Int = 4
        public init() {}
    }

    /// 点列（輪郭）→ まっすぐな線分ならその端点
    public static func segment(from points: [HUDPoint], config: Configuration = Configuration()) -> LineSegment? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        var pathLength = 0.0
        for i in 1..<points.count {
            pathLength += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        let seg = LineSegment(start: first, end: last)
        guard pathLength > 0, seg.length / pathLength >= config.minStraightness else { return nil }
        return seg
    }

    public static func lanes(from contours: [[HUDPoint]], config: Configuration = Configuration()) -> [LineSegment] {
        let candidates = contours.compactMap { segment(from: $0, config: config) }.filter { s in
            min(s.start.y, s.end.y) >= config.horizonY - 0.05
                && max(s.start.y, s.end.y) >= config.horizonY + 0.1
                && s.length >= config.minLength
                && s.angleFromHorizontal >= config.minAngle
                && s.angleFromHorizontal <= config.maxAngle
        }
        // 車線は左右で傾きが逆：左側の線は「/」、右側の線は「\」が自然
        let plausible = candidates.filter { s in
            let midX = (s.start.x + s.end.x) / 2
            return (midX < 0.5 && s.side == -1) || (midX >= 0.5 && s.side == 1)
        }
        return Array(plausible.sorted { $0.length > $1.length }.prefix(config.maxLines))
    }
}

/// 標識・看板の文字から、標識の種類を推定する（実験機能）。
public enum SignTextClassifier {
    public struct SignReading: Hashable, Sendable {
        public var kind: String
        public var text: String
        public var isImportant: Bool
    }

    static let rules: [(keywords: [String], kind: String, important: Bool)] = [
        (["止まれ", "とまれ", "STOP"], "一時停止", true),
        (["徐行"], "徐行", true),
        (["通行止", "通行禁止", "進入禁止"], "通行止め", true),
        (["一方通行"], "一方通行", false),
        (["歩行者専用", "歩行者天国"], "歩行者専用", false),
        (["自転車専用", "自転車通行"], "自転車", false),
        (["駐車禁止", "駐停車禁止"], "駐車禁止", false),
        (["横断歩道"], "横断歩道", false),
        (["スクールゾーン", "通学路"], "通学路", true),
        (["工事中", "工事"], "工事中", true),
        (["出口", "EXIT"], "出口", false),
        (["非常口"], "非常口", false),
        (["トイレ", "WC", "TOILET"], "トイレ", false),
        (["改札", "のりば", "乗り場"], "駅の案内", false),
    ]

    public static func classify(_ text: String) -> SignReading? {
        let t = text.uppercased().replacingOccurrences(of: " ", with: "")
        for rule in rules where rule.keywords.contains(where: { t.contains($0.uppercased()) }) {
            return SignReading(kind: rule.kind, text: text, isImportant: rule.important)
        }
        // 「30」「40」など速度表示らしい数字（単独の 10〜120 の 10 の倍数）
        if let n = Int(t), n >= 10, n <= 120, n % 10 == 0 {
            return SignReading(kind: "最高速度 \(n)km/h（推定）", text: text, isImportant: false)
        }
        return nil
    }
}
