import Foundation

public enum ZoomDirection: String, Codable, Sendable { case zoomIn, zoomOut }
public enum AdjustDirection: String, Codable, Sendable { case up, down }
public enum MoveDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right

    public var displayName: String {
        switch self {
        case .up: return "上"
        case .down: return "下"
        case .left: return "左"
        case .right: return "右"
        }
    }
}

public enum StatusTopic: String, Codable, CaseIterable, Sendable {
    case time, date, battery, speed, eta, remainingDistance, weather, location, heading

    public var displayName: String {
        switch self {
        case .time: return "時刻"
        case .date: return "日付"
        case .battery: return "バッテリー"
        case .speed: return "速度"
        case .eta: return "到着予定"
        case .remainingDistance: return "残り距離"
        case .weather: return "天気"
        case .location: return "現在地"
        case .heading: return "方角"
        }
    }
}

public enum AppScreen: String, Codable, CaseIterable, Sendable, Identifiable {
    case home, hud, hudEditor, navigation, vision, assistant, settings, history, weather, scan3D, work

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .home: return "ホーム"
        case .hud: return "HUD"
        case .hudEditor: return "HUD編集"
        case .navigation: return "ナビ"
        case .vision: return "ビジョン"
        case .assistant: return "アシスタント"
        case .settings: return "設定"
        case .history: return "履歴"
        case .weather: return "天気"
        case .scan3D: return "3Dスキャン"
        case .work: return "ワーク"
        }
    }
}

public enum NearbyCategory: String, Codable, CaseIterable, Sendable {
    case convenienceStore, restaurant, cafe, station, busStop, parking, restroom, hospital, pharmacy, sightseeing, publicFacility, gasStation

    public var displayName: String {
        switch self {
        case .convenienceStore: return "コンビニ"
        case .restaurant: return "飲食店"
        case .cafe: return "カフェ"
        case .station: return "駅"
        case .busStop: return "バス停"
        case .parking: return "駐車場"
        case .restroom: return "トイレ"
        case .hospital: return "病院"
        case .pharmacy: return "薬局"
        case .sightseeing: return "観光地"
        case .publicFacility: return "公共施設"
        case .gasStation: return "ガソリンスタンド"
        }
    }

    public var systemImage: String {
        switch self {
        case .convenienceStore: return "bag"
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .station: return "tram"
        case .busStop: return "bus"
        case .parking: return "parkingsign"
        case .restroom: return "toilet"
        case .hospital: return "cross.case"
        case .pharmacy: return "pills"
        case .sightseeing: return "camera"
        case .publicFacility: return "building.columns"
        case .gasStation: return "fuelpump"
        }
    }

    /// 検索語（MapKit の自然言語検索に渡す）
    public var searchQuery: String {
        switch self {
        case .convenienceStore: return "コンビニ"
        case .restaurant: return "レストラン"
        case .cafe: return "カフェ"
        case .station: return "駅"
        case .busStop: return "バス停"
        case .parking: return "駐車場"
        case .restroom: return "トイレ"
        case .hospital: return "病院"
        case .pharmacy: return "薬局"
        case .sightseeing: return "観光"
        case .publicFacility: return "役所"
        case .gasStation: return "ガソリンスタンド"
        }
    }

    public var aliases: [String] {
        switch self {
        case .convenienceStore: return ["コンビニ", "こんびに", "コンビニエンスストア"]
        case .restaurant: return ["飲食店", "レストラン", "ご飯", "ごはん", "食事", "ランチ"]
        case .cafe: return ["カフェ", "喫茶", "コーヒー"]
        case .station: return ["駅", "えき"]
        case .busStop: return ["バス停", "ばすてい"]
        case .parking: return ["駐車場", "パーキング"]
        case .restroom: return ["トイレ", "といれ", "お手洗い", "化粧室"]
        case .hospital: return ["病院", "びょういん", "クリニック"]
        case .pharmacy: return ["薬局", "ドラッグストア", "くすり"]
        case .sightseeing: return ["観光地", "観光", "名所"]
        case .publicFacility: return ["公共施設", "役所", "区役所", "市役所", "図書館"]
        case .gasStation: return ["ガソリンスタンド", "ガソスタ", "給油"]
        }
    }
}

