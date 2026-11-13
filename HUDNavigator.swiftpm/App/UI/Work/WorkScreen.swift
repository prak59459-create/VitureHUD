import SwiftUI

/// ワーク：机での作業・勉強・発表に使う道具（集中タイマー・やること・メモ・ブラウザ・台本・予定）。
/// ここで操作した内容が、そのままグラスの HUD に出る。
struct WorkScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WorkHeader()
                    WorkPresetRow()
                    WorkSectionPicker()
                    switch model.workSection {
                    case .focus: FocusSection()
                    case .todo: TodoSection()
                    case .notes: NotesSection()
                    case .browser: BrowserSection()
                    case .script: ScriptSection()
                    case .agenda: AgendaSection()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 110)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct WorkHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let work = model.workspace
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ワーク").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("机での作業・勉強・発表に").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if work.focus.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    StatusChip(text: "\(work.focus.phase.displayName) \(HUDFormat.timer(work.focus.remaining(at: timeline.date)))", systemImage: "timer",
                               color: work.focus.phase.isBreak ? UIStyle.success : UIStyle.accent, showsDot: work.focus.isRunning)
                }
            } else {
                ConnectionChip()
            }
        }
    }
}

/// 机で使うプリセットへの切り替え
struct WorkPresetRow: View {
    @Environment(AppModel.self) private var model
    private let keys = ["desk", "focus", "browser", "presentation", "kitchen"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(keys, id: \.self) { key in
                    if let preset = model.presets.first(where: { $0.key == key }) {
                        Button {
                            model.applyPreset(preset.id)
                        } label: {
                            PresetCard(preset: preset, isSelected: preset.id == model.activePresetID, compact: true)
                        }
                        .buttonStyle(TilePressStyle())
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

struct WorkSectionPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorkSection.allCases) { section in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { model.workSection = section }
                    } label: {
                        SelectablePill(title: section.displayName, systemImage: section.systemImage, isSelected: model.workSection == section)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

/// 「グラスに表示」の切り替え（そのウィジェットを今のプリセットに出す・隠す）
struct HUDWidgetChip: View {
    @Environment(AppModel.self) private var model
    let kind: WidgetKind

    var body: some View {
        let shown = model.isWidgetShown(kind)
        Button {
            model.setWidget(kind, shown: !shown)
            model.showToast(shown ? "\(kind.displayName)を HUD から隠しました" : "\(kind.displayName)を HUD に表示しました")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: shown ? "eye.fill" : "eye.slash")
                Text(shown ? "HUD に表示中：\(kind.displayName)" : "HUD に表示：\(kind.displayName)").lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(shown ? Color.black : UIStyle.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(shown ? UIStyle.accent : UIStyle.accent.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: shown)
    }
}

extension View {
    /// 入力欄の面
    func fieldSurface(radius: CGFloat = 14) -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(UIStyle.fieldBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(UIStyle.cardStroke, lineWidth: 1))
    }
}

/// 丸いアイコンのボタン（再生・停止など）
struct RoundIconButton: View {
    var systemImage: String
    var label: String
    var prominent = false
    var size: CGFloat = 52
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : UIStyle.accent)
                .frame(width: size, height: size)
                .background(prominent ? UIStyle.accent : UIStyle.fieldBackground, in: Circle())
                .overlay(Circle().strokeBorder(prominent ? Color.clear : UIStyle.cardStroke, lineWidth: 1))
                .shadow(color: UIStyle.accent.opacity(prominent ? 0.4 : 0), radius: 10, y: 2)
        }
        .buttonStyle(TilePressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - 集中・タイマー

struct FocusSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FocusTimerCard()
            HStack(spacing: 8) {
                HUDWidgetChip(kind: .focusTimer)
                HUDWidgetChip(kind: .timer)
            }
            CountdownCard()
            StopwatchCard()
            FocusSettingsCard()
        }
    }
}

struct FocusTimerCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let work = model.workspace
        let focus = work.focus
        let color = focus.phase.isBreak ? UIStyle.success : UIStyle.accent
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let now = timeline.date
                ZStack {
                    ProgressRing(progress: focus.isActive ? focus.progress(at: now, settings: work.data.focus) : 0, color: color, track: Color.white.opacity(0.08), lineWidth: 12)
                    VStack(spacing: 4) {
                        Text(focus.isActive ? focus.phase.displayName : "集中タイマー")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(focus.isActive ? color : Color.secondary)
                        Text(HUDFormat.timer(focus.isActive ? focus.remaining(at: now) : work.data.focus.duration(of: .work)))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text(focus.isPaused ? "一時停止中" : (focus.isActive ? "\(focus.currentRound) 回目" : "今日 \(Int(work.focusSecondsToday(now: now) / 60)) 分"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 230, height: 230)
            }
            HStack(spacing: 18) {
                RoundIconButton(systemImage: "stop.fill", label: "終了") { work.stopFocus() }
                    .disabled(!focus.isActive)
                    .opacity(focus.isActive ? 1 : 0.4)
                RoundIconButton(systemImage: focus.isRunning ? "pause.fill" : "play.fill", label: focus.isRunning ? "一時停止" : "開始", prominent: true, size: 68) {
                    work.toggleFocus()
                }
                RoundIconButton(systemImage: "forward.end.fill", label: "次へ") { work.skipFocus() }
                    .disabled(!focus.isActive)
                    .opacity(focus.isActive ? 1 : 0.4)
            }
            HStack(spacing: 8) {
                StatusChip(text: "今日 \(Int(work.focusSecondsToday() / 60)) 分", systemImage: "flame.fill", color: UIStyle.warning)
                StatusChip(text: "\(focus.completedRounds) 回完了", systemImage: "checkmark.seal.fill", color: UIStyle.success)
                if focus.completedRounds > 0 && !focus.isActive {
                    Button("回数を 0 に") { work.resetFocus() }.font(.caption)
                }
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .cardSurface(highlighted: focus.isRunning)
        .sensoryFeedback(.impact, trigger: focus.isRunning)
    }
}

struct CountdownCard: View {
    @Environment(AppModel.self) private var model
    @State private var customMinutes = 20
    private let quick = [1, 3, 5, 10, 15, 30, 60]

    var body: some View {
        let work = model.workspace
        let countdown = work.countdown
        Card(title: "タイマー", systemImage: "timer") {
            if countdown.isActive {
                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HUDFormat.timer(countdown.remaining(at: timeline.date)))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            ProgressView(value: countdown.progress(at: timeline.date)).tint(UIStyle.accent)
                        }
                        RoundIconButton(systemImage: countdown.isRunning ? "pause.fill" : "play.fill", label: countdown.isRunning ? "一時停止" : "再開", prominent: true, size: 48) { work.toggleTimer() }
                        RoundIconButton(systemImage: "plus", label: "1 分足す", size: 48) { work.addToTimer(seconds: 60) }
                        RoundIconButton(systemImage: "xmark", label: "止める", size: 48) { work.stopTimer() }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quick, id: \.self) { minutes in
                            Button {
                                work.startTimer(seconds: Double(minutes * 60))
                            } label: {
                                SelectablePill(title: "\(minutes) 分", systemImage: nil, isSelected: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Stepper("\(customMinutes) 分", value: $customMinutes, in: 1...240)
                    Button("開始") { work.startTimer(seconds: Double(customMinutes * 60)) }
                        .buttonStyle(.primaryCompact)
                }
            }
            Text("「5分タイマー」「3分測って」と話しても始められます。アプリを閉じていても、終わると通知します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct StopwatchCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let work = model.workspace
        let stopwatch = work.stopwatch
        Card(title: "ストップウォッチ", systemImage: "stopwatch") {
            HStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                    Text(HUDFormat.stopwatch(stopwatch.elapsed(at: timeline.date), tenths: true))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                RoundIconButton(systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill", label: stopwatch.isRunning ? "止める" : "始める", prominent: true, size: 48) { work.toggleStopwatch() }
                RoundIconButton(systemImage: "flag.fill", label: "ラップ", size: 48) { work.lapStopwatch() }
                RoundIconButton(systemImage: "arrow.counterclockwise", label: "リセット", size: 48) { work.resetStopwatch() }
            }
            if !stopwatch.laps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(stopwatch.laps.enumerated().reversed().prefix(8)), id: \.offset) { index, lap in
                            StatusChip(text: "\(index + 1)：\(HUDFormat.stopwatch(lap, tenths: true))", color: .white)
                        }
                    }
                }
            }
        }
    }
}

