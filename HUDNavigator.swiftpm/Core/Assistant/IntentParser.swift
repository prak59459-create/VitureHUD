import Foundation

/// 音声認識したテキスト（日本語）をアプリの操作に変換する。端末内で動く・無料・オフライン。
/// 当てはまらない文は `.ask` として AI アシスタントに渡す。
public struct IntentParser: Sendable {
    /// ユーザーが作ったプリセット名 → key（ユーザープリセットは id 文字列）
    public var userPresetNames: [String: String]
    public var userThemeNames: [String: String]

    public init(userPresetNames: [String: String] = [:], userThemeNames: [String: String] = [:]) {
        self.userPresetNames = userPresetNames
        self.userThemeNames = userThemeNames
    }

    /// 表記ゆれを減らす（空白・句読点を除き、全角英数を半角に、英字を小文字に）。
    public static func normalize(_ text: String) -> String {
        var s = text
        s = s.applyingFullWidthToHalfWidth()
        s = s.lowercased()
        // 長音「ー」は単語の一部なので残す。
        let removed: Set<Character> = [" ", "\u{3000}", "。", "、", "！", "？", "!", "?", ".", ",", "「", "」", "・", "〜"]
        return String(s.filter { !removed.contains($0) })
    }

    public func parse(_ rawText: String) -> AppCommand {
        let text = Self.normalize(rawText)
        guard !text.isEmpty else { return .cancel }
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        func hasAny(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        let negative = has("オフ", "おふ", "off", "止め", "とめ", "停止", "やめ", "消して", "けして", "無効", "切って", "きって", "非表示", "隠して", "かくして", "閉じ", "とじ", "終了", "しゅうりょう")
        let positive = has("オン", "おん", "on", "開始", "かいし", "有効", "つけて", "付けて", "表示", "ひょうじ", "出して", "だして", "見せて", "スタート", "始め", "はじめ")

        // キャンセル
        if text == "キャンセル" || text == "やめて" || text == "なんでもない" || text == "取り消し" { return .cancel }

        // もう一度
        if has("もう一度", "もういちど", "繰り返して", "くりかえして", "なんて言った") { return .repeatGuidance }

        // ワーク（計算・タイマー・やること・メモ・ブラウザ・台本）
        if let work = Self.parseWork(raw: rawText, text: text, positive: positive, negative: negative) { return work }

        // 背景
        if has("背景", "はいけい", "バックグラウンド") || has("黒背景", "ブラック") {
            if has("黒", "くろ", "ブラック", "black") { return .setBackground(.black) }
            if has("カメラ", "かめら", "映像", "パススルー", "camera") { return .setBackground(.camera) }
            if has("切り替え", "切替", "きりかえ", "変えて", "かえて") { return .toggleBackground }
        }
        if has("カメラモード", "カメラに切り替え", "カメラに変更", "カメラにして", "カメラ表示", "カメラ背景", "パススルー") { return .setBackground(.camera) }
        if has("黒にして", "真っ黒", "まっくろ") { return .setBackground(.black) }

        // 距離・3D
        if has("何メートル", "なんメートル", "何m", "距離を測", "距離をはか", "きょりをはか", "どのくらい離れ", "どれくらい離れ") { return .measureDistance }
        if has("3dスキャン", "スキャン", "すきゃん", "立体的に記録", "3d化") { return .open(.scan3D) }
        if has("距離の推定", "距離推定", "奥行き", "深度", "距離モード", "障害物検知", "障害物警告") { return .setDepth(!negative) }

        // 頭の動き（正面合わせ・空間固定・チラ見）
        if has("正面", "しょうめん") && has("リセット", "合わせ", "あわせ", "戻", "もど", "にして", "設定", "決め") { return .recenterHead }
        if has("固定", "こてい") && has("hud", "空間", "画面", "表示", "ヘッド", "頭") {
            return .setHeadLock(!(negative || has("解除", "かいじょ", "外し", "はずし")))
        }
        if has("チラ見", "ちらみ", "下を見") { return .setGlanceMode(!(negative && !has("表示")) && !has("解除", "やめ")) }

        // HUD
        if has("hud", "ハッド", "はっど", "ヘッドアップ") {
            if has("編集", "へんしゅう") { return .open(.hudEditor) }
            if has("整列", "せいれつ", "並べ", "ならべ") { return .autoArrange }
            if has("3d", "立体", "りったい") { return .setStereo3D(!negative) }
            if has("明るく", "あかるく") { return .adjustBrightness(.up) }
            if has("暗く", "くらく") { return .adjustBrightness(.down) }
            if has("大きく", "おおきく", "拡大") { return .adjustHUDScale(.up) }
            if has("小さく", "ちいさく", "縮小") { return .adjustHUDScale(.down) }
            if let dir = Self.moveDirection(text) { return .moveHUD(dir) }
            if negative { return .stopHUD }
            if positive || has("起動", "きどう") { return .startHUD }
        }
        if has("自動整列", "整列して", "並べて", "ならべて") { return .autoArrange }

        // 文字の大きさ・明るさ・夜間
        if has("文字", "もじ", "字を") {
            if has("大きく", "おおきく") { return .adjustTextSize(.up) }
            if has("小さく", "ちいさく") { return .adjustTextSize(.down) }
        }
        if has("画面を明るく", "表示を明るく") { return .adjustBrightness(.up) }
        if has("画面を暗く", "表示を暗く", "まぶしい", "眩しい") { return .adjustBrightness(.down) }
        if has("夜間", "やかん", "ナイトモード") { return .setNightDim(!negative) }
        if has("立体表示", "3d表示", "3dモード") && !has("地図", "マップ") { return .setStereo3D(!negative) }

        // プリセット・テーマの順送り
        if has("次のプリセット", "つぎのプリセット", "プリセットを変え", "次のモード") { return .cyclePreset(1) }
        if has("前のプリセット", "まえのプリセット", "前のモード") { return .cyclePreset(-1) }
        if has("テーマを変え", "次のテーマ", "つぎのテーマ", "別のテーマ") { return .nextTheme }

        // 心拍計・同期・記録
        if has("心拍計", "心拍センサー", "しんぱくけい") && has("接続", "つない", "繋い", "せつぞく") { return .connectHeartRate }
        if has("同期", "どうき", "シンク") { return .syncNow }
        if has("記録") && !has("履歴") {
            if has("開始", "始め", "はじめ", "スタート") { return .setRecording(true) }
            if has("終了", "止め", "とめ", "やめ", "終わ") { return .setRecording(false) }
        }

        // プリセット・テーマ
        if has("テーマ", "てーま") {
            for (key, aliases) in BuiltInContent.themeAliases where hasAny(aliases.map { Self.normalize($0) }) {
                return .applyTheme(key: key)
            }
            for (name, key) in userThemeNames where text.contains(Self.normalize(name)) {
                return .applyTheme(key: key)
            }
        }
        if has("モード", "もーど", "プリセット", "ぷりせっと", "にして", "に変更", "に切り替え") {
            for (name, key) in userPresetNames where text.contains(Self.normalize(name)) {
                return .applyPreset(key: key)
            }
            for (key, aliases) in BuiltInContent.presetAliases where hasAny(aliases.map { Self.normalize($0) }) {
                // 「ナビを開始」などとの衝突を避けるため、徒歩は「モード/プリセット」が必要
                return .applyPreset(key: key)
            }
        }

        // 音声案内
        if has("音声案内", "おんせいあんない", "読み上げ", "よみあげ", "音声ガイド", "ナビの音声", "ミュート", "みゅーと", "声") {
            if has("ミュート", "みゅーと") { return .setVoiceGuidance(false) }
            if negative { return .setVoiceGuidance(false) }
            if positive { return .setVoiceGuidance(true) }
        }

        // 物体認識・危険検知
        if has("危険検知", "きけんけんち", "危険警告", "衝突警告") {
            return .setHazardAlerts(!negative)
        }
        if has("物体認識", "ぶったいにんしき", "物体検出", "物体検知", "認識", "検出") {
            return .setDetection(!negative)
        }

        // 地図
        if has("地図", "ちず", "マップ", "まっぷ", "map") {
            if has("3d", "立体", "りったい", "スリーディー") { return .setMap3D(true) }
            if has("2d", "平面", "へいめん", "ツーディー") { return .setMap3D(false) }
            if has("大きく", "おおきく", "拡大", "かくだい", "ズームイン", "近く", "詳しく", "くわしく") { return .mapZoom(.zoomIn) }
            if has("小さく", "ちいさく", "縮小", "しゅくしょう", "ズームアウト", "広く", "ひろく", "遠く") { return .mapZoom(.zoomOut) }
            if negative { return .hideWidget(.miniMap) }
            if positive { return .showWidget(.miniMap) }
        }

        // カメラ
        if has("カメラ", "かめら") {
            if has("明るく", "あかるく") { return .cameraExposure(.up) }
            if has("暗く", "くらく") { return .cameraExposure(.down) }
            if has("ズームイン", "拡大", "かくだい", "大きく", "おおきく") { return .cameraZoom(.zoomIn) }
            if has("ズームアウト", "縮小", "しゅくしょう", "小さく", "ちいさく") { return .cameraZoom(.zoomOut) }
        }

        // ナビ
        if has("ナビ", "なび", "案内", "あんない", "ルート", "るーと") {
            if negative || has("やめ", "キャンセル") { return .stopNavigation }
            if let dest = Self.extractDestination(text), !dest.isEmpty { return .navigate(to: dest) }
            if positive || has("開始", "スタート") { return .startNavigation }
        }
        if let dest = Self.extractDestination(text), has("行きたい", "いきたい", "行って", "いって", "連れて", "つれて", "向かう", "むかう") {
            return .navigate(to: dest)
        }

        // 周辺検索
        if has("近く", "ちかく", "周辺", "しゅうへん", "最寄り", "もより", "付近", "この辺") || has("探して", "さがして", "どこ", "ある") {
            for category in NearbyCategory.allCases where hasAny(category.aliases.map { Self.normalize($0) }) {
                return .searchNearby(category)
            }
        }
        if let query = Self.extractSearchQuery(text) {
            // 「目的地を検索して」のように検索語が無い場合はナビ画面を開く
            let generic = ["目的地", "行き先", "いきさき", "場所", "ばしょ", "住所", "じゅうしょ"]
            return generic.contains(query) ? .open(.navigation) : .search(query)
        }

        // 状態の問い合わせ（「〇〇を表示して／消して」はウィジェットの操作なので除く）
        if !(positive || negative) {
            if has("何時", "なんじ", "時刻", "じこく", "時間を教え") { return .status(.time) }
            if has("何日", "なんにち", "日付", "ひづけ", "今日は何曜", "曜日") { return .status(.date) }
            if has("バッテリー", "ばってりー", "電池", "でんち", "充電") { return .status(.battery) }
            if has("速度", "そくど", "スピード", "速さ", "時速") { return .status(.speed) }
            if has("到着", "とうちゃく", "あと何分", "あとなんぷん", "いつ着", "何時に着") { return .status(.eta) }
            if has("あと何キロ", "あと何メートル", "残り距離", "のこりきょり", "あとどのくらい", "あとどれくらい") { return .status(.remainingDistance) }
            if has("天気", "てんき", "雨", "あめ", "気温", "きおん", "暑い", "寒い", "傘") { return .status(.weather) }
            if has("ここはどこ", "現在地", "げんざいち", "今どこ", "いまどこ") { return .status(.location) }
            if has("どっち", "方角", "ほうがく", "方位", "北はどっち") { return .status(.heading) }
        }

        // ウィジェットの表示・非表示（「〇〇を表示して」「〇〇を消して」）。
        // 「世界時計」と「時計」のように名前が重なるときは、長い名前を優先する
        if positive || negative {
            var best: (kind: WidgetKind, length: Int)?
            for kind in WidgetKind.allCases {
                for name in Self.widgetAliases(kind).map({ Self.normalize($0) }) where text.contains(name) {
                    if best == nil || name.count > best!.length { best = (kind, name.count) }
                }
            }
            if let best { return negative ? .hideWidget(best.kind) : .showWidget(best.kind) }
        }

        // 画面
        if has("開いて", "ひらいて", "を表示", "画面") {
            if has("設定", "せってい") { return .open(.settings) }
            if has("履歴", "りれき") { return .open(.history) }
            if has("天気", "てんき") { return .open(.weather) }
            if has("ホーム", "ほーむ") { return .open(.home) }
            if has("ワーク", "わーく", "デスク", "作業", "ブラウザ", "ウェブ") { return .open(.work) }
        }

        return .ask(rawText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - ワーク

    /// デスクワーク向けの言い方（当てはまらなければ nil）
    static func parseWork(raw: String, text: String, positive: Bool, negative: Bool) -> AppCommand? {
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let stops = has("止め", "とめ", "停止", "やめ", "キャンセル", "終了", "解除", "ストップ", "リセット")
        let starts = has("開始", "かいし", "始め", "はじめ", "スタート", "再生", "流して", "進めて", "オン", "つけて")

        // 計算（「128かける3は？」「(12+3)*4」）
        if let expression = MathExpression.normalize(raw) { return .calculate(expression) }

        // 集中タイマー（ポモドーロ）
        if has("集中タイマー", "ポモドーロ", "ぽもどーろ") || (has("集中") && !has("モード", "プリセット") && (starts || stops)) {
            if has("次へ", "スキップ", "飛ばし", "とばし") { return .skipFocus }
            if stops || has("オフ", "消して") { return .setFocus(false) }
            if starts { return .setFocus(true) }
        }
        if has("休憩") && has("スキップ", "飛ばし", "とばし", "終わり", "おわり") { return .skipFocus }

        // ストップウォッチ
        if has("ストップウォッチ") {
            // 「ストップウォッチ」自体に「ストップ」が入っているので、取り除いてから見る
            let rest = text.replacingOccurrences(of: "ストップウォッチ", with: "")
            let stopWords = ["止め", "とめ", "停止", "やめ", "キャンセル", "終了", "ストップ", "リセット"]
            if stopWords.contains(where: { rest.contains($0) }) { return .setStopwatch(false) }
            if starts || has("計って", "測って", "はかって") { return .setStopwatch(true) }
        }

        // タイマー（「5分タイマー」「3分測って」「10分後に教えて」）
        let duration = extractDuration(text)
        if has("タイマー", "たいまー") && !has("集中", "ポモドーロ") {
            if let duration { return .startTimer(seconds: duration) }
            if stops { return .stopTimer }
        }
        if let duration, has("測って", "はかって", "計って", "たったら", "経ったら", "後に教え", "後におしえ", "後に知らせ", "後にしらせ", "後に呼んで") {
            return .startTimer(seconds: duration)
        }

        // やること
        if has("やること", "タスク", "todo", "トゥードゥー") {
            if let title = extractTodoTitle(raw) { return .addTodo(title) }
            if has("完了", "終わった", "おわった", "終わり", "済み", "済んだ", "できた", "チェック") {
                return .completeTodo(extractCompletedTodo(raw) ?? "")
            }
        }

        // メモ（「メモ、牛乳を買う」「牛乳を買うとメモして」）
        if has("メモ", "めも"), let note = extractNote(raw) { return .addNote(note) }

        // ブラウザ
        if has("スクロール") || (has("ページ") && has("下に", "上に", "下へ", "上へ", "進んで", "送って")) {
            return .webScroll(has("上に", "上へ", "うえに", "戻") ? .up : .down)
        }
        if has("ページ", "ブラウザ", "サイト") && has("戻って", "もどって", "戻る", "戻して") { return .webBack }
        if has("ウェブ", "web", "ブラウザ", "ネットで", "インターネット", "ググ", "サイトを"), let query = extractWebQuery(raw) {
            return .openWeb(query)
        }

        // 台本（プロンプター）
        if has("台本", "だいほん", "プロンプター", "原稿") {
            if has("止め", "とめ", "停止", "ストップ", "一時停止") { return .setTeleprompter(false) }
            if has("再生", "開始", "スタート", "始め", "はじめ", "流して", "進めて", "読み") { return .setTeleprompter(true) }
        }
        return nil
    }

    /// 「5分」「1時間30分」「90秒」「3分半」を秒にする
    static func extractDuration(_ text: String) -> Int? {
        let chars = Array(text)
        var total = 0
        var found = false
        var digits = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isASCII, c.isNumber {
                digits.append(c)
                i += 1
                continue
            }
            if let n = Int(digits) {
                if c == "時", i + 1 < chars.count, chars[i + 1] == "間" {
                    total += n * 3600
                    found = true
                    i += 1
                } else if c == "分" {
                    total += n * 60
                    found = true
                    if i + 1 < chars.count, chars[i + 1] == "半" {
                        total += 30
                        i += 1
                    }
                } else if c == "秒" {
                    total += n
                    found = true
                }
            }
            digits = ""
            i += 1
        }
        return found && total > 0 && total <= 24 * 3600 ? total : nil
    }

    /// 前後の空白・句読点を取り除く
    static func tidy(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " \u{3000}、。,.:：!！?？「」\n"))
    }

