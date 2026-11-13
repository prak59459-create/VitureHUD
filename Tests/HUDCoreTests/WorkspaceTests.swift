import XCTest
@testable import HUDCore

final class WorkspaceTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testTodosKeepPendingAboveDone() {
        var w = WorkspaceData()
        let a = w.addTodo("資料を作る", now: t0)!
        let b = w.addTodo("メールを返す", now: t0)!
        XCTAssertNil(w.addTodo("   "))
        XCTAssertEqual(w.pendingTodos.map(\.title), ["資料を作る", "メールを返す"])
        w.setTodo(a.id, done: true, now: t0)
        XCTAssertEqual(w.todos.map(\.title), ["メールを返す", "資料を作る"])
        XCTAssertNotNil(w.todos[1].completedAt)
        let c = w.addTodo("買い物", now: t0)!
        XCTAssertEqual(w.todos.map(\.title), ["メールを返す", "買い物", "資料を作る"])
        XCTAssertEqual(w.completeNextTodo(now: t0)?.id, b.id)
        XCTAssertEqual(w.completeTodo(matching: "買い", now: t0)?.id, c.id)
        XCTAssertNil(w.completeNextTodo(now: t0))
        w.toggleTodo(a.id, now: t0)
        XCTAssertEqual(w.pendingTodos.map(\.title), ["資料を作る"])
        w.removeCompletedTodos()
        XCTAssertEqual(w.todos.count, 1)
    }

    func testNotes() {
        var w = WorkspaceData()
        XCTAssertNil(w.selectedNote)
        let n = w.appendToSelectedNote("牛乳を買う", now: t0)
        XCTAssertEqual(w.notes.count, 1)
        XCTAssertEqual(n.displayTitle, "牛乳を買う")
        w.appendToSelectedNote("卵も", now: t0.addingTimeInterval(5))
        XCTAssertEqual(w.selectedNote?.lines, ["牛乳を買う", "卵も"])
        let second = w.addNote(title: "会議", text: "議題\n\n  決めること ", now: t0.addingTimeInterval(10))
        XCTAssertEqual(w.selectedNote?.id, second.id)
        XCTAssertEqual(second.displayTitle, "会議")
        XCTAssertEqual(second.lines, ["議題", "決めること"])
        w.deleteNote(second.id)
        XCTAssertEqual(w.notes.count, 1)
        XCTAssertEqual(w.selectedNote?.id, n.id)
    }

    func testWorkspaceDecodesOldFiles() throws {
        let json = #"{"todos":[{"title":"古いデータ"}],"script":"こんにちは"}"#
        let w = try HUDJSON.decode(WorkspaceData.self, from: Data(json.utf8))
        XCTAssertEqual(w.todos.first?.title, "古いデータ")
        XCTAssertEqual(w.focus.workMinutes, 25)
        XCTAssertFalse(w.bookmarks.isEmpty)
        let round = try HUDJSON.decode(WorkspaceData.self, from: HUDJSON.encode(w))
        XCTAssertEqual(round.todos.first?.title, w.todos.first?.title)
        XCTAssertEqual(round.script, "こんにちは")
    }

    func testFocusLog() {
        var w = WorkspaceData()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        w.logFocus(seconds: 1500, at: t0, calendar: utc)
        w.logFocus(seconds: 1500, at: t0.addingTimeInterval(60), calendar: utc)
        XCTAssertEqual(w.focusSeconds(on: t0, calendar: utc), 3000)
        XCTAssertEqual(w.focusSeconds(on: t0.addingTimeInterval(86_400 * 2), calendar: utc), 0)
    }

    func testWebAddress() {
        XCTAssertEqual(WebAddress.resolve("https://example.com/a?b=1"), "https://example.com/a?b=1")
        XCTAssertEqual(WebAddress.resolve(" example.com "), "https://example.com")
        XCTAssertEqual(WebAddress.resolve("ja.wikipedia.org/wiki/Tokyo"), "https://ja.wikipedia.org/wiki/Tokyo")
        XCTAssertEqual(WebAddress.resolve("swift 配列"), WebAddress.searchBase + "swift%20%E9%85%8D%E5%88%97")
        XCTAssertEqual(WebAddress.resolve("東京.天気"), WebAddress.searchBase + WebAddress.percentEncode("東京.天気"))
        XCTAssertTrue(WebAddress.resolve("javascript:alert(1)")!.hasPrefix(WebAddress.searchBase))
        XCTAssertNil(WebAddress.resolve("   "))
        XCTAssertEqual(WebAddress.resolve("about:blank"), "about:blank")
        XCTAssertEqual(WebAddress.display("https://www.example.com/"), "example.com")
        XCTAssertEqual(WebAddress.host("https://ja.wikipedia.org/wiki/X"), "ja.wikipedia.org")
    }

    func testWorldClock() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // 2027-01-15 00:30 UTC = 東京 9:30・ニューヨーク 前日 19:30
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 0, minute: 30))!
        let ny = WorldClockCity(name: "ニューヨーク", timeZoneID: "America/New_York").timeText(at: date, relativeTo: tokyo)
        XCTAssertEqual(ny.time, "19:30")
        XCTAssertEqual(ny.dayNote, "前日")
        XCTAssertEqual(ny.offsetHours, -14)
        let here = WorldClockCity(name: "東京", timeZoneID: "Asia/Tokyo").timeText(at: date, relativeTo: tokyo)
        XCTAssertEqual(here.time, "9:30")
        XCTAssertEqual(here.dayNote, "")
        XCTAssertEqual(WorldClockCity(name: "?", timeZoneID: "Nowhere/None").timeText(at: date).time, "--:--")
        for city in WorldClockCity.presets { XCTAssertNotNil(TimeZone(identifier: city.timeZoneID), city.name) }
    }
}

