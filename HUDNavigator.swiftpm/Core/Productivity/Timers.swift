import Foundation

// 集中タイマー（ポモドーロ）・タイマー・ストップウォッチ・台本の送り・かんたんな計算。
// どれも「開始した時刻」から今の値を計算する（アプリが止まっていても正しく進む）。

public struct FocusSettings: Codable, Hashable, Sendable {
    public var workMinutes: Double
    public var shortBreakMinutes: Double
    public var longBreakMinutes: Double
    /// 何回集中したら長い休憩にするか
    public var roundsBeforeLongBreak: Int
    /// 終わったら自動で次（休憩・集中）を始める
    public var autoContinue: Bool
    public var speaksPhaseChanges: Bool

    public init(workMinutes: Double = 25, shortBreakMinutes: Double = 5, longBreakMinutes: Double = 15, roundsBeforeLongBreak: Int = 4, autoContinue: Bool = true, speaksPhaseChanges: Bool = true) {
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.roundsBeforeLongBreak = roundsBeforeLongBreak
        self.autoContinue = autoContinue
        self.speaksPhaseChanges = speaksPhaseChanges
    }

    enum CodingKeys: String, CodingKey { case workMinutes, shortBreakMinutes, longBreakMinutes, roundsBeforeLongBreak, autoContinue, speaksPhaseChanges }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        workMinutes = c.value(.workMinutes, default: d.workMinutes)
        shortBreakMinutes = c.value(.shortBreakMinutes, default: d.shortBreakMinutes)
        longBreakMinutes = c.value(.longBreakMinutes, default: d.longBreakMinutes)
        roundsBeforeLongBreak = c.value(.roundsBeforeLongBreak, default: d.roundsBeforeLongBreak)
        autoContinue = c.value(.autoContinue, default: d.autoContinue)
        speaksPhaseChanges = c.value(.speaksPhaseChanges, default: d.speaksPhaseChanges)
    }

    public func sanitized() -> FocusSettings {
        var s = self
        s.workMinutes = workMinutes.clamped(to: 1...180)
        s.shortBreakMinutes = shortBreakMinutes.clamped(to: 1...60)
        s.longBreakMinutes = longBreakMinutes.clamped(to: 1...120)
        s.roundsBeforeLongBreak = roundsBeforeLongBreak.clamped(to: 1...12)
        return s
    }

    public func duration(of phase: FocusPhase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .work: return workMinutes * 60
        case .shortBreak: return shortBreakMinutes * 60
        case .longBreak: return longBreakMinutes * 60
        }
    }
}

public enum FocusPhase: String, Codable, CaseIterable, Sendable {
    case idle, work, shortBreak, longBreak

    public var displayName: String {
        switch self {
        case .idle: return "待機"
        case .work: return "集中"
        case .shortBreak: return "休憩"
        case .longBreak: return "長い休憩"
        }
    }

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

/// 集中タイマーの状態
public struct FocusTimerState: Codable, Hashable, Sendable {
    public var phase: FocusPhase = .idle
    /// 動いているとき：この時刻に今の区切りが終わる
    public var endsAt: Date?
    /// 一時停止中：残り秒
    public var pausedRemaining: TimeInterval?
    /// 終わった集中の回数（長い休憩のあと 0 に戻さず数え続ける）
    public var completedRounds: Int = 0

    public init() {}

    public var isRunning: Bool { phase != .idle && endsAt != nil }
    public var isPaused: Bool { phase != .idle && pausedRemaining != nil }
    public var isActive: Bool { phase != .idle }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// 今の区切りの進み具合（0〜1）
    public func progress(at now: Date, settings: FocusSettings) -> Double {
        let total = settings.duration(of: phase)
        guard total > 0 else { return 0 }
        return (1 - remaining(at: now) / total).clamped(to: 0...1)
    }

    /// いま何回目の集中か（1 始まり）
    public var currentRound: Int { completedRounds + (phase == .work ? 1 : 0) }

