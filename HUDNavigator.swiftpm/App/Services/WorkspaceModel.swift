import SwiftUI
import Observation
import UserNotifications

/// ワーク（メモ・やること・集中タイマー・タイマー・ストップウォッチ・台本）の状態。端末内に保存する。
/// タイマー類は「終わる時刻」を持つので、アプリを閉じて開き直しても正しい残り時間になる。
@MainActor
@Observable
final class WorkspaceModel {
    var data = WorkspaceData() {
        didSet { if data != oldValue { scheduleSave() } }
    }
    private(set) var focus = FocusTimerState()
    private(set) var countdown = CountdownState()
    private(set) var stopwatch = StopwatchState()
    private(set) var prompter = TeleprompterState()
    /// 最後の計算（式 = 答え）
    private(set) var lastCalculation: String?

    enum Event {
        case focusChanged(FocusTimerState.Transition)
        case timerFinished(label: String, seconds: TimeInterval)
        case prompterFinished
    }

    /// 動いているタイマーなど（保存して、次の起動で続きから）
    private struct Runtime: Codable {
        var focus = FocusTimerState()
        var countdown = CountdownState()
        var stopwatch = StopwatchState()
        var prompter = TeleprompterState()
    }

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var store: JSONFileStore?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var cachedLines: (script: String, width: Int, lines: [Teleprompter.Line])?

    // MARK: - 保存

    func load(from store: JSONFileStore) {
        self.store = store
        if let saved = store.load(WorkspaceData.self, from: "workspace") {
            data = saved
        }
        if let runtime = store.load(Runtime.self, from: "workspace-state") {
            focus = runtime.focus
            countdown = runtime.countdown
            stopwatch = runtime.stopwatch
            prompter = runtime.prompter
            // 台本は開き直したら止めておく（勝手に進んでいると読めない）
            if prompter.isRunning { prompter.pause(now: Date(), charactersPerMinute: data.scriptCharactersPerMinute, total: scriptTotal) }
        }
        tick()
        updateTicker()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let store else { return }
        try? store.save(data, as: "workspace")
        try? store.save(Runtime(focus: focus, countdown: countdown, stopwatch: stopwatch, prompter: prompter), as: "workspace-state")
    }

    func deleteAll() {
        stopFocus()
        stopTimer()
        stopwatch.reset()
        prompter = TeleprompterState()
        data = WorkspaceData()
        lastCalculation = nil
        saveNow()
    }

    private func runtimeChanged() {
        updateTicker()
        scheduleSave()
    }

    // MARK: - 定期処理