final class TimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFocusCycle() {
        let s = FocusSettings(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, roundsBeforeLongBreak: 2)
        var f = FocusTimerState()
        XCTAssertFalse(f.isActive)
        f.start(now: t0, settings: s)
        XCTAssertEqual(f.phase, .work)
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(60)), 24 * 60)
        XCTAssertEqual(f.progress(at: t0.addingTimeInterval(750), settings: s), 0.5, accuracy: 0.001)
        XCTAssertNil(f.tick(now: t0.addingTimeInterval(1499), settings: s))
        let first = f.tick(now: t0.addingTimeInterval(1500), settings: s)
        XCTAssertEqual(first, FocusTimerState.Transition(finished: .work, next: .shortBreak, finishedSeconds: 1500, startedNext: true))
        XCTAssertEqual(f.completedRounds, 1)
        XCTAssertEqual(f.phase, .shortBreak)
        let t1 = t0.addingTimeInterval(1500 + 300)
        XCTAssertEqual(f.tick(now: t1, settings: s)?.next, .work)
        XCTAssertEqual(f.currentRound, 2)
        // 2 回目が終わったら長い休憩
        let second = f.tick(now: t1.addingTimeInterval(1500), settings: s)
        XCTAssertEqual(second?.next, .longBreak)
        XCTAssertEqual(f.remaining(at: t1.addingTimeInterval(1500)), 15 * 60)
    }

    func testFocusPauseSkipAndManualContinue() {
        var s = FocusSettings()
        var f = FocusTimerState()
        f.start(now: t0, settings: s)
        f.pause(now: t0.addingTimeInterval(100))
        XCTAssertTrue(f.isPaused)
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(9999)), 1400)
        XCTAssertNil(f.tick(now: t0.addingTimeInterval(9999), settings: s))
        f.resume(now: t0.addingTimeInterval(200))
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(300)), 1300)
        // 途中で飛ばす：使った時間だけ記録する
        let skipped = f.advance(now: t0.addingTimeInterval(300), settings: s)
        XCTAssertEqual(skipped.finishedSeconds, 200, accuracy: 0.001)
        XCTAssertEqual(f.phase, .shortBreak)
        // 自動で続けない設定
        s.autoContinue = false
        let end = f.tick(now: t0.addingTimeInterval(300 + 300), settings: s)
        XCTAssertEqual(end?.startedNext, false)
        XCTAssertEqual(f.phase, .idle)
        f.reset()
        XCTAssertEqual(f.completedRounds, 0)
        XCTAssertEqual(FocusSettings(workMinutes: 0, roundsBeforeLongBreak: 99).sanitized().workMinutes, 1)
    }

    func testCountdownAndStopwatch() {
        var c = CountdownState()
        c.start(seconds: 180, label: "お茶", now: t0)
        XCTAssertEqual(c.remaining(at: t0.addingTimeInterval(30)), 150)
        c.add(seconds: 60, now: t0.addingTimeInterval(30))
        XCTAssertEqual(c.remaining(at: t0.addingTimeInterval(30)), 210)
        c.pause(now: t0.addingTimeInterval(40))
        XCTAssertFalse(c.tick(now: t0.addingTimeInterval(1000)))
        c.resume(now: t0.addingTimeInterval(1000))
        XCTAssertFalse(c.tick(now: t0.addingTimeInterval(1199)))
        XCTAssertTrue(c.tick(now: t0.addingTimeInterval(1200)))
        XCTAssertFalse(c.isActive)

        var w = StopwatchState()
        w.start(now: t0)
        XCTAssertEqual(w.elapsed(at: t0.addingTimeInterval(12.5)), 12.5)
        w.lap(now: t0.addingTimeInterval(5))
        w.pause(now: t0.addingTimeInterval(20))
        XCTAssertEqual(w.elapsed(at: t0.addingTimeInterval(500)), 20)
        w.start(now: t0.addingTimeInterval(600))
        XCTAssertEqual(w.elapsed(at: t0.addingTimeInterval(610)), 30)
        XCTAssertEqual(w.laps, [5])
        w.reset()
        XCTAssertFalse(w.isActive)
    }

    func testTimerFormats() {
        XCTAssertEqual(HUDFormat.timer(1499.2), "25:00")
        XCTAssertEqual(HUDFormat.timer(59), "0:59")
        XCTAssertEqual(HUDFormat.timer(3900), "1:05:00")
        XCTAssertEqual(HUDFormat.timer(0), "0:00")
        XCTAssertEqual(HUDFormat.stopwatch(75.49, tenths: true), "1:15.4")
        XCTAssertEqual(HUDFormat.spokenSeconds(90), "1分30秒")
        XCTAssertEqual(HUDFormat.spokenSeconds(300), "5分")
        XCTAssertEqual(HUDFormat.spokenSeconds(3600), "1時間")
    }

    func testTeleprompter() {
        let lines = Teleprompter.lines("こんにちは。\n\n今日は新しい製品についてお話しします。よろしくお願いします。", maxCharacters: 10)
        XCTAssertEqual(lines.first?.text, "こんにちは。")
        XCTAssertEqual(lines[1].start, 6)
        XCTAssertTrue(lines.allSatisfy { $0.count <= 10 })
        let total = Teleprompter.totalCharacters(lines)
        XCTAssertEqual(total, lines.reduce(0) { $0 + $1.count })
        XCTAssertEqual(Teleprompter.linePosition(lines, character: 3), 0.5, accuracy: 0.001)
        XCTAssertEqual(Teleprompter.linePosition(lines, character: 11), 1.5, accuracy: 0.001)
        XCTAssertEqual(Teleprompter.linePosition(lines, character: Double(total)), Double(lines.count))

        var state = TeleprompterState()
        XCTAssertEqual(state.characterPosition(at: t0, charactersPerMinute: 300, total: total), 0)
        state.play(now: t0)
        XCTAssertEqual(state.characterPosition(at: t0.addingTimeInterval(2), charactersPerMinute: 300, total: total), 10)
        state.seek(by: -4, now: t0.addingTimeInterval(2), charactersPerMinute: 300, total: total)
        XCTAssertEqual(state.characterPosition(at: t0.addingTimeInterval(3), charactersPerMinute: 300, total: total), 11)
        state.pause(now: t0.addingTimeInterval(3), charactersPerMinute: 300, total: total)
        XCTAssertEqual(state.characterPosition(at: t0.addingTimeInterval(99), charactersPerMinute: 300, total: total), 11)
        state.play(now: t0.addingTimeInterval(100))
        XCTAssertEqual(state.characterPosition(at: t0.addingTimeInterval(9999), charactersPerMinute: 300, total: total), Double(total))
        XCTAssertEqual(Teleprompter.remainingSeconds(total: 300, position: 150, charactersPerMinute: 300), 30)
        XCTAssertTrue(Teleprompter.lines("  \n ").isEmpty)
    }

    func testMath() {
        XCTAssertEqual(MathExpression.evaluate("12*(3+4)"), 84)
        XCTAssertEqual(MathExpression.evaluate("2+3*4-6/2"), 11)
        XCTAssertEqual(MathExpression.evaluate("-3+5"), 2)
        XCTAssertEqual(MathExpression.evaluate("200*15%"), 30)
        XCTAssertNil(MathExpression.evaluate("1/0"))
        XCTAssertNil(MathExpression.evaluate("2+"))
        XCTAssertNil(MathExpression.evaluate("(2+3"))
        XCTAssertEqual(MathExpression.normalize("128かける3は？"), "128*3")
        XCTAssertEqual(MathExpression.normalize("１００ わる ４"), "100/4")
        XCTAssertEqual(MathExpression.normalize("5たす6ひく1を計算して"), "5+6-1")
        XCTAssertNil(MathExpression.normalize("5分タイマー"))
        XCTAssertNil(MathExpression.normalize("3D表示にして"))
        XCTAssertNil(MathExpression.normalize("100"))
        XCTAssertNil(MathExpression.normalize("-5"))
        XCTAssertEqual(MathExpression.format(84), "84")
        XCTAssertEqual(MathExpression.format(2.5), "2.5")
        XCTAssertEqual(MathExpression.format(1.0 / 3), "0.333333")
    }
}

