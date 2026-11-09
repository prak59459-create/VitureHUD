import Foundation

public enum DetectionLabel: String, Codable, CaseIterable, Sendable {
    case person, bicycle, car, motorcycle, bus, truck, train, dog, cat, animal, trafficLight, stopSign, text, other

    public var displayName: String {
        switch self {
        case .person: return "歩行者"
        case .bicycle: return "自転車"
        case .car: return "自動車"
        case .motorcycle: return "バイク"
        case .bus: return "バス"
        case .truck: return "トラック"
        case .train: return "電車"
        case .dog: return "犬"
        case .cat: return "猫"
        case .animal: return "動物"
        case .trafficLight: return "信号"
        case .stopSign: return "標識"
        case .text: return "文字"
        case .other: return "物体"
        }
    }

    /// 危険度評価で「動く物体」として扱うか
    public var isMovingHazard: Bool {
        switch self {
        case .person, .bicycle, .car, .motorcycle, .bus, .truck, .train, .dog, .cat, .animal: return true
        default: return false
        }
    }

    /// 危険度の重み（大きい・速い物体ほど大きい）
    public var hazardWeight: Double {
        switch self {
        case .car, .bus, .truck, .train: return 1.0
        case .motorcycle: return 0.95
        case .bicycle: return 0.8
        case .person: return 0.5
        case .dog, .cat, .animal: return 0.4
        default: return 0.2
        }
    }

    /// 距離の目安を出すための代表的な高さ（m）。
    public var typicalHeight: Double? {
        switch self {
        case .person: return 1.65
        case .bicycle: return 1.1
        case .car: return 1.5
        case .motorcycle: return 1.2
        case .bus: return 3.0
        case .truck: return 3.0
        case .dog: return 0.5
        case .cat: return 0.3
        default: return nil
        }
    }

    /// Core ML（COCO 系など）のラベル名や Vision の識別子から変換する。
    public static func from(identifier: String) -> DetectionLabel {
        let id = identifier.lowercased()
        switch id {
        case "person", "human", "pedestrian", "people": return .person
        case "bicycle", "bike", "cyclist": return .bicycle
        case "car", "automobile", "vehicle": return .car
        case "motorcycle", "motorbike", "scooter": return .motorcycle
        case "bus": return .bus
        case "truck", "lorry": return .truck
        case "train", "tram": return .train
        case "dog": return .dog
        case "cat": return .cat
        case "bird", "horse", "sheep", "cow", "bear", "animal": return .animal
        case "traffic light", "traffic_light", "trafficlight": return .trafficLight
        case "stop sign", "stop_sign", "stopsign", "sign", "traffic sign": return .stopSign
        default: return .other
        }
    }
}

public struct Detection: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: DetectionLabel
    /// 元の識別子（モデルのラベル名）
    public var rawLabel: String
    public var confidence: Double
    /// 画像内の位置（正規化、左上原点）
    public var box: NormalizedRect
    public var timestamp: Date
    /// 追跡ID（ObjectTracker が付与）
    public var trackID: Int?

    public init(id: UUID = UUID(), label: DetectionLabel, rawLabel: String? = nil, confidence: Double, box: NormalizedRect, timestamp: Date, trackID: Int? = nil) {
        self.id = id
        self.label = label
        self.rawLabel = rawLabel ?? label.rawValue
        self.confidence = confidence
        self.box = box
        self.timestamp = timestamp
        self.trackID = trackID
    }

    /// 距離の目安（m）。カメラの縦画角と代表的な高さから概算するだけで、正確ではない。
    /// 枠が画面端で切れている場合は推定しない。
    public func approximateDistance(verticalFieldOfViewDegrees: Double) -> Double? {
        guard let h = label.typicalHeight, box.height > 0.02, box.minY > 0.01, box.maxY < 0.99 else { return nil }
        let fov = verticalFieldOfViewDegrees * .pi / 180
        let d = h / (2 * tan(fov / 2) * box.height)
        return d.isFinite && d > 0 && d < 200 ? d : nil
    }
}
