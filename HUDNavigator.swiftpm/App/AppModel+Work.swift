import SwiftUI
import UIKit

/// ワーク画面の項目
enum WorkSection: String, CaseIterable, Identifiable {
    case focus, todo, notes, browser, script, agenda

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .focus: return "集中"
        case .todo: return "やること"
        case .notes: return "メモ"
        case .browser: return "ブラウザ"
        case .script: return "台本"
        case .agenda: return "予定"
        }
    }

    var systemImage: String {
        switch self {
        case .focus: return "timer"
        case .todo: return "checklist"
        case .notes: return "note.text"
        case .browser: return "globe"
        case .script: return "text.alignleft"
        case .agenda: return "calendar"
        }
    }

    /// この項目を HUD に出すウィジェット
    var widgets: [WidgetKind] {
        switch self {
        case .focus: return [.focusTimer, .timer]
        case .todo: return [.todo]
        case .notes: return [.notes]
        case .browser: return [.webPage]
        case .script: return [.teleprompter]
        case .agenda: return [.calendar, .worldClock]
        }
    }
}

/// ワーク（デスクワーク・勉強・発表）：タイマー・やること・メモ・ブラウザ・台本
extension AppModel {
    func configureWorkspace() {
        workspace.load(from: store)
        workspace.onEvent = { [unowned self] event in self.handleWorkspaceEvent(event) }
        web.darkMode = workspace.data.webDarkMode
        web.desktopMode = workspace.data.webDesktopMode
        web.zoom = workspace.data.webZoom
        web.onNavigated = { [unowned self] url in
            if self.workspace.data.lastURL != url { self.workspace.data.lastURL = url }
        }
    }

    private func handleWorkspaceEvent(_ event: WorkspaceModel.Event) {
        switch event {
        case .focusChanged(let transition):
            let title = transition.finished == .work ? "集中おつかれさまでした" : "休憩が終わりました"
            let minutes = Int((workspace.data.focus.duration(of: transition.next) / 60).rounded())
            let message = transition.startedNext ? "\(transition.next.displayName)を始めます（\(minutes)分）" : "次は\(transition.next.displayName)です"
            alerts.post(HUDAlert(category: .system, title: title, message: message, priority: .important, duration: 8, dedupeKey: "work-focus"), allowSpeech: false)
            if workspace.data.focus.speaksPhaseChanges {
                speech.speak("\(title)。\(message)", priority: .normal, force: true)
            }
            deviceTest.record("集中タイマー: \(transition.finished.displayName) → \(transition.next.displayName)")
        case .timerFinished(let label, let seconds):
            let title = label.isEmpty ? "タイマーが終わりました" : "「\(label)」のタイマーが終わりました"
            alerts.post(HUDAlert(category: .system, title: title, message: HUDFormat.spokenSeconds(seconds), priority: .important, duration: 10, dedupeKey: "work-timer"), allowSpeech: false)
            speech.speak(title, priority: .normal, force: true)
        case .prompterFinished:
            showToast("台本の最後まで進みました")
        }
    }

    /// ブラウザをまだ開いていなければ、前回のページ（なければホーム）を開く
    func openBrowserIfNeeded() {
        web.openIfNeeded(last: workspace.data.lastURL, home: workspace.data.homeURL)
    }

    /// ブラウザの設定を変えて保存する
    func setWeb(darkMode: Bool? = nil, desktopMode: Bool? = nil, zoom: Double? = nil) {
        if let darkMode {
            web.darkMode = darkMode
            workspace.data.webDarkMode = darkMode
        }
        if let desktopMode {
            web.desktopMode = desktopMode
            workspace.data.webDesktopMode = desktopMode
        }
        if let zoom {
            let z = zoom.clamped(to: 0.5...3)
            web.zoom = z
            workspace.data.webZoom = z
        }
    }

    /// 今のプリセットに、そのウィジェットが表示されているか
    func isWidgetShown(_ kind: WidgetKind) -> Bool { layout.contains(widget: kind) }

    func setWidget(_ kind: WidgetKind, shown: Bool) {
        if shown { showWidget(kind) } else { hideWidget(kind) }
    }

    /// 机で使うプリセットに切り替える
    func applyPreset(key: String) {
        guard let preset = presets.first(where: { $0.key == key }) else { return }
        applyPreset(preset.id)
        showToast("プリセット：\(preset.name)")
    }