final class WorkIntentTests: XCTestCase {
    private let parser = IntentParser()

    private func check(_ text: String, _ expected: AppCommand, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(parser.parse(text), expected, text, file: file, line: line)
    }

    func testTimers() {
        check("5分タイマー", .startTimer(seconds: 300))
        check("タイマーを1時間30分にセット", .startTimer(seconds: 5400))
        check("3分半測って", .startTimer(seconds: 210))
        check("90秒たったら教えて", .startTimer(seconds: 90))
        check("タイマーを止めて", .stopTimer)
        check("タイマーを表示して", .showWidget(.timer))
        check("ストップウォッチをスタート", .setStopwatch(true))
        check("ストップウォッチを止めて", .setStopwatch(false))
        XCTAssertEqual(IntentParser.extractDuration("あと何分"), nil)
        XCTAssertEqual(IntentParser.extractDuration("2時間"), 7200)
    }

    func testFocus() {
        check("集中タイマーを開始", .setFocus(true))
        check("ポモドーロを始めて", .setFocus(true))
        check("集中タイマーをオンにして", .setFocus(true))
        check("集中を終了", .setFocus(false))
        check("ポモドーロを止めて", .setFocus(false))
        check("休憩をスキップ", .skipFocus)
        check("集中タイマーを表示して", .showWidget(.focusTimer))
        check("集中モードにして", .applyPreset(key: "focus"))
    }