    /// text から first より後・last より前を取り出す
    static func between(_ text: String, after first: [String], before last: [String]) -> String? {
        for a in first {
            guard let start = text.range(of: a) else { continue }
            let rest = text[start.upperBound...]
            for b in last {
                if let end = rest.range(of: b, options: .backwards) {
                    let middle = tidy(String(rest[rest.startIndex..<end.lowerBound]))
                    if !middle.isEmpty && middle.count <= 120 { return middle }
                }
            }
        }
        return nil
    }

    /// 「やることに牛乳を買うを追加」「牛乳を買うをタスクに追加して」「タスク追加 牛乳を買う」
    static func extractTodoTitle(_ raw: String) -> String? {
        let text = tidy(raw)
        let lists = ["やることリスト", "やること", "タスクリスト", "タスク", "TODO", "ToDo", "todo", "Todo"]
        let adds = ["を追加", "をついか", "追加", "を入れて", "をいれて", "を足して", "を登録", "と追加"]
        // 「〇〇に △△ を追加」
        if let title = between(text, after: lists.map { $0 + "に" }, before: adds) { return title }
        // 「△△ を 〇〇に追加」
        for list in lists {
            for joiner in ["を", "って", "と", ""] {
                let marker = joiner + list + "に"
                if let r = text.range(of: marker), text[r.upperBound...].contains("追加") || text[r.upperBound...].contains("入れ") || text[r.upperBound...].contains("登録") {
                    let title = tidy(String(text[text.startIndex..<r.lowerBound]))
                    if !title.isEmpty && title.count <= 120 { return title }
                }
            }
        }
        // 「タスク追加 △△」
        for list in lists {
            for add in ["追加", "を追加", "に追加"] {
                let marker = list + add
                if text.hasPrefix(marker) {
                    let title = tidy(String(text.dropFirst(marker.count)))
                    if !title.isEmpty && title.count <= 120 && !["して", "する", "したい"].contains(title) { return title }
                }
            }
        }
        return nil
    }