/// アプリの操作。UIボタン・音声コマンド・ショートカットは全てこれを発行する。
public enum AppCommand: Hashable, Sendable {
    case setBackground(BackgroundMode)
    case toggleBackground
    case applyPreset(key: String)
    case applyTheme(key: String)
    case showWidget(WidgetKind)
    case hideWidget(WidgetKind)
    case mapZoom(ZoomDirection)
    case setMap3D(Bool)
    case startNavigation
    case stopNavigation
    case navigate(to: String)
    case search(String)
    case searchNearby(NearbyCategory)
    case setVoiceGuidance(Bool)
    case setDetection(Bool)
    case setHazardAlerts(Bool)
    case status(StatusTopic)
    case startHUD
    case stopHUD
    case open(AppScreen)
    case cameraZoom(ZoomDirection)
    case cameraExposure(AdjustDirection)
    case repeatGuidance
    case autoArrange
    /// HUD 全体の大きさ
    case adjustHUDScale(AdjustDirection)
    /// HUD 全体の位置
    case moveHUD(MoveDirection)
    /// 文字の大きさ（最小文字サイズとテーマの倍率）
    case adjustTextSize(AdjustDirection)
    /// HUD の明るさ
    case adjustBrightness(AdjustDirection)
    case setNightDim(Bool)
    case setStereo3D(Bool)
    /// 次（+1）／前（-1）のプリセット
    case cyclePreset(Int)
    case nextTheme
    case connectHeartRate
    case syncNow
    case setRecording(Bool)
    /// 今の頭の向きを正面にする
    case recenterHead
    /// HUD を空間に固定する（頭の動き）
    case setHeadLock(Bool)
    /// 下を見たときだけ詳しく表示する
    case setGlanceMode(Bool)
    /// 距離の推定（LiDAR・2 つのカメラ・AI）
    case setDepth(Bool)
    /// 正面の物までの距離を読み上げる
    case measureDistance
    // ワーク（デスクワーク・勉強・発表）
    /// 集中タイマー（ポモドーロ）
    case setFocus(Bool)
    /// 集中タイマーの今の区切りを飛ばす
    case skipFocus
    /// カウントダウンのタイマー（秒）
    case startTimer(seconds: Int)
    case stopTimer
    case setStopwatch(Bool)
    case addTodo(String)
    /// やることを終わりにする（空文字ならいちばん上）
    case completeTodo(String)
    /// メモに 1 行足す
    case addNote(String)
    /// ブラウザで開く（アドレスか検索語）
    case openWeb(String)
    case webScroll(AdjustDirection)
    case webBack
    /// 台本（プロンプター）の再生・停止
    case setTeleprompter(Bool)
    case calculate(String)
    case cancel
    /// 定型コマンドに当てはまらない質問（AIアシスタントへ）
    case ask(String)

    public var summary: String {
        switch self {
        case .setBackground(let m): return "背景を\(m.displayName)に変更"
        case .toggleBackground: return "背景を切り替え"
        case .applyPreset(let k): return "プリセット「\(k)」を適用"
        case .applyTheme(let k): return "テーマ「\(k)」を適用"
        case .showWidget(let w): return "\(w.displayName)を表示"
        case .hideWidget(let w): return "\(w.displayName)を非表示"
        case .mapZoom(let d): return d == .zoomIn ? "地図を拡大" : "地図を縮小"
        case .setMap3D(let on): return on ? "地図を3D表示" : "地図を2D表示"
        case .startNavigation: return "ナビを開始"
        case .stopNavigation: return "ナビを終了"
        case .navigate(let q): return "「\(q)」へのナビ"
        case .search(let q): return "「\(q)」を検索"
        case .searchNearby(let c): return "近くの\(c.displayName)を検索"
        case .setVoiceGuidance(let on): return on ? "音声案内をオン" : "音声案内をオフ"
        case .setDetection(let on): return on ? "物体認識をオン" : "物体認識をオフ"
        case .setHazardAlerts(let on): return on ? "危険検知をオン" : "危険検知をオフ"
        case .status(let t): return "\(t.displayName)を確認"
        case .startHUD: return "HUDを開始"
        case .stopHUD: return "HUDを終了"
        case .open(let s): return "\(s.displayName)を開く"
        case .cameraZoom(let d): return d == .zoomIn ? "カメラを拡大" : "カメラを縮小"
        case .cameraExposure(let d): return d == .up ? "カメラを明るく" : "カメラを暗く"
        case .repeatGuidance: return "案内をもう一度"
        case .autoArrange: return "パネルを自動整列"
        case .adjustHUDScale(let d): return d == .up ? "HUDを大きく" : "HUDを小さく"
        case .moveHUD(let d): return "HUDを\(d.displayName)へ移動"
        case .adjustTextSize(let d): return d == .up ? "文字を大きく" : "文字を小さく"
        case .adjustBrightness(let d): return d == .up ? "HUDを明るく" : "HUDを暗く"
        case .setNightDim(let on): return on ? "夜間の減光をオン" : "夜間の減光をオフ"
        case .setStereo3D(let on): return on ? "3D表示をオン" : "3D表示をオフ"
        case .cyclePreset(let n): return n >= 0 ? "次のプリセット" : "前のプリセット"
        case .nextTheme: return "次のテーマ"
        case .connectHeartRate: return "心拍計に接続"
        case .syncNow: return "今すぐ同期"
        case .setRecording(let on): return on ? "移動の記録を開始" : "移動の記録を終了"
        case .recenterHead: return "正面を合わせる"
        case .setHeadLock(let on): return on ? "HUDを空間に固定" : "HUDの固定を解除"
        case .setGlanceMode(let on): return on ? "下を見たときだけ詳しく表示" : "常に詳しく表示"
        case .setDepth(let on): return on ? "距離の推定をオン" : "距離の推定をオフ"
        case .measureDistance: return "正面までの距離"
        case .setFocus(let on): return on ? "集中タイマーを開始" : "集中タイマーを終了"
        case .skipFocus: return "集中タイマーを次へ"
        case .startTimer(let s): return "タイマー \(HUDFormat.spokenSeconds(Double(s)))"
        case .stopTimer: return "タイマーを止める"
        case .setStopwatch(let on): return on ? "ストップウォッチを開始" : "ストップウォッチを止める"
        case .addTodo: return "やることを追加"
        case .completeTodo: return "やることを完了"
        case .addNote: return "メモに追記"
        case .openWeb(let q): return "ブラウザで「\(q)」を開く"
        case .webScroll(let d): return d == .up ? "ページを上へ" : "ページを下へ"
        case .webBack: return "前のページに戻る"
        case .setTeleprompter(let on): return on ? "台本を再生" : "台本を止める"
        case .calculate(let e): return "計算：\(e)"
        case .cancel: return "キャンセル"
        case .ask(let q): return "質問：\(q)"
        }
    }
}