    func testTodoAndNotes() {
        check("やることに牛乳を買うを追加", .addTodo("牛乳を買う"))
        check("資料を作るをタスクに追加して", .addTodo("資料を作る"))
        check("タスク追加 メールを返す", .addTodo("メールを返す"))
        check("次のタスク完了", .completeTodo(""))
        check("タスクの資料を完了にして", .completeTodo("資料"))
        check("やることを表示して", .showWidget(.todo))
        check("メモ、牛乳を買う", .addNote("牛乳を買う"))
        check("14時に電話とメモして", .addNote("14時に電話"))
        check("メモに会議は3階を追加", .addNote("会議は3階"))
        check("メモを表示して", .showWidget(.notes))
        check("メモを消して", .hideWidget(.notes))
    }

    func testWebAndTeleprompter() {
        check("猫の動画をウェブで検索", .openWeb("猫の動画"))
        check("ブラウザで example.com を開いて", .openWeb("example.com"))
        check("Swiftの配列をググって", .openWeb("Swiftの配列"))
        check("下にスクロール", .webScroll(.down))
        check("上にスクロールして", .webScroll(.up))
        check("前のページに戻って", .webBack)
        check("ブラウザを表示して", .showWidget(.webPage))
        check("ブラウザを開いて", .open(.work))
        check("台本を再生", .setTeleprompter(true))
        check("台本を止めて", .setTeleprompter(false))
        check("台本を表示して", .showWidget(.teleprompter))
        check("128かける3は？", .calculate("128*3"))
    }