    public mutating func start(now: Date, settings: FocusSettings) {
        phase = .work
        pausedRemaining = nil
        endsAt = now.addingTimeInterval(settings.duration(of: .work))
    }

    public mutating func pause(now: Date) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    public mutating func resume(now: Date) {
        guard let left = pausedRemaining, phase != .idle else { return }
        endsAt = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    public mutating func stop() {
        phase = .idle
        endsAt = nil
        pausedRemaining = nil
    }

    public mutating func reset() {
        stop()
        completedRounds = 0
    }

    /// 次の区切り（集中 → 休憩 → 集中 …）
    public func nextPhase(settings: FocusSettings) -> FocusPhase {
        switch phase {
        case .idle: return .work
        case .work:
            let rounds = completedRounds + 1
            return rounds % max(1, settings.roundsBeforeLongBreak) == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: return .work
        }
    }

    public struct Transition: Equatable, Sendable {
        public var finished: FocusPhase
        public var next: FocusPhase
        /// 終わった区切りの長さ（秒）
        public var finishedSeconds: TimeInterval
        /// 自動で次を始めたか
        public var startedNext: Bool
    }

    /// 今の区切りを終わらせて次へ（スキップ・時間切れ共通）
    public mutating func advance(now: Date, settings: FocusSettings, elapsedInPhase: TimeInterval? = nil, autoStart: Bool = true) -> Transition {
        let finished = phase
        let next = nextPhase(settings: settings)
        let total = settings.duration(of: finished)
        let spent = elapsedInPhase ?? max(0, total - remaining(at: now))
        if finished == .work { completedRounds += 1 }
        if autoStart {
            phase = next
            pausedRemaining = nil
            endsAt = now.addingTimeInterval(settings.duration(of: next))
        } else {
            phase = .idle
            endsAt = nil
            pausedRemaining = nil
        }
        return Transition(finished: finished, next: next, finishedSeconds: spent, startedNext: autoStart)
    }

    /// 定期的に呼ぶ。区切りが終わっていたら次へ進めて、何が起きたかを返す。
    public mutating func tick(now: Date, settings: FocusSettings) -> Transition? {
        guard isRunning, let endsAt, now >= endsAt else { return nil }
        return advance(now: now, settings: settings, elapsedInPhase: settings.duration(of: phase), autoStart: settings.autoContinue)
    }
}

/// カウントダウンのタイマー
public struct CountdownState: Codable, Hashable, Sendable {
    public var label: String = ""
    public var duration: TimeInterval = 0
    public var endsAt: Date?
    public var pausedRemaining: TimeInterval?

    public init() {}

    public var isRunning: Bool { endsAt != nil }
    public var isPaused: Bool { pausedRemaining != nil }
    public var isActive: Bool { isRunning || isPaused }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    public func progress(at now: Date) -> Double {
        guard duration > 0, isActive else { return 0 }
        return (1 - remaining(at: now) / duration).clamped(to: 0...1)
    }

    public mutating func start(seconds: TimeInterval, label: String = "", now: Date) {
        duration = max(1, seconds)
        self.label = label
        endsAt = now.addingTimeInterval(duration)
        pausedRemaining = nil
    }

    public mutating func pause(now: Date) {
        guard isRunning else { return }
        pausedRemaining = remaining(at: now)
        endsAt = nil
    }

    public mutating func resume(now: Date) {
        guard let left = pausedRemaining else { return }
        endsAt = now.addingTimeInterval(left)
        pausedRemaining = nil
    }

    public mutating func add(seconds: TimeInterval, now: Date) {
        if let endsAt {
            self.endsAt = max(now, endsAt.addingTimeInterval(seconds))
        } else if let left = pausedRemaining {
            pausedRemaining = max(0, left + seconds)
        }
        duration = max(1, duration + seconds)
    }

    public mutating func stop() {
        endsAt = nil
        pausedRemaining = nil
    }

