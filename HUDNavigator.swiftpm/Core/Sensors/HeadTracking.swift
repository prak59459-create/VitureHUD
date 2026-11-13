import Foundation

// 頭の動き（ヘッドトラッキング）。VITURE 本体のセンサーは iOS から公式には読めないため、
// 複数の「頭の向きの取り方」を用意して、どれでも同じように HUD を動かせるようにする。

/// 頭の向きを取る方法
public enum HeadTrackingSource: String, Codable, CaseIterable, Sendable {
    case off
    /// AirPods（Pro・第3世代以降・Max）の加速度・ジャイロ
    case airPods
    /// グラスに付けた Bluetooth の動きセンサー（WitMotion WT901BLE など・自作 ESP32 も可）
    case bleSensor
    /// VITURE 本体の USB センサーを直接読む（実験・iOS の制限で動かない可能性が高い）
    case glassesUSB
    /// VITURE の公式アクセサリー（USB-C XR 充電アダプターなど）を、公開されている API だけで読む
    case glassesAccessory
    /// 端末の前面カメラで顔の向きを推定（机に置いて使うとき）
    case frontCamera
    /// 端末そのものの向き（動作確認用・端末を頭に固定する場合）
    case device

    public var displayName: String {
        switch self {
        case .off: return "使わない"
        case .airPods: return "AirPods"
        case .bleSensor: return "Bluetooth の動きセンサー"
        case .glassesUSB: return "VITURE 本体（USB・実験）"
        case .glassesAccessory: return "VITURE 公式アダプター（公開 API）"
        case .frontCamera: return "前面カメラ（顔の向き）"
        case .device: return "端末の向き"
        }
    }

    public var detail: String {
        switch self {
        case .off: return "頭の動きを使いません。"
        case .airPods: return "AirPods の中の加速度センサー・ジャイロで頭の向きを取ります。いちばん手軽です。"
        case .bleSensor: return "グラスのつるに小さな Bluetooth センサー（WitMotion WT901BLE など、または自作の ESP32）を付けて、グラスそのものの向きを取ります。"
        case .glassesUSB: return "VITURE 本体のセンサーを USB で直接読みます。iOS は一般のアプリに USB 機器の直接操作を許可していないため、動かない可能性が高い実験機能です（結果を診断に表示します）。"
        case .glassesAccessory: return "VITURE の公式アクセサリー（USB-C XR 充電アダプターなど）が iOS の公開 API（アクセサリー通信・MIDI など）で見えるかを調べ、頭の向きのデータが届けば使います。機器には何も送らず、非公開の API も使いません。見えた内容は診断に表示します。"
        case .frontCamera: return "端末を顔の前に置き、前面カメラで顔の向きを推定します。背面カメラ（カメラ背景・物体認識）とは同時に使えません。"
        case .device: return "端末そのものの傾きを使います。動作確認や、端末を頭に固定する場合に。"
        }
    }
}

/// 頭のジェスチャーで行う操作
public enum HeadGestureAction: String, Codable, CaseIterable, Sendable {
    case none
    case acceptSuggestion
    case dismissAlerts
    case repeatGuidance
    case nextPreset
    case previousPreset
    case toggleBackground
    case recenter
    case startVoice

    public var displayName: String {
        switch self {
        case .none: return "何もしない"
        case .acceptSuggestion: return "提案を実行"
        case .dismissAlerts: return "通知を消す"
        case .repeatGuidance: return "案内をもう一度"
        case .nextPreset: return "次のプリセット"
        case .previousPreset: return "前のプリセット"
        case .toggleBackground: return "背景を切り替え"
        case .recenter: return "正面を合わせる"
        case .startVoice: return "話しかける"
        }
    }
}

