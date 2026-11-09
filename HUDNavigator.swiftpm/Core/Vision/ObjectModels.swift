import Foundation

/// アプリに最初から入っている物体検出モデル（Apple 配布の Core ML 版 YOLOv3。YOLO License＝パブリックドメイン）
public enum BundledObjectModel: String, Codable, CaseIterable, Sendable {
    /// 速い（35MB）
    case yolov3Tiny = "YOLOv3Tiny"
    /// 精度が高い（62MB・8ビット量子化）
    case yolov3 = "YOLOv3Int8LUT"

    public var displayName: String {
        switch self {
        case .yolov3Tiny: return "YOLOv3 Tiny（速い）"
        case .yolov3: return "YOLOv3（高精度）"
        }
    }

    public var detail: String {
        switch self {
        case .yolov3Tiny: return "人・自転車・車・バイク・バス・トラック・信号・一時停止標識・犬・猫など 80 種類。電池と発熱を抑えたいときに。"
        case .yolov3: return "同じ 80 種類を、より遠く・小さくても見つけやすいモデル。処理が重いので推論の回数を少なめに。"
        }
    }

    public static let credit = "YOLOv3: Joseph Redmon, Ali Farhadi（YOLO License・パブリックドメイン）。Core ML 版は Apple が配布。https://github.com/pjreddie/darknet"
}

/// 物体検出モデルのラベル（COCO の 80 種類）の日本語名
public enum ObjectLabels {
    public static let japanese: [String: String] = [
        "person": "人", "bicycle": "自転車", "car": "自動車", "motorbike": "バイク", "motorcycle": "バイク",
        "aeroplane": "飛行機", "airplane": "飛行機", "bus": "バス", "train": "電車", "truck": "トラック", "boat": "ボート",
        "traffic light": "信号", "fire hydrant": "消火栓", "stop sign": "一時停止標識", "parking meter": "パーキングメーター",
        "bench": "ベンチ", "bird": "鳥", "cat": "猫", "dog": "犬", "horse": "馬", "sheep": "羊", "cow": "牛",
        "elephant": "象", "bear": "熊", "zebra": "シマウマ", "giraffe": "キリン", "backpack": "リュック",
        "umbrella": "傘", "handbag": "ハンドバッグ", "tie": "ネクタイ", "suitcase": "スーツケース", "frisbee": "フリスビー",
        "skis": "スキー板", "snowboard": "スノーボード", "sports ball": "ボール", "kite": "凧", "baseball bat": "バット",
        "baseball glove": "グローブ", "skateboard": "スケートボード", "surfboard": "サーフボード", "tennis racket": "ラケット",
        "bottle": "ボトル", "wine glass": "ワイングラス", "cup": "カップ", "fork": "フォーク", "knife": "ナイフ",
        "spoon": "スプーン", "bowl": "ボウル", "banana": "バナナ", "apple": "りんご", "sandwich": "サンドイッチ",
        "orange": "オレンジ", "broccoli": "ブロッコリー", "carrot": "にんじん", "hot dog": "ホットドッグ", "pizza": "ピザ",
        "donut": "ドーナツ", "cake": "ケーキ", "chair": "椅子", "sofa": "ソファ", "couch": "ソファ",
        "pottedplant": "鉢植え", "potted plant": "鉢植え", "bed": "ベッド", "diningtable": "テーブル", "dining table": "テーブル",
        "toilet": "トイレ", "tvmonitor": "テレビ", "tv": "テレビ", "laptop": "ノートパソコン", "mouse": "マウス",
        "remote": "リモコン", "keyboard": "キーボード", "cell phone": "スマートフォン", "microwave": "電子レンジ",
        "oven": "オーブン", "toaster": "トースター", "sink": "流し台", "refrigerator": "冷蔵庫", "book": "本",
        "clock": "時計", "vase": "花瓶", "scissors": "はさみ", "teddy bear": "ぬいぐるみ", "hair drier": "ドライヤー",
        "toothbrush": "歯ブラシ",
    ]

    /// 表示用の名前（危険度で使う分類があればその名前、なければ日本語のラベル名）
    public static func displayName(label: DetectionLabel, raw: String) -> String {
        if label != .other { return label.displayName }
        return japanese[raw.lowercased()] ?? raw
    }
}
