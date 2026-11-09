import Foundation

public enum TestEnvironment: String, Codable, CaseIterable, Sendable {
    /// Swift Playgrounds 内で実行（iPad、回数無制限）
    case playgrounds
    /// AltStore でインストールした正式アプリ（週7回まで）
    case installedApp

    public var displayName: String {
        switch self {
        case .playgrounds: return "Swift Playgrounds"
        case .installedApp: return "正式アプリ（IPA）"
        }
    }
}

public enum CheckResult: String, Codable, CaseIterable, Sendable {
    case notRun, pass, fail, skipped

    public var displayName: String {
        switch self {
        case .notRun: return "未実施"
        case .pass: return "OK"
        case .fail: return "NG"
        case .skipped: return "スキップ"
        }
    }
}

public struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var phase: Int
    public var title: String
    public var steps: String
    public var expected: String
    /// この項目を確認できる環境
    public var environments: Set<TestEnvironment>
    /// iPhone でしか確認できない／iPad でしか確認できない など
    public var deviceNote: String?

    public init(id: String, phase: Int, title: String, steps: String, expected: String, environments: Set<TestEnvironment> = [.playgrounds, .installedApp], deviceNote: String? = nil) {
        self.id = id
        self.phase = phase
        self.title = title
        self.steps = steps
        self.expected = expected
        self.environments = environments
        self.deviceNote = deviceNote
    }
}

public struct ChecklistEntry: Codable, Hashable, Sendable {
    public var itemID: String
    public var result: CheckResult
    public var note: String
    public var updatedAt: Date

    public init(itemID: String, result: CheckResult = .notRun, note: String = "", updatedAt: Date = Date()) {
        self.itemID = itemID
        self.result = result
        self.note = note
        self.updatedAt = updatedAt
    }
}

/// 実行中に自動で記録する計測値
public struct MetricSample: Codable, Hashable, Sendable {
    public var time: Date
    public var hudFPS: Double?
    public var inferenceFPS: Double?
    public var thermal: Int?
    public var batteryLevel: Double?
    public var horizontalAccuracy: Double?
    public var memoryMB: Double?
    public var externalDisplayConnected: Bool

    public init(time: Date, hudFPS: Double? = nil, inferenceFPS: Double? = nil, thermal: Int? = nil, batteryLevel: Double? = nil, horizontalAccuracy: Double? = nil, memoryMB: Double? = nil, externalDisplayConnected: Bool = false) {
        self.time = time
        self.hudFPS = hudFPS
        self.inferenceFPS = inferenceFPS
        self.thermal = thermal
        self.batteryLevel = batteryLevel
        self.horizontalAccuracy = horizontalAccuracy
        self.memoryMB = memoryMB
        self.externalDisplayConnected = externalDisplayConnected
    }
}

/// GitHub Issue に添付する実機テストレポート。
public struct DeviceTestReport: Codable, Sendable {
    public var appVersion: String
    public var buildNumber: String
    public var environment: TestEnvironment
    public var deviceModel: String
    public var systemVersion: String
    public var externalDisplay: String?
    public var createdAt: Date
    public var entries: [ChecklistEntry]
    public var metrics: [MetricSample]
    public var log: [String]

    public init(appVersion: String, buildNumber: String, environment: TestEnvironment, deviceModel: String, systemVersion: String, externalDisplay: String?, createdAt: Date, entries: [ChecklistEntry], metrics: [MetricSample], log: [String]) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.environment = environment
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.externalDisplay = externalDisplay
        self.createdAt = createdAt
        self.entries = entries
        self.metrics = metrics
        self.log = log
    }

    public var summary: (pass: Int, fail: Int, notRun: Int) {
        (entries.filter { $0.result == .pass }.count, entries.filter { $0.result == .fail }.count, entries.filter { $0.result == .notRun }.count)
    }

    /// 書き出し用 JSON。ログ中の座標らしき数値を丸める。
    public func exportData(roundLocations: Bool) throws -> Data {
        var copy = self
        if roundLocations {
            copy.log = log.map(DeviceTestReport.roundCoordinates)
        }
        return try HUDJSON.encode(copy)
    }

    /// "35.681236, 139.767125" のような小数を3桁に丸める。
    static func roundCoordinates(_ line: String) -> String {
        var result = ""
        var number = ""
        func flush() {
            if let dot = number.firstIndex(of: "."), number.distance(from: dot, to: number.endIndex) > 4, let v = Double(number), abs(v) <= 180 {
                result += String(format: "%.3f", v)
            } else {
                result += number
            }
            number = ""
        }
        for ch in line {
            if ch.isNumber || ch == "." || (ch == "-" && number.isEmpty) {
                number.append(ch)
            } else {
                flush()
                result.append(ch)
            }
        }
        flush()
        return result
    }
}