public struct HeadTrackingSettings: Codable, Hashable, Sendable {
    public var source: HeadTrackingSource = .off
    /// HUD を空間に固定する（頭を動かすと HUD が逆に動く）
    public var headLock: Bool = false
    /// 1度あたりのずらし量（1080p 換算 px）
    public var strength: Double = 40
    /// 頭を傾けたとき HUD を逆に回して水平を保つ
    public var compensatesRoll: Bool = false
    /// なめらかさ（0 = そのまま、0.9 = かなりなめらか）
    public var smoothing: Double = 0.6
    public var invertYaw: Bool = false
    public var invertPitch: Bool = false
    public var invertRoll: Bool = false
    /// センサーの付け方で上下と傾きが入れ替わる場合
    public var swapPitchRoll: Bool = false
    /// うなずき・首振り・首かしげで操作する
    public var gesturesEnabled: Bool = false
    public var nodAction: HeadGestureAction = .acceptSuggestion
    public var shakeAction: HeadGestureAction = .dismissAlerts
    public var tiltLeftAction: HeadGestureAction = .previousPreset
    public var tiltRightAction: HeadGestureAction = .nextPreset
    /// 下を見たときだけ詳しく表示する（ふだんは最小限）
    public var glanceMode: Bool = false
    /// 下を向いたと判断する角度（度）
    public var glanceAngle: Double = 15
    /// 前回つないだ Bluetooth センサー
    public var rememberedSensorID: String? = nil
    public var rememberedSensorName: String? = nil
    public init() {}

    public func action(for gesture: HeadGesture) -> HeadGestureAction {
        switch gesture {
        case .nod: return nodAction
        case .shake: return shakeAction
        case .tiltLeft: return tiltLeftAction
        case .tiltRight: return tiltRightAction
        }
    }

    /// センサーの付け方に合わせて向きを入れ替える・反転する
    public func adjusted(_ pose: HeadPose) -> HeadPose {
        var p = pose
        if swapPitchRoll { let t = p.pitch; p.pitch = p.roll; p.roll = t }
        if invertYaw { p.yaw = -p.yaw }
        if invertPitch { p.pitch = -p.pitch }
        if invertRoll { p.roll = -p.roll }
        return p
    }
}

/// 頭の向き（度）。yaw：右を向くとプラス、pitch：上を向くとプラス、roll：右に傾けるとプラス。
public struct HeadPose: Codable, Hashable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public static let zero = HeadPose(yaw: 0, pitch: 0, roll: 0)

    /// -180〜180 度に正規化
    public static func normalize(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a > 180 { a -= 360 }
        if a <= -180 { a += 360 }
        return a
    }

    /// 基準の向きからのずれ
    public func relative(to reference: HeadPose) -> HeadPose {
        HeadPose(
            yaw: Self.normalize(yaw - reference.yaw),
            pitch: Self.normalize(pitch - reference.pitch),
            roll: Self.normalize(roll - reference.roll)
        )
    }
}

/// 生の向き → 基準からのずれ → なめらかに
public struct HeadPoseFilter: Sendable {
    public private(set) var reference: HeadPose?
    public private(set) var smoothed: HeadPose?
    public private(set) var lastRaw: HeadPose?

    public init() {}

    /// 次の値を正面にする
    public mutating func recenter() {
        reference = lastRaw
        smoothed = lastRaw == nil ? nil : .zero
    }

    public mutating func reset() {
        reference = nil
        smoothed = nil
        lastRaw = nil
    }

    /// raw はセンサーの値（設定の反転などは適用済み）。戻り値は正面からのずれ。
    public mutating func update(raw: HeadPose, smoothing: Double) -> HeadPose {
        lastRaw = raw
        if reference == nil { reference = raw }
        let rel = raw.relative(to: reference ?? raw)
        let a = smoothing.clamped(to: 0...0.95)
        guard let s = smoothed else {
            smoothed = rel
            return rel
        }
        let next = HeadPose(
            yaw: HeadPose.normalize(s.yaw + (1 - a) * HeadPose.normalize(rel.yaw - s.yaw)),
            pitch: s.pitch + (1 - a) * (rel.pitch - s.pitch),
            roll: HeadPose.normalize(s.roll + (1 - a) * HeadPose.normalize(rel.roll - s.roll))
        )
        smoothed = next
        return next
    }
}

/// HUD を空間に固定するためのずらし量
public enum HeadLock {
    /// 右を向くと HUD は左へ、上を向くと HUD は下へ。画面の limit 倍までに制限。
    public static func offset(for pose: HeadPose, pixelsPerDegree: Double, width: Double, height: Double, limit: Double = 0.6) -> (x: Double, y: Double) {
        let x = (-pose.yaw * pixelsPerDegree).clamped(to: -width * limit...width * limit)
        let y = (pose.pitch * pixelsPerDegree).clamped(to: -height * limit...height * limit)
        return (x, y)
    }
}

