import Foundation

// デスクワーク・勉強・発表などで使う「ワーク」のデータ（メモ・やること・しおり・台本）。
// 画面に依存しない純粋なロジックだけを置く（Linux でテストする）。

public struct NoteItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", text: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case id, title, text, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        title = c.value(.title, default: "")
        text = c.value(.text, default: "")
        updatedAt = c.value(.updatedAt, default: Date())
    }

    /// 表示用の題名（題名が空なら本文の 1 行目）
    public var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "新しいメモ" : String(first.prefix(24))
    }

    /// 空でない行
    public var lines: [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

public struct TodoItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public var createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey { case id, title, isDone, createdAt, completedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        title = c.value(.title, default: "")
        isDone = c.value(.isDone, default: false)
        createdAt = c.value(.createdAt, default: Date())
        completedAt = c.value(.completedAt, default: nil)
    }
}

public struct WebBookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String

    public init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

/// 世界時計に出す都市
public struct WorldClockCity: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// IANA のタイムゾーン名（例: "America/New_York"）
    public var timeZoneID: String

    public init(id: UUID = UUID(), name: String, timeZoneID: String) {
        self.id = id
        self.name = name
        self.timeZoneID = timeZoneID
    }

    public static let presets: [WorldClockCity] = [
        WorldClockCity(name: "東京", timeZoneID: "Asia/Tokyo"),
        WorldClockCity(name: "ニューヨーク", timeZoneID: "America/New_York"),
        WorldClockCity(name: "ロサンゼルス", timeZoneID: "America/Los_Angeles"),
        WorldClockCity(name: "ロンドン", timeZoneID: "Europe/London"),
        WorldClockCity(name: "パリ", timeZoneID: "Europe/Paris"),
        WorldClockCity(name: "ベルリン", timeZoneID: "Europe/Berlin"),
        WorldClockCity(name: "シンガポール", timeZoneID: "Asia/Singapore"),
        WorldClockCity(name: "上海", timeZoneID: "Asia/Shanghai"),
        WorldClockCity(name: "ソウル", timeZoneID: "Asia/Seoul"),
        WorldClockCity(name: "バンコク", timeZoneID: "Asia/Bangkok"),
        WorldClockCity(name: "デリー", timeZoneID: "Asia/Kolkata"),
        WorldClockCity(name: "ドバイ", timeZoneID: "Asia/Dubai"),
        WorldClockCity(name: "シドニー", timeZoneID: "Australia/Sydney"),
        WorldClockCity(name: "ホノルル", timeZoneID: "Pacific/Honolulu"),
        WorldClockCity(name: "サンパウロ", timeZoneID: "America/Sao_Paulo"),
        WorldClockCity(name: "UTC", timeZoneID: "UTC"),
    ]

    /// その都市の時刻（例: "9:05"）と、基準の場所との日付の違い（"翌日"・"前日"・""）
    public func timeText(at date: Date, relativeTo home: TimeZone = .current) -> (time: String, dayNote: String, offsetHours: Double) {
        guard let zone = TimeZone(identifier: timeZoneID) else { return ("--:--", "", 0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var homeCalendar = Calendar(identifier: .gregorian)
        homeCalendar.timeZone = home
        let time = HUDFormat.clock(date, calendar: calendar)
        let there = calendar.dateComponents([.year, .month, .day], from: date)
        let here = homeCalendar.dateComponents([.year, .month, .day], from: date)
        let thereKey = (there.year ?? 0) * 10000 + (there.month ?? 0) * 100 + (there.day ?? 0)
        let hereKey = (here.year ?? 0) * 10000 + (here.month ?? 0) * 100 + (here.day ?? 0)
        let note = thereKey > hereKey ? "翌日" : (thereKey < hereKey ? "前日" : "")
        let offset = Double(zone.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)) / 3600
        return (time, note, offset)
    }
}

/// ワークのデータ一式（端末内に保存）
public struct WorkspaceData: Codable, Hashable, Sendable {
    public var notes: [NoteItem]
    public var selectedNoteID: UUID?
    public var todos: [TodoItem]
    public var bookmarks: [WebBookmark]
    /// ブラウザを開いたときのページ
    public var homeURL: String
    public var lastURL: String?
    /// 台本（プロンプター）
    public var script: String
    /// 台本の速さ（1 分あたりの文字数）
    public var scriptCharactersPerMinute: Double
    public var focus: FocusSettings
    public var worldClocks: [WorldClockCity]
    /// ブラウザの設定
    public var webDarkMode: Bool
    public var webDesktopMode: Bool
    public var webZoom: Double
    /// 集中した記録（日付 "yyyy-MM-dd" → 秒）
    public var focusLog: [String: Double]