    func performWork(_ command: AppCommand) -> CommandOutcome {
        switch command {
        case .setFocus(let on):
            if on {
                if workspace.focus.isRunning { return CommandOutcome(message: "集中タイマーはもう動いています。残り\(HUDFormat.spokenSeconds(workspace.focus.remaining(at: Date())))です。") }
                workspace.startFocus()
                if !isWidgetShown(.focusTimer) { showWidget(.focusTimer) }
                let minutes = Int((workspace.focus.remaining(at: Date()) / 60).rounded())
                return CommandOutcome(message: "\(workspace.focus.phase.displayName)を始めます。\(minutes)分です。")
            }
            guard workspace.focus.isActive else { return CommandOutcome(message: "集中タイマーは動いていません。") }
            workspace.stopFocus()
            return CommandOutcome(message: "集中タイマーを終了しました。")
        case .skipFocus:
            guard workspace.focus.isActive else { return CommandOutcome(message: "集中タイマーは動いていません。") }
            workspace.skipFocus()
            return CommandOutcome(message: "\(workspace.focus.phase.displayName)に進みました。", speak: false)
        case .startTimer(let seconds):
            workspace.startTimer(seconds: Double(seconds))
            if !isWidgetShown(.timer) { showWidget(.timer) }
            return CommandOutcome(message: "\(HUDFormat.spokenSeconds(Double(seconds)))のタイマーを始めました。")
        case .stopTimer:
            guard workspace.countdown.isActive else { return CommandOutcome(message: "タイマーは動いていません。") }
            workspace.stopTimer()
            return CommandOutcome(message: "タイマーを止めました。")
        case .setStopwatch(let on):
            if on {
                workspace.setStopwatch(running: true)
                if !isWidgetShown(.timer) { showWidget(.timer) }
                return CommandOutcome(message: "ストップウォッチを始めました。")
            }
            guard workspace.stopwatch.isRunning else { return CommandOutcome(message: "ストップウォッチは動いていません。") }
            workspace.setStopwatch(running: false)
            return CommandOutcome(message: "ストップウォッチを止めました。\(HUDFormat.spokenSeconds(workspace.stopwatch.elapsed(at: Date())))です。")
        case .addTodo(let title):
            guard let item = workspace.data.addTodo(title) else { return CommandOutcome(message: "追加する内容が分かりませんでした。") }
            return CommandOutcome(message: "やることに「\(item.title)」を追加しました。")
        case .completeTodo(let name):
            let finished = name.isEmpty ? workspace.data.completeNextTodo() : workspace.data.completeTodo(matching: name)
            guard let finished else {
                return CommandOutcome(message: name.isEmpty ? "終わっていないやることはありません。" : "「\(name)」に当てはまるやることが見つかりませんでした。")
            }
            let left = workspace.data.pendingTodos.count
            return CommandOutcome(message: "「\(finished.title)」を完了にしました。" + (left == 0 ? "すべて終わりました。" : "残り\(left)件です。"))
        case .addNote(let text):
            let note = workspace.data.appendToSelectedNote(text)
            return CommandOutcome(message: "「\(note.displayTitle)」にメモしました。")
        case .openWeb(let query):
            guard WebAddress.resolve(query) != nil else { return CommandOutcome(message: "開くページが分かりませんでした。") }
            web.open(query)
            if !isWidgetShown(.webPage) { showWidget(.webPage) }
            if !isHUDVisible {
                workSection = .browser
                selectedTab = .work
            }
            return CommandOutcome(message: "ブラウザで「\(query)」を開きます。", speak: false)
        case .webScroll(let direction):
            guard web.hasLoaded else { return CommandOutcome(message: "ブラウザでページを開いていません。") }
            web.scroll(byScreens: direction == .down ? 0.8 : -0.8)
            return CommandOutcome(message: direction == .down ? "下へ送りました。" : "上へ戻しました。", speak: false)
        case .webBack:
            guard web.canGoBack else { return CommandOutcome(message: "前のページはありません。") }
            web.goBack()
            return CommandOutcome(message: "前のページに戻りました。", speak: false)
        case .setTeleprompter(let on):
            guard workspace.scriptTotal > 0 else {
                workSection = .script
                selectedTab = .work
                return CommandOutcome(message: "台本がまだありません。ワーク画面で文章を入れてください。")
            }
            if on && !isWidgetShown(.teleprompter) { showWidget(.teleprompter) }
            workspace.setPrompter(running: on)
            return CommandOutcome(message: on ? "台本を流します。" : "台本を止めました。", speak: false)
        case .calculate(let expression):
            guard let result = workspace.calculate(expression) else { return CommandOutcome(message: "計算できませんでした。") }
            return CommandOutcome(message: "\(expression) = \(result)", detail: nil)
        default:
            return CommandOutcome(message: "")
        }
    }
}