public enum HeadGesture: String, Codable, CaseIterable, Sendable {
    case nod, shake, tiltLeft, tiltRight

    public var displayName: String {
        switch self {
        case .nod: return "うなずく"
        case .shake: return "首を横に振る"
        case .tiltLeft: return "首を左にかしげる"
        case .tiltRight: return "首を右にかしげる"
        }
    }
}

/// うなずき（縦に下→上）・首振り（横に3回以上の往復）・首かしげ（傾けたまま0.5秒）を見つける
public struct HeadGestureDetector: Sendable {
    public struct Sample: Sendable {
        public var time: TimeInterval
        public var pose: HeadPose
        public init(time: TimeInterval, pose: HeadPose) {
            self.time = time
            self.pose = pose
        }
    }

    public var nodThreshold: Double = 12
    public var shakeThreshold: Double = 12
    public var tiltThreshold: Double = 20
    public var tiltHold: TimeInterval = 0.5
    public var window: TimeInterval = 1.3
    public var cooldown: TimeInterval = 1.2

    private var samples: [Sample] = []
    private var lastGesture: TimeInterval = -.infinity

    public init() {}

    public mutating func reset() {
        samples.removeAll()
    }

    public mutating func add(_ pose: HeadPose, at time: TimeInterval) -> HeadGesture? {
        samples.append(Sample(time: time, pose: pose))
        samples.removeAll { time - $0.time > window }
        guard time - lastGesture >= cooldown, samples.count >= 4 else { return nil }

        let yaws = samples.map(\.pose.yaw)
        let pitches = samples.map(\.pose.pitch)
        let yawSwings = Self.swings(yaws, threshold: shakeThreshold)
        let pitchSwings = Self.swings(pitches, threshold: nodThreshold)

        var found: HeadGesture?
        if yawSwings.count >= 3 && pitchSwings.count < 2 {
            found = .shake
        } else if pitchSwings.count >= 2 && pitchSwings[0] < 0 && pitchSwings[1] > 0 && yawSwings.count < 2 {
            // 下へ動いてから上へ戻る
            found = .nod
        } else {
            let recent = samples.filter { time - $0.time <= tiltHold }
            if let first = recent.first, time - first.time >= tiltHold * 0.8, recent.count >= 3 {
                if recent.allSatisfy({ $0.pose.roll >= tiltThreshold }) { found = .tiltRight }
                if recent.allSatisfy({ $0.pose.roll <= -tiltThreshold }) { found = .tiltLeft }
            }
        }
        if let found {
            lastGesture = time
            samples.removeAll()
            return found
        }
        return nil
    }

    /// 値がしきい値以上動いて向きを変えた回数（+1 は増える方向、-1 は減る方向）
    static func swings(_ values: [Double], threshold: Double) -> [Int] {
        guard var hi = values.first else { return [] }
        var lo = hi
        var ext = hi
        var dir = 0
        var result: [Int] = []
        for v in values.dropFirst() {
            switch dir {
            case 0:
                hi = max(hi, v)
                lo = min(lo, v)
                if v - lo >= threshold { dir = 1; result.append(1); ext = v }
                else if hi - v >= threshold { dir = -1; result.append(-1); ext = v }
            case 1:
                if v > ext { ext = v } else if ext - v >= threshold { dir = -1; result.append(-1); ext = v }
            default:
                if v < ext { ext = v } else if v - ext >= threshold { dir = 1; result.append(1); ext = v }
            }
        }
        return result
    }
}

/// 下を見たかどうか（行ったり来たりしないよう、戻るときは 5 度の余裕）
public struct GlanceDetector: Sendable {
    public var angle: Double
    public var hysteresis: Double = 5
    public private(set) var isGlancing = false

    public init(angle: Double = 15) {
        self.angle = angle
    }

    @discardableResult
    public mutating func update(pitch: Double) -> Bool {
        if isGlancing {
            if pitch > -angle + hysteresis { isGlancing = false }
        } else if pitch <= -angle {
            isGlancing = true
        }
        return isGlancing
    }

    /// ふだん（下を見ていないとき）に表示するウィジェット
    public static let essentialWidgets: Set<WidgetKind> = [.clock, .nextTurn, .notifications]
}