    /// 「タスクの牛乳を完了」→ "牛乳"（名前がなければ nil）
    static func extractCompletedTodo(_ raw: String) -> String? {
        let text = tidy(raw)
        let name = between(text, after: ["タスクの", "やることの"], before: ["を完了", "を終わり", "をおわり", "が終わった", "がおわった", "をチェック", "は終わった", "はできた"])
        return name
    }

    /// 「メモ、牛乳を買う」「牛乳を買うとメモして」「メモに牛乳を追加」
    static func extractNote(_ raw: String) -> String? {
        let text = tidy(raw)
        for suffix in ["とメモしておいて", "とメモしといて", "とメモして", "ってメモしておいて", "ってメモしといて", "ってメモして", "をメモしておいて", "をメモしといて", "をメモして", "をメモに追加して", "をメモに追加", "をメモに書いて", "とメモ", "をメモ"] {
            if text.hasSuffix(suffix) {
                let note = tidy(String(text.dropLast(suffix.count)))
                if !note.isEmpty { return note }
            }
        }
        if let note = between(text, after: ["メモに"], before: ["を追加", "と書いて", "って書いて", "を書いて", "と追加"]) { return note }
        for prefix in ["メモしておいて", "メモしといて", "メモして", "メモを取って", "メモ取って", "メモ"] where text.hasPrefix(prefix) {
            let rest = String(text.dropFirst(prefix.count))
            // 「メモを表示」のような操作と区別するため、区切り（、・空白・：）が必要
            guard let first = rest.first, "、,:： \u{3000}。".contains(first) else { continue }
            let note = tidy(rest)
            if !note.isEmpty { return note }
        }
        return nil
    }