    public init(
        notes: [NoteItem] = [],
        selectedNoteID: UUID? = nil,
        todos: [TodoItem] = [],
        bookmarks: [WebBookmark] = WorkspaceData.defaultBookmarks,
        homeURL: String = "https://duckduckgo.com/",
        lastURL: String? = nil,
        script: String = "",
        scriptCharactersPerMinute: Double = 300,
        focus: FocusSettings = FocusSettings(),
        worldClocks: [WorldClockCity] = [WorldClockCity.presets[1], WorldClockCity.presets[3]],
        webDarkMode: Bool = true,
        webDesktopMode: Bool = false,
        webZoom: Double = 1,
        focusLog: [String: Double] = [:]
    ) {
        self.notes = notes
        self.selectedNoteID = selectedNoteID
        self.todos = todos
        self.bookmarks = bookmarks
        self.homeURL = homeURL
        self.lastURL = lastURL
        self.script = script
        self.scriptCharactersPerMinute = scriptCharactersPerMinute
        self.focus = focus
        self.worldClocks = worldClocks
        self.webDarkMode = webDarkMode
        self.webDesktopMode = webDesktopMode
        self.webZoom = webZoom
        self.focusLog = focusLog
    }

    public static let defaultBookmarks: [WebBookmark] = [
        WebBookmark(title: "検索", url: "https://duckduckgo.com/"),
        WebBookmark(title: "Wikipedia", url: "https://ja.wikipedia.org/"),
        WebBookmark(title: "翻訳", url: "https://translate.google.com/"),
        WebBookmark(title: "GitHub", url: "https://github.com/"),
    ]

    enum CodingKeys: String, CodingKey {
        case notes, selectedNoteID, todos, bookmarks, homeURL, lastURL, script, scriptCharactersPerMinute, focus, worldClocks
        case webDarkMode, webDesktopMode, webZoom, focusLog
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkspaceData()
        notes = c.value(.notes, default: d.notes)
        selectedNoteID = c.value(.selectedNoteID, default: nil)
        todos = c.value(.todos, default: d.todos)
        bookmarks = c.value(.bookmarks, default: d.bookmarks)
        homeURL = c.value(.homeURL, default: d.homeURL)
        lastURL = c.value(.lastURL, default: nil)
        script = c.value(.script, default: d.script)
        scriptCharactersPerMinute = c.value(.scriptCharactersPerMinute, default: d.scriptCharactersPerMinute)
        focus = c.value(.focus, default: d.focus)
        worldClocks = c.value(.worldClocks, default: d.worldClocks)
        webDarkMode = c.value(.webDarkMode, default: d.webDarkMode)
        webDesktopMode = c.value(.webDesktopMode, default: d.webDesktopMode)
        webZoom = c.value(.webZoom, default: d.webZoom)
        focusLog = c.value(.focusLog, default: d.focusLog)
    }

    // MARK: メモ

    /// HUD に出すメモ（選んだもの。なければ最後に書いたもの）
    public var selectedNote: NoteItem? {
        if let id = selectedNoteID, let n = notes.first(where: { $0.id == id }) { return n }
        return notes.max { $0.updatedAt < $1.updatedAt }
    }

    @discardableResult
    public mutating func addNote(title: String = "", text: String = "", now: Date = Date()) -> NoteItem {
        let note = NoteItem(title: title, text: text, updatedAt: now)
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        return note
    }

    /// 選んでいるメモの末尾に 1 行足す（メモがなければ作る）。音声の「メモして」で使う。
    @discardableResult
    public mutating func appendToSelectedNote(_ line: String, now: Date = Date()) -> NoteItem {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let current = selectedNote, let i = notes.firstIndex(where: { $0.id == current.id }) else {
            return addNote(text: trimmed, now: now)
        }
        notes[i].text = notes[i].text.isEmpty ? trimmed : notes[i].text + "\n" + trimmed
        notes[i].updatedAt = now
        selectedNoteID = notes[i].id
        return notes[i]
    }

