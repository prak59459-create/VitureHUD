import SwiftUI

// ワーク（デスクワーク・勉強・発表）のウィジェット：メモ・やること・集中タイマー・タイマー・予定・ブラウザ・台本・世界時計

/// 左右に分けて描く 3D 表示のとき、何番目の目か（0 = 左・ふつうの表示）。ブラウザは 1 つしかないので左だけに出す。
private struct HUDEyeIndexKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var hudEyeIndex: Int {
        get { self[HUDEyeIndexKey.self] }
        set { self[HUDEyeIndexKey.self] = newValue }
    }
}

/// 見出し＋中身（行を並べるウィジェットの共通の形）
struct ListPanel<Content: View>: View {
    let ctx: WidgetContext
    var icon: String
    var title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        let t = ctx.typography
        VStack(alignment: .leading, spacing: t.body(8)) {
            if ctx.config.showsLabel {
                HStack(spacing: t.body(8)) {
                    Image(systemName: icon).foregroundStyle(ctx.accent)
                    Text(title).foregroundStyle(ctx.secondary)
                    Spacer(minLength: 4)
                    if let trailing { Text(trailing).foregroundStyle(ctx.secondary).monospacedDigit() }
                }
                .font(t.bodyFont(22, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

/// 何もないときの案内
struct WidgetHint: View {
    let ctx: WidgetContext
    var text: String

    var body: some View {
        Text(text)
            .font(ctx.typography.bodyFont(22, weight: .medium))
            .foregroundStyle(ctx.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 進み具合の輪
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var track: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - メモ

struct NotesWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let t = ctx.typography
        let note = model.workspace.data.selectedNote
        let title = (note?.title.isEmpty ?? true) ? "メモ" : (note?.title ?? "メモ")
        ListPanel(ctx: ctx, icon: "note.text", title: title) {
            if let note, !note.text.isEmpty {
                Text(note.text)
                    .font(t.bodyFont(26, weight: .medium))
                    .foregroundStyle(ctx.text)
                    .lineSpacing(t.body(6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                WidgetHint(ctx: ctx, text: "「メモ、牛乳を買う」と話すか、ワーク画面で書いてください")
            }
        }
    }
}

// MARK: - やること

struct TodoWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let t = ctx.typography
        let data = model.workspace.data
        let pending = data.pendingTodos
        let done = data.doneTodos
        let rowHeight = t.body(26) * 1.45
        ListPanel(ctx: ctx, icon: "checklist", title: "やること", trailing: data.todos.isEmpty ? nil : "\(done.count)/\(data.todos.count)") {
            if data.todos.isEmpty {
                WidgetHint(ctx: ctx, text: "「やることに〇〇を追加」と話すか、ワーク画面で追加してください")
            } else {
                GeometryReader { geo in
                    let rows = max(1, Int(geo.size.height / rowHeight))
                    // 終わっていないものを先に。入りきらない分は「ほか n 件」
                    let all = pending + done
                    let shown = all.count > rows ? Array(all.prefix(max(1, rows - 1))) : all
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { item in
                            HStack(spacing: t.body(8)) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? ctx.secondary : ctx.accent)
                                Text(item.title)
                                    .strikethrough(item.isDone)
                                    .foregroundStyle(item.isDone ? ctx.secondary.opacity(0.7) : ctx.text)
                            }
                            .frame(height: rowHeight, alignment: .leading)
                        }
                        if all.count > shown.count {
                            Text("ほか \(all.count - shown.count) 件")
                                .foregroundStyle(ctx.secondary)
                                .frame(height: rowHeight, alignment: .leading)
                        }
                    }
                    .font(t.bodyFont(26, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - 集中タイマー

struct FocusTimerWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let focus = model.workspace.focus
        let settings = model.workspace.data.focus
        let t = ctx.typography
        if focus.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                let color = focus.phase.isBreak ? ctx.secondary : ctx.accent
                HStack(spacing: t.size(0.12)) {
                    ProgressRing(progress: focus.progress(at: now, settings: settings), color: color, track: ctx.secondary.opacity(0.25), lineWidth: max(3, t.size(0.07)))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Image(systemName: focus.phase.isBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                                .font(.system(size: t.size(0.22), weight: .semibold))
                                .foregroundStyle(color)
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(HUDFormat.timer(focus.remaining(at: now)))
                            .font(t.primary)
                            .monospacedDigit()
                            .foregroundStyle(focus.isPaused ? ctx.secondary : ctx.text)
                            .contentTransition(.numericText(countsDown: true))
                        if ctx.config.showsLabel {
                            Text(focus.isPaused ? "一時停止中" : (focus.phase == .work ? "集中・\(focus.currentRound) 回目" : focus.phase.displayName))
                                .font(t.secondary)
                                .foregroundStyle(ctx.secondary)
                        }
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            MetricView(ctx: ctx, icon: "timer", value: HUDFormat.timer(settings.duration(of: .work)), caption: "「集中を始めて」で開始")
        }
    }
}

// MARK: - タイマー・ストップウォッチ

struct TimerWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let countdown = model.workspace.countdown
        let stopwatch = model.workspace.stopwatch
        if countdown.isActive {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let left = countdown.remaining(at: timeline.date)
                MetricView(
                    ctx: ctx,
                    icon: ctx.config.compact ? nil : "timer",
                    value: HUDFormat.timer(left),
                    caption: countdown.isPaused ? "一時停止中" : (countdown.label.isEmpty ? "タイマー" : countdown.label),
                    valueColor: left <= 10 && countdown.isRunning ? ctx.warning : nil
                )
            }
        } else if stopwatch.isActive {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                MetricView(
                    ctx: ctx,
                    icon: ctx.config.compact ? nil : "stopwatch",
                    value: HUDFormat.stopwatch(stopwatch.elapsed(at: timeline.date)),
                    caption: stopwatch.isRunning ? "ストップウォッチ" : "一時停止中"
                )
            }
        } else {
            MetricView(ctx: ctx, icon: "timer", value: "--:--", caption: "「5分タイマー」で開始")
        }
    }
}

// MARK: - 今日の予定

struct CalendarWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let t = ctx.typography
        let calendar = model.calendar
        let rowHeight = t.body(24) * 1.5
        ListPanel(ctx: ctx, icon: "calendar", title: "予定") {
            switch calendar.access {
            case .granted:
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let now = timeline.date
                    let events = calendar.upcoming(now: now, limit: 12)
                    if events.isEmpty {
                        WidgetHint(ctx: ctx, text: "今日・明日の予定はありません")
                    } else {
                        GeometryReader { geo in
                            let rows = max(1, Int(geo.size.height / rowHeight))
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(events.prefix(rows)) { event in
                                    let current = event.isNow(now)
                                    HStack(spacing: t.body(10)) {
                                        Text(Self.timeLabel(event, now: now))
                                            .foregroundStyle(current ? ctx.accent : ctx.secondary)
                                            .monospacedDigit()
                                        Text(event.title)
                                            .foregroundStyle(ctx.text)
                                    }
                                    .fontWeight(current ? .bold : .medium)
                                    .frame(height: rowHeight, alignment: .leading)
                                }
                            }
                            .font(t.bodyFont(24, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            case .unknown:
                WidgetHint(ctx: ctx, text: "ワーク画面でカレンダーを許可してください")
            case .denied:
                WidgetHint(ctx: ctx, text: "カレンダーが許可されていません")
            case .unavailable:
                WidgetHint(ctx: ctx, text: "この版ではカレンダーを使えません")
            }
        }
    }

    /// 「10:00」「終日」「明日 9:00」
    static func timeLabel(_ event: AgendaEvent, now: Date) -> String {
        let tomorrow = !Calendar.current.isDate(event.start, inSameDayAs: now) && event.start > now
        if event.isAllDay { return tomorrow ? "明日" : "終日" }
        return (tomorrow ? "明日 " : "") + HUDFormat.clock(event.start)
    }
}

// MARK: - ブラウザ

struct WebPageWidget: View {
    @Environment(AppModel.self) private var model
    @Environment(\.hudEyeIndex) private var eye
    let ctx: WidgetContext

    private var host: WebHost? {
        switch ctx.surface {
        case .external: return .glasses
        case .deviceFullScreen: return .deviceHUD
        default: return nil
        }
    }

    var body: some View {
        let browser = model.web
        let radius = max(4, ctx.style.cornerRadius * 0.6)
        if let host, eye == 0 {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Color.black
                    WebHostView(browser: browser, host: host, isActive: browser.activeHost == host, allowsTouch: host == .deviceHUD)
                    if !browser.hasLoaded {
                        placeholder
                    }
                    if browser.isLoading {
                        Rectangle()
                            .fill(ctx.accent)
                            .frame(width: geo.size.width * max(0.05, browser.progress), height: max(2, geo.size.height * 0.006))
                    }
                    if host == .glasses {
                        // 端末のトラックパッドで動かすカーソル
                        let d = max(14, geo.size.height * 0.03)
                        Circle()
                            .fill(ctx.accent.opacity(browser.isTextFieldFocused ? 0.35 : 0.85))
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1).padding(1))
                            .frame(width: d, height: d)
                            .position(x: browser.cursor.x * geo.size.width, y: browser.cursor.y * geo.size.height)
                            .allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onAppear {
                browser.register(host)
                model.openBrowserIfNeeded()
            }
            .onDisappear { browser.unregister(host) }
        } else {
            placeholder
                .background(Color.black, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    private var placeholder: some View {
        let t = ctx.typography
        let browser = model.web
        return VStack(spacing: t.body(10)) {
            Image(systemName: "globe")
                .font(.system(size: t.body(60), weight: .light))
                .foregroundStyle(ctx.accent)
            Text(browser.title.isEmpty ? "ブラウザ" : browser.title)
                .font(t.bodyFont(26, weight: .semibold))
                .foregroundStyle(ctx.text)
            Text(browser.urlString.isEmpty ? "ワーク画面でページを開いてください" : WebAddress.display(browser.urlString))
                .font(t.bodyFont(20, weight: .medium))
                .foregroundStyle(ctx.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(t.body(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 台本（プロンプター）

struct TeleprompterWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let t = ctx.typography
        let work = model.workspace
        let fontSize = t.body(40)
        let lineHeight = fontSize * 1.5
        if work.data.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            WidgetHint(ctx: ctx, text: "ワーク → 台本 に、読みたい文章を入れてください")
        } else {
            GeometryReader { geo in
                // 全角 1 文字がおよそ文字サイズと同じ幅
                let perLine = max(6, Int(geo.size.width / fontSize))
                let lines = work.scriptLines(maxCharacters: perLine)
                let total = Teleprompter.totalCharacters(lines)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !work.prompter.isRunning || ctx.surface == .thumbnail)) { timeline in
                    let position = work.prompter.characterPosition(at: timeline.date, charactersPerMinute: work.data.scriptCharactersPerMinute, total: total)
                    let linePosition = Teleprompter.linePosition(lines, character: position)
                    let current = min(max(0, lines.count - 1), Int(linePosition))
                    let first = max(0, current - 3)
                    let last = min(lines.count - 1, current + 8)
                    ZStack(alignment: .topLeading) {
                        if first <= last {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(first...last, id: \.self) { i in
                                    Text(lines[i].text)
                                        .foregroundStyle(i == current ? ctx.text : ctx.secondary.opacity(i < current ? 0.3 : 0.75))
                                        .frame(height: lineHeight, alignment: .leading)
                                }
                            }
                            .font(t.bodyFont(40, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: true)
                            // 行が多くてもパネルの大きさは変えない（はみ出した分は切り取る）
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                            // 今読んでいる行が、上から 3 割の位置に来るように送る
                            .offset(y: geo.size.height * 0.3 - CGFloat(linePosition - Double(first)) * lineHeight)
                        }
                        // 読む位置の目印
                        Rectangle()
                            .fill(ctx.accent)
                            .frame(width: max(3, fontSize * 0.1), height: lineHeight * 0.8)
                            .offset(x: -fontSize * 0.3, y: geo.size.height * 0.3 + lineHeight * 0.1)
                        Text(work.prompter.isRunning
                             ? "残り \(HUDFormat.timer(Teleprompter.remainingSeconds(total: total, position: position, charactersPerMinute: work.data.scriptCharactersPerMinute)))"
                             : (position >= Double(total) && total > 0 ? "おわり" : "停止中"))
                            .font(t.bodyFont(18, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(ctx.secondary)
                            .padding(.horizontal, t.body(8))
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .padding(.leading, fontSize * 0.4)
            .clipped()
        }
    }
}

// MARK: - 世界時計

struct WorldClockWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let t = ctx.typography
        let cities = model.workspace.data.worldClocks
        let rowHeight = t.body(26) * 1.45
        ListPanel(ctx: ctx, icon: "globe.asia.australia", title: "世界時計") {
            if cities.isEmpty {
                WidgetHint(ctx: ctx, text: "ワーク画面で都市を選んでください")
            } else {
                TimelineView(.periodic(from: .now, by: 10)) { timeline in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(cities) { city in
                            let info = city.timeText(at: timeline.date)
                            HStack(spacing: t.body(8)) {
                                Text(city.name).foregroundStyle(ctx.secondary)
                                Spacer(minLength: 4)
                                if !info.dayNote.isEmpty {
                                    Text(info.dayNote).font(t.bodyFont(18, weight: .medium)).foregroundStyle(ctx.secondary)
                                }
                                Text(info.time).foregroundStyle(ctx.text).monospacedDigit()
                            }
                            .frame(height: rowHeight)
                        }
                    }
                    .font(t.bodyFont(26, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
            }
        }
    }
}