/// 実機チェックリスト（Phase 0〜7）。
public enum DeviceChecklist {
    public static let items: [ChecklistItem] = [
        // Phase 0（技術スパイク）
        ChecklistItem(id: "S0-P", phase: 0, title: "Swift Playgrounds で起動", steps: "HUDNavigator.swiftpm を Swift Playgrounds で開いて実行する", expected: "ホーム画面が表示される", environments: [.playgrounds], deviceNote: "iPad"),
        ChecklistItem(id: "S0-0", phase: 0, title: "AltStore でインストール", steps: "Release の .ipa を AltStore でインストールして起動する", expected: "ホーム画面が表示される", environments: [.installedApp]),
        ChecklistItem(id: "S0-1", phase: 0, title: "外部ディスプレイ独立表示", steps: "VITURE を接続し、設定→外部ディスプレイで状態を見る", expected: "グラスにHUD、端末に操作画面が別々に表示される（Playgrounds ではミラーになる場合あり）"),
        ChecklistItem(id: "S0-2", phase: 0, title: "黒背景の透過・文字見本", steps: "詳細→視認性テストを表示し、室内・屋外でグラス越しに見る", expected: "読める最小文字サイズ・色をメモに記録"),
        ChecklistItem(id: "S0-3", phase: 0, title: "カメラ＋外部出力の同時動作", steps: "背景をカメラにして10分表示する", expected: "止まらない／温度表示が「高温」にならない"),
        ChecklistItem(id: "S0-4", phase: 0, title: "権限ダイアログ", steps: "カメラ・位置・マイク・音声認識・モーションを順に使う", expected: "それぞれ許可ダイアログが出て、許可後に動作する"),
        ChecklistItem(id: "S0-5", phase: 0, title: "物体認識の速度", steps: "ビジョン画面で人物を写す", expected: "枠が表示され、推論fpsを記録"),
        ChecklistItem(id: "S0-6", phase: 0, title: "位置情報の取得", steps: "設定→センサー情報で位置・速度・方位・精度を見る", expected: "値と精度を記録（iPad Wi-Fi モデルは GPS なし）"),
        ChecklistItem(id: "S0-7", phase: 0, title: "ショートカット", steps: "ショートカットアプリで「HUD Navigator」のアクションを探す", expected: "アクションが表示され、実行できる", environments: [.installedApp]),
        ChecklistItem(id: "S0-8", phase: 0, title: "日本語音声認識・読み上げ", steps: "アシスタントで「黒背景にして」と話す／案内を読み上げる", expected: "認識されて背景が黒になる／日本語で読み上げる"),
        // Phase 1
        ChecklistItem(id: "P1-1", phase: 1, title: "HUDパネルの移動・サイズ変更", steps: "HUD編集でパネルをドラッグ・右下ハンドルで拡大", expected: "グラス側の表示も同時に変わる"),
        ChecklistItem(id: "P1-2", phase: 1, title: "配置の復元", steps: "アプリを終了して再起動／グラスを抜き差し", expected: "配置・背景モードが元に戻る"),
        ChecklistItem(id: "P1-3", phase: 1, title: "表示位置の調整", steps: "設定→外部ディスプレイで位置・拡大率を変える", expected: "視野の端でも読める位置に調整できる"),
        // Phase 2
        ChecklistItem(id: "P2-1", phase: 2, title: "テーマ・プリセット切替", steps: "7種のテーマとプリセットを順に切り替える", expected: "崩れずに切り替わる"),
        ChecklistItem(id: "P2-2", phase: 2, title: "テーマの書き出し・読み込み", steps: "テーマを書き出し、別端末（または同じ端末）で読み込む", expected: "同じ見た目になる"),
        // Phase 3
        ChecklistItem(id: "P3-1", phase: 3, title: "徒歩ナビ（屋外）", steps: "近所の目的地まで徒歩ナビを使う", expected: "曲がる前に音声案内、到着で終了", deviceNote: "iPhone 15 推奨（GPS）"),
        ChecklistItem(id: "P3-2", phase: 3, title: "デモルート再生", steps: "ナビ→デモ再生", expected: "ミニマップ・次の曲がり角・ETAが更新され、音声案内が流れる"),
        ChecklistItem(id: "P3-3", phase: 3, title: "リルート", steps: "ナビ中にわざとルートから外れる", expected: "「ルートから外れました」→再検索"),
        // Phase 4
        ChecklistItem(id: "P4-1", phase: 4, title: "歩行者・犬猫の検出", steps: "ビジョンで人や動物を写す", expected: "枠とラベルが重なって表示される"),
        ChecklistItem(id: "P4-2", phase: 4, title: "接近警告（実験）", steps: "安全な場所で、人にゆっくり近づいてもらう", expected: "警告が出る（出ない場合もある＝実験機能）"),
        ChecklistItem(id: "P4-3", phase: 4, title: "発熱・省電力", steps: "カメラ＋物体認識を30分使う", expected: "温度状態と省電力モードの移行を記録"),
        // Phase 5
        ChecklistItem(id: "P5-1", phase: 5, title: "音声コマンド10種", steps: "アシスタントのコマンド例を順に話す", expected: "それぞれ正しく動作する"),
        ChecklistItem(id: "P5-2", phase: 5, title: "クラウドAI（任意）", steps: "APIキーを入れて質問する", expected: "回答が表示・読み上げされる／通信ログに記録される"),
        // Phase 6
        ChecklistItem(id: "P6-1", phase: 6, title: "天気", steps: "天気ウィジェットを表示する", expected: "出典・更新時刻つきで表示される"),
        ChecklistItem(id: "P6-2", phase: 6, title: "設定の同期", steps: "iPad で書き出し → iCloud Drive → iPhone で読み込み", expected: "テーマ・プリセット・お気に入りが移る"),
        ChecklistItem(id: "P6-3", phase: 6, title: "履歴", steps: "履歴をONにして移動し、履歴画面を見る", expected: "距離・時間・グラフが表示される／全削除できる"),
        // Phase 7
        ChecklistItem(id: "P7-1", phase: 7, title: "60分連続利用", steps: "徒歩ナビプリセットで60分使う", expected: "落ちない・温度と電池の推移を記録"),
        ChecklistItem(id: "P7-2", phase: 7, title: "iPhone 15 総合確認", steps: "iPhone 15 + VITURE で主要機能を一通り使う", expected: "iPad と同様に動作する", environments: [.installedApp], deviceNote: "iPhone 15"),
    ]

    public static func items(for environment: TestEnvironment) -> [ChecklistItem] {
        items.filter { $0.environments.contains(environment) }
    }
}