    public mutating func updateNote(_ id: UUID, title: String? = nil, text: String? = nil, now: Date = Date()) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if let title { notes[i].title = title }
        if let text { notes[i].text = text }
        notes[i].updatedAt = now
    }

    public mutating func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteID == id { selectedNoteID = notes.first?.id }
    }

    // MARK: やること

    public var pendingTodos: [TodoItem] { todos.filter { !$0.isDone } }
    public var doneTodos: [TodoItem] { todos.filter(\.isDone) }

    @discardableResult
    public mutating func addTodo(_ title: String, now: Date = Date()) -> TodoItem? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let item = TodoItem(title: String(t.prefix(120)), createdAt: now)
        // 終わっていないものの最後に入れる（終わったものは下にまとめる）
        let index = todos.firstIndex(where: \.isDone) ?? todos.count
        todos.insert(item, at: index)
        return item
    }

    public mutating func setTodo(_ id: UUID, done: Bool, now: Date = Date()) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        var item = todos.remove(at: i)
        item.isDone = done
        item.completedAt = done ? now : nil
        // 「まだ」のものの最後＝「終わった」ものの先頭に入れる
        let index = todos.firstIndex(where: \.isDone) ?? todos.count
        todos.insert(item, at: index)
    }

    public mutating func toggleTodo(_ id: UUID, now: Date = Date()) {
        guard let item = todos.first(where: { $0.id == id }) else { return }
        setTodo(id, done: !item.isDone, now: now)
    }

    /// いちばん上の「まだ」のものを終わりにする（音声の「次のタスク完了」）
    @discardableResult
    public mutating func completeNextTodo(now: Date = Date()) -> TodoItem? {
        guard let next = pendingTodos.first else { return nil }
        setTodo(next.id, done: true, now: now)
        return next
    }

    /// 名前の一部が合う「まだ」のものを終わりにする
    @discardableResult
    public mutating func completeTodo(matching text: String, now: Date = Date()) -> TodoItem? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, let item = pendingTodos.first(where: { $0.title.lowercased().contains(key) }) else { return nil }
        setTodo(item.id, done: true, now: now)
        return item
    }

    public mutating func removeCompletedTodos() {
        todos.removeAll(where: \.isDone)
    }

    public mutating func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    // MARK: 集中の記録

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public mutating func logFocus(seconds: Double, at date: Date = Date(), calendar: Calendar = .current) {
        guard seconds > 0 else { return }
        focusLog[Self.dayKey(date, calendar: calendar), default: 0] += seconds
        // 60 日より前は消す
        if focusLog.count > 60 {
            let keep = Set(focusLog.keys.sorted().suffix(60))
            focusLog = focusLog.filter { keep.contains($0.key) }
        }
    }

    public func focusSeconds(on date: Date = Date(), calendar: Calendar = .current) -> Double {
        focusLog[Self.dayKey(date, calendar: calendar)] ?? 0
    }
}

/// 入力した文字を「開くアドレス」にする（アドレスならそのまま、言葉なら検索）
public enum WebAddress {
    public static let searchBase = "https://duckduckgo.com/?q="

    public static func resolve(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return text.contains(" ") ? nil : text
        }
        // 危ない・使えない種類のアドレスは検索に回す
        let looksLikeHost = !text.contains(" ") && !text.contains("　") && text.contains(".") && !text.hasPrefix(".") && !text.hasSuffix(".")
            && text.unicodeScalars.allSatisfy { $0.isASCII }
            && !lower.hasPrefix("javascript:") && !lower.hasPrefix("file:") && !lower.hasPrefix("data:")
        if looksLikeHost { return "https://" + text }
        if lower.hasPrefix("localhost") && !text.contains(" ") { return "http://" + text }
        return searchBase + percentEncode(text)
    }

    /// 検索語を URL に入れられる形にする
    public static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// 表示用に短くする（https:// と末尾の / を省く）
    public static func display(_ url: String) -> String {
        var s = url
        for prefix in ["https://", "http://"] where s.lowercased().hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    /// アドレスのホスト名（しおりの名前に使う）
    public static func host(_ url: String) -> String {
        let d = display(url)
        return String(d.split(separator: "/").first ?? Substring(d))
    }
}