    /// 何かが動いている間だけ 0.5 秒ごとに確認する
    private func updateTicker() {
        let needed = focus.isRunning || countdown.isRunning || prompter.isRunning
        if needed, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } else if !needed, let ticker {
            ticker.invalidate()
            self.ticker = nil
        }
    }

    /// 終わったタイマーがないか確認する（画面に戻ったときにも呼ぶ）
    func tick(now: Date = Date()) {
        var changed = false
        if let transition = focus.tick(now: now, settings: data.focus) {
            finishFocusPhase(transition, at: now)
            changed = true
        }
        if countdown.isRunning {
            let label = countdown.label
            let seconds = countdown.duration
            if countdown.tick(now: now) {
                onEvent?(.timerFinished(label: label, seconds: seconds))
                changed = true
            }
        }
        if prompter.isRunning {
            let total = scriptTotal
            if prompter.characterPosition(at: now, charactersPerMinute: data.scriptCharactersPerMinute, total: total) >= Double(total) {
                prompter.pause(now: now, charactersPerMinute: data.scriptCharactersPerMinute, total: total)
                onEvent?(.prompterFinished)
                changed = true
            }
        }
        if changed { runtimeChanged() }
    }

    private func finishFocusPhase(_ transition: FocusTimerState.Transition, at now: Date) {
        if transition.finished == .work { data.logFocus(seconds: transition.finishedSeconds, at: now) }
        onEvent?(.focusChanged(transition))
        scheduleFocusNotification()
    }

    // MARK: - 集中タイマー

    func startFocus() {
        if focus.isPaused {
            focus.resume(now: Date())
        } else if !focus.isRunning {
            focus.start(now: Date(), settings: data.focus)
        }
        scheduleFocusNotification()
        runtimeChanged()
    }

    func pauseFocus() {
        focus.pause(now: Date())
        cancelNotification("work-focus")
        runtimeChanged()
    }

    func toggleFocus() {
        if focus.isRunning { pauseFocus() } else { startFocus() }
    }

    func stopFocus() {
        // 途中まで集中した分は記録する
        if focus.phase == .work {
            let spent = data.focus.duration(of: .work) - focus.remaining(at: Date())
            if spent >= 60 { data.logFocus(seconds: spent) }
        }
        focus.stop()
        cancelNotification("work-focus")
        runtimeChanged()
    }

    func resetFocus() {
        focus.reset()
        cancelNotification("work-focus")
        runtimeChanged()
    }

    func skipFocus() {
        guard focus.isActive else { return }
        let now = Date()
        if focus.isPaused { focus.resume(now: now) }
        let transition = focus.advance(now: now, settings: data.focus)
        finishFocusPhase(transition, at: now)
        runtimeChanged()
    }

    /// 今日集中した時間（進行中の分も含む）
    func focusSecondsToday(now: Date = Date()) -> Double {
        var total = data.focusSeconds(on: now)
        if focus.phase == .work { total += data.focus.duration(of: .work) - focus.remaining(at: now) }
        return total
    }

    // MARK: - タイマー・ストップウォッチ

    func startTimer(seconds: TimeInterval, label: String = "") {
        countdown.start(seconds: seconds, label: label, now: Date())
        scheduleTimerNotification()
        runtimeChanged()
    }

    func toggleTimer() {
        let now = Date()
        if countdown.isRunning {
            countdown.pause(now: now)
            cancelNotification("work-timer")
        } else if countdown.isPaused {
            countdown.resume(now: now)
            scheduleTimerNotification()
        }
        runtimeChanged()
    }

    func addToTimer(seconds: TimeInterval) {
        guard countdown.isActive else { return }
        countdown.add(seconds: seconds, now: Date())
        if countdown.isRunning { scheduleTimerNotification() }
        runtimeChanged()
    }

    func stopTimer() {
        countdown.stop()
        cancelNotification("work-timer")
        runtimeChanged()
    }

    func toggleStopwatch() {
        let now = Date()
        if stopwatch.isRunning { stopwatch.pause(now: now) } else { stopwatch.start(now: now) }
        runtimeChanged()
    }

    func setStopwatch(running: Bool) {
        if running != stopwatch.isRunning { toggleStopwatch() }
    }

    func lapStopwatch() {
        stopwatch.lap(now: Date())
        runtimeChanged()
    }

    func resetStopwatch() {
        stopwatch.reset()
        runtimeChanged()
    }

    // MARK: - 台本（プロンプター）

    /// 表示用に行へ分けた台本（1 行の文字数ごとに作り直す）
    func scriptLines(maxCharacters: Int) -> [Teleprompter.Line] {
        if let c = cachedLines, c.script == data.script, c.width == maxCharacters { return c.lines }
        let lines = Teleprompter.lines(data.script, maxCharacters: maxCharacters)
        cachedLines = (data.script, maxCharacters, lines)
        return lines
    }

    /// 台本の文字数（空白の行は数えない）
    var scriptTotal: Int { Teleprompter.totalCharacters(scriptLines(maxCharacters: 1000)) }

    func prompterPosition(at now: Date = Date()) -> Double {
        prompter.characterPosition(at: now, charactersPerMinute: data.scriptCharactersPerMinute, total: scriptTotal)
    }

    func setPrompter(running: Bool) {
        let now = Date()
        let total = scriptTotal
        if running {
            guard total > 0 else { return }
            if prompterPosition(at: now) >= Double(total) { prompter.restart(now: now) }
            prompter.play(now: now)
        } else {
            prompter.pause(now: now, charactersPerMinute: data.scriptCharactersPerMinute, total: total)
        }
        runtimeChanged()
    }

    func togglePrompter() { setPrompter(running: !prompter.isRunning) }

    func seekPrompter(by characters: Double) {
        prompter.seek(by: characters, now: Date(), charactersPerMinute: data.scriptCharactersPerMinute, total: scriptTotal)
        runtimeChanged()
    }

    func restartPrompter() {
        prompter.restart(now: Date())
        runtimeChanged()
    }

    /// 速さを変える（動いている間も位置が飛ばないように、今の位置を確定してから変える）
    func setPrompterSpeed(_ charactersPerMinute: Double) {
        let now = Date()
        let wasRunning = prompter.isRunning
        if wasRunning { prompter.pause(now: now, charactersPerMinute: data.scriptCharactersPerMinute, total: scriptTotal) }
        data.scriptCharactersPerMinute = charactersPerMinute.clamped(to: 60...900)
        if wasRunning { prompter.play(now: now) }
        runtimeChanged()
    }

    // MARK: - 計算

    @discardableResult
    func calculate(_ expression: String) -> String? {
        guard let value = MathExpression.evaluate(expression) else { return nil }
        let text = MathExpression.format(value)
        lastCalculation = "\(expression) = \(text)"
        return text
    }

    // MARK: - 通知（アプリを閉じている間に終わったとき用）

    private func scheduleTimerNotification() {
        cancelNotification("work-timer")
        guard countdown.isRunning else { return }
        let left = countdown.remaining(at: Date())
        guard left >= 1 else { return }
        let title = countdown.label.isEmpty ? "タイマーが終わりました" : "「\(countdown.label)」のタイマーが終わりました"
        schedule(id: "work-timer", title: title, body: HUDFormat.spokenSeconds(countdown.duration), after: left)
    }

    private func scheduleFocusNotification() {
        cancelNotification("work-focus")
        guard focus.isRunning else { return }
        let left = focus.remaining(at: Date())
        guard left >= 1 else { return }
        let next = focus.nextPhase(settings: data.focus)
        let title = focus.phase == .work ? "集中おつかれさまでした" : "休憩が終わりました"
        schedule(id: "work-focus", title: title, body: "次は\(next.displayName)です。", after: left)
    }

    private func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func cancelNotification(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