    /// 時間切れなら止めて true を返す
    public mutating func tick(now: Date) -> Bool {
        guard let endsAt, now >= endsAt else { return false }
        stop()
        return true
    }
}

public struct StopwatchState: Codable, Hashable, Sendable {
    public var startedAt: Date?
    public var accumulated: TimeInterval = 0
    public var laps: [TimeInterval] = []

    public init() {}

    public var isRunning: Bool { startedAt != nil }
    public var isActive: Bool { isRunning || accumulated > 0 }

    public func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public mutating func start(now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    public mutating func pause(now: Date) {
        guard startedAt != nil else { return }
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    public mutating func lap(now: Date) {
        guard isActive else { return }
        laps.append(elapsed(at: now))
        if laps.count > 50 { laps.removeFirst(laps.count - 50) }
    }

    public mutating func reset() {
        startedAt = nil
        accumulated = 0
        laps = []
    }
}

public extension HUDFormat {
    /// 残り時間（例: "24:59"、1 時間以上は "1:05:00"）
    static func timer(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(0, seconds).rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 経過時間（切り捨て。ストップウォッチ用）
    static func stopwatch(_ seconds: TimeInterval, tenths: Bool = false) -> String {
        guard seconds.isFinite else { return "--:--" }
        let clamped = max(0, seconds)
        let total = Int(clamped)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
        if tenths { text += String(format: ".%d", Int((clamped - Double(total)) * 10)) }
        return text
    }

    /// 読み上げ用の長さ（例: "5分"、"1分30秒"、"45秒"）
    static func spokenSeconds(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)時間") }
        if m > 0 { parts.append("\(m)分") }
        if s > 0 || parts.isEmpty { parts.append("\(s)秒") }
        return parts.joined()
    }
}

/// 台本（プロンプター）の送り
public struct TeleprompterState: Codable, Hashable, Sendable {
    /// 動いているとき：この時刻に position から読み始めた
    public var startedAt: Date?
    /// 止まっている間の位置（文字数）
    public var position: Double = 0

    public init() {}

    public var isRunning: Bool { startedAt != nil }

    /// 今読んでいる位置（先頭からの文字数）
    public func characterPosition(at now: Date, charactersPerMinute: Double, total: Int) -> Double {
        let moved = startedAt.map { max(0, now.timeIntervalSince($0)) * charactersPerMinute / 60 } ?? 0
        return min(Double(max(0, total)), position + moved)
    }

    public mutating func play(now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    public mutating func pause(now: Date, charactersPerMinute: Double, total: Int) {
        guard startedAt != nil else { return }
        position = characterPosition(at: now, charactersPerMinute: charactersPerMinute, total: total)
        startedAt = nil
    }

    /// 位置を動かす（文字数）。動いている間も使える。
    public mutating func seek(by delta: Double, now: Date, charactersPerMinute: Double, total: Int) {
        let current = characterPosition(at: now, charactersPerMinute: charactersPerMinute, total: total)
        position = (current + delta).clamped(to: 0...Double(max(0, total)))
        if startedAt != nil { startedAt = now }
    }

    public mutating func restart(now: Date) {
        position = 0
        if startedAt != nil { startedAt = now }
    }
}

public enum Teleprompter {
    public struct Line: Equatable, Sendable {
        public var text: String
        /// この行が始まる位置（先頭からの文字数）
        public var start: Int
        public var count: Int
    }

    /// 台本を表示用の行に分ける（改行で区切り、長い行は maxCharacters ごとに折り返す）
    public static func lines(_ script: String, maxCharacters: Int = 22) -> [Line] {
        let limit = max(4, maxCharacters)
        var result: [Line] = []
        var offset = 0
        for raw in script.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var rest = Substring(line)
            while !rest.isEmpty {
                let piece = rest.prefix(limit)
                result.append(Line(text: String(piece), start: offset, count: piece.count))
                offset += piece.count
                rest = rest.dropFirst(piece.count)
            }
        }
        return result
    }

    public static func totalCharacters(_ lines: [Line]) -> Int {
        lines.last.map { $0.start + $0.count } ?? 0
    }

    /// 位置（文字数）から「何行目のどのあたりか」（例: 2.5 ＝ 3 行目の真ん中）
    public static func linePosition(_ lines: [Line], character: Double) -> Double {
        guard !lines.isEmpty else { return 0 }
        for (i, line) in lines.enumerated() {
            let end = Double(line.start + line.count)
            if character < end {
                return Double(i) + (character - Double(line.start)) / Double(max(1, line.count))
            }
        }
        return Double(lines.count)
    }

    /// 読み終わるまでの残り秒
    public static func remainingSeconds(total: Int, position: Double, charactersPerMinute: Double) -> TimeInterval {
        guard charactersPerMinute > 0 else { return 0 }
        return max(0, Double(total) - position) / charactersPerMinute * 60
    }
}

/// かんたんな計算（四則・かっこ・パーセント）。「128かける3」のような言い方も読む。
public enum MathExpression {
    /// 話し言葉を式にする（計算でなければ nil）
    public static func normalize(_ spoken: String) -> String? {
        var s = spoken.applyingFullWidthToHalfWidth().lowercased()
        let replacements: [(String, String)] = [
            ("かける", "*"), ("掛ける", "*"), ("×", "*"), ("x", "*"),
            ("わる", "/"), ("割る", "/"), ("÷", "/"),
            ("たす", "+"), ("足す", "+"), ("プラス", "+"),
            ("ひく", "-"), ("引く", "-"), ("マイナス", "-"),
            ("パーセント", "%"), ("かっこ閉じ", ")"), ("かっことじ", ")"), ("かっこ", "("),
            ("は?", ""), ("は？", ""), ("はいくつ", ""), ("はいくら", ""), ("を計算して", ""), ("を計算", ""), ("計算して", ""), ("計算", ""),
            ("=", ""), ("、", ""), ("。", ""), ("?", ""), ("？", ""), (",", ""), (" ", ""), ("　", ""),
        ]
        for (from, to) in replacements { s = s.replacingOccurrences(of: from, with: to) }
        if s.hasSuffix("は") { s = String(s.dropLast()) }
        guard !s.isEmpty, s.allSatisfy({ "0123456789.+-*/()%".contains($0) }) else { return nil }
        // 数字だけ・演算子なしは計算ではない
        guard s.contains(where: { "+-*/%".contains($0) }), s.contains(where: \.isNumber) else { return nil }
        // 先頭の符号だけの式（"-5"）は計算とみなさない
        let body = s.hasPrefix("-") || s.hasPrefix("+") ? String(s.dropFirst()) : s
        guard body.contains(where: { "+-*/%".contains($0) }) else { return nil }
        return s
    }

    public static func evaluate(_ expression: String) -> Double? {
        var parser = Parser(Array(expression.filter { !$0.isWhitespace }))
        guard let value = parser.expression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// 結果の表示（整数はそのまま、小数は最大 6 桁）
    public static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    struct Parser {
        let chars: [Character]
        var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        var isAtEnd: Bool { index >= chars.count }
        var peek: Character? { index < chars.count ? chars[index] : nil }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while let op = peek, op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = factor() else { return nil }
            while let op = peek, op == "*" || op == "/" {
                index += 1
                guard let rhs = factor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func factor() -> Double? {
            guard let c = peek else { return nil }
            var value: Double
            if c == "-" || c == "+" {
                index += 1
                guard let inner = factor() else { return nil }
                return c == "-" ? -inner : inner
            }
            if c == "(" {
                index += 1
                guard let inner = expression(), peek == ")" else { return nil }
                index += 1
                value = inner
            } else {
                var text = ""
                while let d = peek, d.isNumber || d == "." {
                    text.append(d)
                    index += 1
                }
                guard let number = Double(text) else { return nil }
                value = number
            }
            while peek == "%" {
                index += 1
                value /= 100
            }
            return value
        }
    }
}