    func testExistingPhrasesStillWork() {
        check("東京駅を検索して", .search("東京駅"))
        check("距離を測って", .measureDistance)
        check("時計を表示して", .showWidget(.clock))
        check("世界時計を表示して", .showWidget(.worldClock))
        check("到着予定を表示", .showWidget(.eta))
        check("予定を表示して", .showWidget(.calendar))
        check("デスクワークモードにして", .applyPreset(key: "desk"))
        check("発表モードにして", .applyPreset(key: "presentation"))
        check("ワークを開いて", .open(.work))
        check("今何時？", .status(.time))
    }

    func testCodecAndDeepLinks() {
        XCTAssertEqual(AICommandCodec.command(name: "startTimer", value: "300"), .startTimer(seconds: 300))
        XCTAssertNil(AICommandCodec.command(name: "startTimer", value: "-1"))
        XCTAssertEqual(AICommandCodec.command(name: "addTodo", value: "牛乳"), .addTodo("牛乳"))
        XCTAssertEqual(AICommandCodec.command(name: "setFocus", value: "true"), .setFocus(true))
        XCTAssertEqual(AICommandCodec.command(name: "applyPreset", value: "browser"), .applyPreset(key: "browser"))
        XCTAssertNil(AICommandCodec.command(name: "calculate", value: "abc"))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://focus/start")!), .setFocus(true))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://timer/300")!), .startTimer(seconds: 300))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://timer?minutes=5")!), .startTimer(seconds: 300))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://todo?add=test")!), .addTodo("test"))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://web?q=example.com")!), .openWeb("example.com"))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://open/work")!), .open(.work))
    }

    func testWorkPresets() {
        XCTAssertTrue(BuiltInContent.isLegacyDeskLayout(HUDLayout(name: "旧", panels: [.make(.clock), .make(.notifications), .make(.battery)])))
        let desk = BuiltInContent.makePresets().first { $0.key == "desk" }!
        XCTAssertFalse(BuiltInContent.isLegacyDeskLayout(desk.layout))
        XCTAssertTrue(desk.layout.contains(widget: .todo))
        // 机で使うプリセットは中央（手元・実際の画面）を空ける
        XCTAssertTrue(LayoutEngine.panelsBlockingCenter(desk.layout.panels).isEmpty)
        for kind in WidgetKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(IntentParser.widgetAliases(kind).isEmpty, kind.rawValue)
            _ = kind.category
        }
        XCTAssertEqual(WidgetKind.calendar.requirements, [.calendar])
    }
}