    /// 「猫の動画をウェブで検索」「ブラウザで example.com を開いて」→ 検索語・アドレス
    static func extractWebQuery(_ raw: String) -> String? {
        var text = tidy(raw)
        for tool in ["インターネットで", "ウェブサイトで", "ウェブで", "Webで", "webで", "WEBで", "ブラウザで", "ネットで", "サイトを", "ググって", "ググる"] {
            text = text.replacingOccurrences(of: tool, with: "")
        }
        for suffix in ["を検索して", "を検索", "検索して", "を調べて", "をしらべて", "について調べて", "を開いて", "をひらいて", "を表示して", "を表示", "を見せて", "を", "で"] {
            let t = tidy(text)
            if t.hasSuffix(suffix) {
                text = String(t.dropLast(suffix.count))
                break
            }
        }
        let query = tidy(text)
        let generic: Set<String> = ["", "ブラウザ", "ウェブ", "ネット", "インターネット", "ページ", "サイト"]
        return generic.contains(query) || query.count > 120 ? nil : query
    }

    static func moveDirection(_ text: String) -> MoveDirection? {
        if text.contains("上に") || text.contains("うえに") || text.contains("上へ") { return .up }
        if text.contains("下に") || text.contains("したに") || text.contains("下へ") { return .down }
        if text.contains("右に") || text.contains("みぎに") || text.contains("右へ") { return .right }
        if text.contains("左に") || text.contains("ひだりに") || text.contains("左へ") { return .left }
        return nil
    }