struct FocusSettingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var work = model.workspace
        Card(title: "集中タイマーの設定", systemImage: "slider.horizontal.3") {
            Stepper("集中：\(Int(work.data.focus.workMinutes)) 分", value: $work.data.focus.workMinutes, in: 5...180, step: 5)
            Stepper("休憩：\(Int(work.data.focus.shortBreakMinutes)) 分", value: $work.data.focus.shortBreakMinutes, in: 1...60, step: 1)
            Stepper("長い休憩：\(Int(work.data.focus.longBreakMinutes)) 分", value: $work.data.focus.longBreakMinutes, in: 5...120, step: 5)
            Stepper("長い休憩まで：\(work.data.focus.roundsBeforeLongBreak) 回", value: $work.data.focus.roundsBeforeLongBreak, in: 1...12)
            Toggle("終わったら自動で次を始める", isOn: $work.data.focus.autoContinue)
            Toggle("切り替わりを声で知らせる", isOn: $work.data.focus.speaksPhaseChanges)
        }
    }
}

// MARK: - やること

struct TodoSection: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        let data = model.workspace.data
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("やることを追加", text: $draft)
                    .focused($isAdding)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .fieldSurface()
                RoundIconButton(systemImage: "plus", label: "追加", prominent: true, size: 46, action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                HUDWidgetChip(kind: .todo)
                Spacer()
                if !data.todos.isEmpty {
                    Text("\(data.doneTodos.count) / \(data.todos.count) 完了").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if data.todos.isEmpty {
                EmptyStateCard(systemImage: "checklist", title: "やることはありません", message: "上の欄から追加するか、「やることに〇〇を追加」と話しかけてください。")
            } else {
                VStack(spacing: 0) {
                    ForEach(data.todos) { item in
                        TodoRow(item: item)
                        if item.id != data.todos.last?.id {
                            Divider().overlay(UIStyle.cardStroke).padding(.leading, 50)
                        }
                    }
                }
                .cardSurface()
                .animation(.snappy(duration: 0.25), value: data.todos)
                if !data.doneTodos.isEmpty {
                    Button(role: .destructive) {
                        model.workspace.data.removeCompletedTodos()
                    } label: {
                        Label("完了したものを消す", systemImage: "trash").font(.subheadline)
                    }
                }
            }
        }
    }

    private func add() {
        guard model.workspace.data.addTodo(draft) != nil else { return }
        draft = ""
        isAdding = true
    }
}

