import Foundation

public enum ManeuverKind: String, Codable, CaseIterable, Sendable {
    case depart, straight, slightRight, right, sharpRight, slightLeft, left, sharpLeft, uTurn, roundabout, merge, keepRight, keepLeft, arrive, unknown

    public var systemImage: String {
        switch self {
        case .depart: return "location.north.fill"
        case .straight: return "arrow.up"
        case .slightRight: return "arrow.up.right"
        case .right: return "arrow.turn.up.right"
        case .sharpRight: return "arrow.turn.right.down"
        case .slightLeft: return "arrow.up.left"
        case .left: return "arrow.turn.up.left"
        case .sharpLeft: return "arrow.turn.left.down"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout: return "arrow.triangle.turn.up.right.circle"
        case .merge: return "arrow.merge"
        case .keepRight: return "arrow.branch"
        case .keepLeft: return "arrow.branch"
        case .arrive: return "flag.checkered"
        case .unknown: return "arrow.up"
        }
    }

    public var spokenName: String {
        switch self {
        case .depart: return "出発"
        case .straight: return "直進"
        case .slightRight: return "斜め右"
        case .right: return "右折"
        case .sharpRight: return "鋭く右"
        case .slightLeft: return "斜め左"
        case .left: return "左折"
        case .sharpLeft: return "鋭く左"
        case .uTurn: return "Uターン"
        case .roundabout: return "ロータリー"
        case .merge: return "合流"
        case .keepRight: return "右方向"
        case .keepLeft: return "左方向"
        case .arrive: return "目的地"
        case .unknown: return "進行"
        }
    }

    /// 地図サービスの案内文から曲がる方向を推定する（日本語・英語）。
    public static func classify(_ instruction: String) -> ManeuverKind {
        let t = instruction.lowercased()
        func has(_ words: String...) -> Bool { words.contains { t.contains($0) } }
        if has("到着", "目的地", "arrive", "destination") { return .arrive }
        if has("uターン", "u-turn", "u turn", "make a u") { return .uTurn }
        if has("ロータリー", "環状交差点", "roundabout", "rotary") { return .roundabout }
        if has("合流", "merge") { return .merge }
        if has("鋭く右", "急な右", "sharp right") { return .sharpRight }
        if has("鋭く左", "急な左", "sharp left") { return .sharpLeft }
        if has("斜め右", "やや右", "slight right", "bear right") { return .slightRight }
        if has("斜め左", "やや左", "slight left", "bear left") { return .slightLeft }
        if has("右側を", "右車線", "keep right", "stay right") { return .keepRight }
        if has("左側を", "左車線", "keep left", "stay left") { return .keepLeft }
        if has("右折", "右に曲", "右へ曲", "turn right", "右方向") { return .right }
        if has("左折", "左に曲", "左へ曲", "turn left", "左方向") { return .left }
        if has("直進", "まっすぐ", "continue", "straight", "head") { return .straight }
        if has("出発", "start", "depart") { return .depart }
        return .unknown
    }
}

public struct NavStep: Codable, Hashable, Sendable {
    public var instruction: String
    /// この区間の距離（m）
    public var distance: Double
    /// 区間の終点（曲がる地点）
    public var endCoordinate: GeoCoordinate
    public var maneuver: ManeuverKind

    public init(instruction: String, distance: Double, endCoordinate: GeoCoordinate, maneuver: ManeuverKind? = nil) {
        self.instruction = instruction
        self.distance = distance
        self.endCoordinate = endCoordinate
        self.maneuver = maneuver ?? ManeuverKind.classify(instruction)
    }

    /// 案内文から道路名らしき部分を抜き出す（「〇〇通り」「〇〇線」など）。取れない場合は nil。
    public var roadName: String? {
        let patterns = ["通り", "街道", "大通り", "線", "道路", "号", "street", "avenue", "road"]
        let separators = CharacterSet(charactersIn: " 、。,で\u{3000}を")
        let tokens = instruction.components(separatedBy: separators).filter { !$0.isEmpty }
        for token in tokens {
            let lower = token.lowercased()
            if patterns.contains(where: { lower.hasSuffix($0) }) && token.count >= 2 && token.count <= 20 {
                // 「〇〇通りに」の「に」等は区切りで落ちている前提
                return token.replacingOccurrences(of: "に入", with: "")
            }
        }
        return nil
    }
}

public struct NavRoute: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var transport: TransportMode
    /// 総距離（m）
    public var distance: Double
    /// 所要時間（秒）
    public var expectedTravelTime: Double
    public var polyline: [GeoCoordinate]
    public var steps: [NavStep]
    public var destinationName: String
    public var advisoryNotices: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        transport: TransportMode,
        distance: Double,
        expectedTravelTime: Double,
        polyline: [GeoCoordinate],
        steps: [NavStep],
        destinationName: String,
        advisoryNotices: [String] = []
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.distance = distance
        self.expectedTravelTime = expectedTravelTime
        self.polyline = polyline
        self.steps = steps
        self.destinationName = destinationName
        self.advisoryNotices = advisoryNotices
    }

    public var destination: GeoCoordinate? { polyline.last ?? steps.last?.endCoordinate }

    /// 平均速度（m/s）。ETA の再計算に使う。
    public var averageSpeed: Double {
        guard expectedTravelTime > 0 else { return transport == .walking ? 1.3 : 10 }
        return distance / expectedTravelTime
    }
}