    static func widgetAliases(_ kind: WidgetKind) -> [String] {
        switch kind {
        case .clock: return ["時計", "とけい"]
        case .date: return ["日付", "ひづけ"]
        case .battery: return ["バッテリー", "電池"]
        case .speed: return ["速度", "そくど", "スピード", "速度計"]
        case .compass: return ["コンパス", "こんぱす", "方位"]
        case .miniMap: return ["ミニマップ", "みにまっぷ"]
        case .weather: return ["天気", "てんき"]
        case .temperature: return ["気温", "きおん", "温度"]
        case .precipitation: return ["降水", "こうすい", "雨の確率"]
        case .airQuality: return ["空気質", "空気", "大気"]
        case .tripDistance: return ["移動距離", "いどうきょり", "歩いた距離"]
        case .eta: return ["到着予想", "到着予定", "eta"]
        case .nextTurn: return ["次の曲がり角", "曲がり角", "ターン"]
        case .notifications: return ["通知", "つうち"]
        case .gpsStatus: return ["gps", "じーぴーえす"]
        case .sensors: return ["センサー", "せんさー", "ジャイロ", "加速度"]
        case .assistant: return ["アシスタント", "あしすたんと"]
        case .detections: return ["検出結果", "検出表示"]
        case .customText: return ["テキスト"]
        case .heartRate: return ["心拍", "しんぱく", "脈拍"]
        case .horizon: return ["水平器", "すいへいき", "水平"]
        case .hourlyForecast: return ["時間ごとの天気", "天気予報", "予報"]
        case .nearbyPlaces: return ["周辺施設", "近くの施設"]
        case .steps: return ["歩数", "ほすう", "万歩計", "気圧"]
        case .headPose: return ["頭の向き", "あたまのむき"]
        case .distance: return ["距離計", "障害物", "きょり"]
        case .notes: return ["メモ", "ノート"]
        case .todo: return ["やること", "タスク", "todo", "やることリスト"]
        case .focusTimer: return ["集中タイマー", "ポモドーロ"]
        case .timer: return ["タイマー", "ストップウォッチ"]
        case .calendar: return ["予定", "スケジュール", "カレンダー"]
        case .webPage: return ["ブラウザ", "ウェブページ", "ウェブ"]
        case .teleprompter: return ["台本", "プロンプター", "原稿"]
        case .worldClock: return ["世界時計", "せかいどけい"]
        }
    }