struct TodoRow: View {
    @Environment(AppModel.self) private var model
    let item: TodoItem

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.workspace.data.toggleTodo(item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(item.isDone ? UIStyle.success : UIStyle.accent)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "未完了に戻す" : "完了にする")
            Text(item.title)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.workspace.data.deleteTodo(item.id)
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.tertiary).frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("削除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sensoryFeedback(.success, trigger: item.isDone)
    }
}

/// 何もないときの案内
struct EmptyStateCard: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(UIStyle.accent)
                .frame(width: 64, height: 64)
                .background(UIStyle.accent.opacity(0.12), in: Circle())
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

// MARK: - メモ

struct NotesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let work = model.workspace
        let selected = work.data.selectedNote
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        work.data.addNote()
                    } label: {
                        SelectablePill(title: "新しいメモ", systemImage: "plus", isSelected: false)
                    }
                    .buttonStyle(.plain)
                    ForEach(work.data.notes) { note in
                        Button {
                            work.data.selectedNoteID = note.id
                        } label: {
                            SelectablePill(title: note.displayTitle, systemImage: nil, isSelected: note.id == selected?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
            HUDWidgetChip(kind: .notes)
            VStack(alignment: .leading, spacing: 10) {
                TextField("題名（なくてもよい）", text: Binding(
                    get: { work.data.selectedNote?.title ?? "" },
                    set: { new in
                        if let id = work.data.selectedNote?.id { work.data.updateNote(id, title: new) } else { work.data.addNote(title: new) }
                    }
                ))
                .font(.headline)
                .fieldSurface()
                TextEditor(text: Binding(
                    get: { work.data.selectedNote?.text ?? "" },
                    set: { new in
                        if let id = work.data.selectedNote?.id { work.data.updateNote(id, text: new) } else { work.data.addNote(text: new) }
                    }
                ))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
                .padding(8)
                .background(UIStyle.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UIStyle.cardStroke, lineWidth: 1))
                HStack {
                    Text("選んでいるメモが HUD に出ます。「メモ、〇〇」と話すと 1 行足せます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let selected {
                        Button(role: .destructive) {
                            work.data.deleteNote(selected.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("このメモを削除")
                    }
                }
            }
            .padding(14)
            .cardSurface()
        }
    }
}

// MARK: - 台本（プロンプター）

struct ScriptSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var work = model.workspace
        let total = work.scriptTotal
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                    let position = work.prompterPosition(at: timeline.date)
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: total > 0 ? min(1, position / Double(total)) : 0).tint(UIStyle.accent)
                        HStack {
                            Text("\(Int(position)) / \(total) 文字").monospacedDigit()
                            Spacer()
                            Text("残り \(HUDFormat.timer(Teleprompter.remainingSeconds(total: total, position: position, charactersPerMinute: work.data.scriptCharactersPerMinute)))").monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 14) {
                    RoundIconButton(systemImage: "backward.end.fill", label: "最初から", size: 46) { work.restartPrompter() }
                    RoundIconButton(systemImage: "gobackward.15", label: "少し戻る", size: 46) { work.seekPrompter(by: -40) }
                    RoundIconButton(systemImage: work.prompter.isRunning ? "pause.fill" : "play.fill", label: work.prompter.isRunning ? "止める" : "流す", prominent: true, size: 64) { work.togglePrompter() }
                        .disabled(total == 0)
                    RoundIconButton(systemImage: "goforward.15", label: "少し進む", size: 46) { work.seekPrompter(by: 40) }
                }
                LabeledSlider(title: "速さ", value: Binding(get: { work.data.scriptCharactersPerMinute }, set: { work.setPrompterSpeed($0) }), range: 60...900, format: { "1 分に \(Int($0)) 文字" })
            }
            .padding(16)
            .cardSurface(highlighted: work.prompter.isRunning)

            HStack(spacing: 8) {
                HUDWidgetChip(kind: .teleprompter)
                Button {
                    model.applyPreset(key: "presentation")
                } label: {
                    Label("発表のプリセットにする", systemImage: "person.wave.2").font(.footnote.weight(.semibold))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("台本").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $work.data.script)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                    .padding(8)
                    .background(UIStyle.fieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(UIStyle.cardStroke, lineWidth: 1))
                Text("グラスには今読む行が大きく出て、少しずつ送られます。「台本を再生」「台本を止めて」と話しても操作できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .cardSurface()
        }
    }
}

// MARK: - 予定・世界時計

struct AgendaSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let calendar = model.calendar
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HUDWidgetChip(kind: .calendar)
                HUDWidgetChip(kind: .worldClock)
            }
            Card(title: "今日・明日の予定", systemImage: "calendar") {
                switch calendar.access {
                case .granted:
                    let now = Date()
                    let events = calendar.upcoming(now: now, limit: 20)
                    if events.isEmpty {
                        Text("予定はありません。").foregroundStyle(.secondary)
                    }
                    ForEach(events) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(CalendarWidget.timeLabel(event, now: now))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(event.isNow(now) ? UIStyle.accent : Color.secondary)
                                .frame(width: 84, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.subheadline.weight(.medium))
                                if let location = event.location {
                                    Text(location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                case .unknown:
                    Text("iPhone・iPad の「カレンダー」に入っている予定を HUD に出せます。予定は端末の中だけで使い、どこにも送りません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("カレンダーを許可する") { calendar.requestAccess() }
                        .buttonStyle(.primaryCompact)
                case .denied:
                    Text("カレンダーが許可されていません。設定アプリ → HUD Navigator → カレンダー で「フルアクセス」にしてください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("設定アプリを開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.secondaryCompact)
                case .unavailable:
                    Text("この版（Swift Playgrounds 版）ではカレンダーを使えません。IPA 版をお使いください。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            WorldClockCard()
        }
        .serviceDemand([.calendar])
    }
}

struct WorldClockCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let work = model.workspace
        Card(title: "世界時計", systemImage: "globe.asia.australia") {
            TimelineView(.periodic(from: .now, by: 10)) { timeline in
                ForEach(work.data.worldClocks) { city in
                    let info = city.timeText(at: timeline.date)
                    HStack {
                        Text(city.name)
                        if !info.dayNote.isEmpty { Text(info.dayNote).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(info.time).font(.title3.weight(.semibold)).monospacedDigit()
                        Button {
                            work.data.worldClocks.removeAll { $0.id == city.id }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(city.name)を外す")
                    }
                }
            }
            Menu {
                ForEach(WorldClockCity.presets) { city in
                    Button(city.name) {
                        if !work.data.worldClocks.contains(where: { $0.timeZoneID == city.timeZoneID }) {
                            work.data.worldClocks.append(WorldClockCity(name: city.name, timeZoneID: city.timeZoneID))
                        }
                    }
                }
            } label: {
                Label("都市を追加", systemImage: "plus.circle.fill").font(.subheadline.weight(.semibold))
            }
        }
    }
}