    /// 「東京駅まで」「東京駅へのナビ」「東京駅に行きたい」から目的地を取り出す。
    static func extractDestination(_ text: String) -> String? {
        let markers = ["までのナビ", "までの案内", "までのルート", "までナビ", "まで案内", "までルート", "まで行きたい", "までいきたい", "まで連れて", "まで",
                       "へのナビ", "への案内", "へのルート", "へナビ", "へ行きたい", "へいきたい", "に行きたい", "にいきたい", "に連れて", "へ連れて", "に向かう", "へ向かう"]
        for marker in markers {
            if let range = text.range(of: marker) {
                var dest = String(text[text.startIndex..<range.lowerBound])
                for prefix in ["ここから", "現在地から", "今から", "いまから"] where dest.hasPrefix(prefix) {
                    dest = String(dest.dropFirst(prefix.count))
                }
                if dest.count >= 1 && dest.count <= 40 { return dest }
            }
        }
        return nil
    }

    /// 「〇〇を検索して」「〇〇を探して」
    static func extractSearchQuery(_ text: String) -> String? {
        let markers = ["を検索", "をけんさく", "を探して", "をさがして", "検索して", "をしらべて", "を調べて"]
        for marker in markers {
            if let range = text.range(of: marker) {
                let q = String(text[text.startIndex..<range.lowerBound])
                if q.count >= 1 && q.count <= 40 { return q }
            }
        }
        if text.hasPrefix("目的地を"), let r = text.range(of: "目的地を") {
            let rest = String(text[r.upperBound...])
            if let q = extractSearchQuery(rest) { return q }
        }
        return nil
    }
}

extension String {
    /// 全角英数字・記号を半角にする（Linux でも動くよう自前で変換）。
    func applyingFullWidthToHalfWidth() -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            let v = scalar.value
            if v >= 0xFF01 && v <= 0xFF5E, let half = Unicode.Scalar(v - 0xFEE0) {
                scalars.append(half)
            } else if v == 0x3000 {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
