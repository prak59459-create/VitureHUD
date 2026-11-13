import XCTest
@testable import HUDNavigator

/// 追加機能（音声・AI の操作、URL、テンプレート、同期）の結合テスト
@MainActor
final class FeatureTests: XCTestCase {
    private var _model: AppModel?
    private var model: AppModel {
        if let m = _model { return m }
        let m = AppModel()
        let daily = m.presets.first { $0.key == "daily" }!.id
        m.resetPreset(daily)
        m.applyPreset(daily)
        m.settings.display = HUDDisplaySettings()
        _model = m
        return m
    }

    func testCanvasAndDisplayCommands() async {
        model.updateCanvas { $0.scale = 1; $0.offsetX = 0; $0.textScale = 1 }
        await model.perform(.adjustHUDScale(.down))
        XCTAssertEqual(model.layout.canvas.scale, 0.95, accuracy: 0.001)
        await model.perform(.adjustHUDScale(.up))
        XCTAssertEqual(model.layout.canvas.scale, 1, accuracy: 0.001)
        await model.perform(.moveHUD(.left))
        XCTAssertLessThan(model.layout.canvas.offsetX, 0)
        await model.perform(.moveHUD(.right))
        XCTAssertEqual(model.layout.canvas.offsetX, 0, accuracy: 0.001)
        await model.perform(.adjustTextSize(.up))
        XCTAssertEqual(model.layout.canvas.textScale, 1.1, accuracy: 0.001)

        model.settings.display.brightness = 1
        await model.perform(.adjustBrightness(.down))
        XCTAssertEqual(model.settings.display.brightness, 0.9, accuracy: 0.001)
        await model.perform(.setStereo3D(true))
        XCTAssertTrue(model.settings.display.stereo3D)
        await model.perform(.setStereo3D(false))
        await model.perform(.setNightDim(false))
        XCTAssertFalse(model.settings.display.nightDimEnabled)
        XCTAssertEqual(model.hudBrightness, 0.9, accuracy: 0.001, "夜間の減光がオフなら設定どおり")
        model.settings.display = HUDDisplaySettings()
    }

    func testStereoLayoutDetection() {
        let hd = CGSize(width: 1920, height: 1080)
        let wide = CGSize(width: 3840, height: 1080)
        XCTAssertEqual(HUDRootView.stereoLayout(surface: .external, size: hd, stereoSetting: false), .none)
        XCTAssertEqual(HUDRootView.stereoLayout(surface: .external, size: hd, stereoSetting: true), .halfSideBySide)
        XCTAssertEqual(HUDRootView.stereoLayout(surface: .external, size: wide, stereoSetting: false), .fullSideBySide, "3D モードの信号は自動")
        XCTAssertEqual(HUDRootView.stereoLayout(surface: .thumbnail, size: wide, stereoSetting: true), .none, "端末側の表示は 2D")
    }

    func testCyclePresetAndNextTheme() async {
        let first = model.activePresetID
        await model.perform(.cyclePreset(1))
        XCTAssertNotEqual(model.activePresetID, first)
        await model.perform(.cyclePreset(-1))
        XCTAssertEqual(model.activePresetID, first)
        let theme = model.activeTheme.id
        await model.perform(.nextTheme)
        XCTAssertNotEqual(model.activeTheme.id, theme)
    }

    func testVoiceParsesNewCommands() async {
        model.settings.display.brightness = 1
        await model.handleUtterance("HUDを暗くして")
        XCTAssertLessThan(model.settings.display.brightness, 1)
        await model.handleUtterance("次のプリセット")
        XCTAssertNotEqual(model.activePreset.key, "daily")
        model.settings.display = HUDDisplaySettings()
    }

    func testAIPlanRunsOnlyWhitelistedCommands() async {
        model.background = .camera
        let json = #"{"commands":[{"name":"setBackground","value":"black"},{"name":"deleteEverything","value":""},{"name":"showWidget","value":"heartRate"}],"reply":"黒背景にして心拍を表示しました"}"#
        let outcome = await model.runAIPlan(json)
        XCTAssertEqual(model.background, .black)
        XCTAssertTrue(model.layout.contains(widget: .heartRate))
        XCTAssertEqual(outcome.message, "黒背景にして心拍を表示しました")
        XCTAssertNotNil(outcome.detail)

        let plain = await model.runAIPlan("ただの答えです")
        XCTAssertEqual(plain.message, "ただの答えです")
        XCTAssertNil(plain.detail)
    }

    func testDeepLinkCommandsAndTemplate() async throws {
        let cmd = try XCTUnwrap(DeepLink.command(from: XCTUnwrap(URL(string: "hudnavigator://background/camera"))))
        await model.perform(cmd)
        XCTAssertEqual(model.background, .camera)
        await model.perform(.setBackground(.black))

        let values = model.templateValues()
        XCTAssertNotNil(values["time"])
        XCTAssertEqual(values["preset"], model.activePreset.name)
        XCTAssertNil(values["hr"], "心拍計がなければ値なし")
        XCTAssertEqual(TemplateRenderer.render("{preset} {hr}", values: values), "\(model.activePreset.name) --")
    }

    func testApplyBundleKeepsDeviceSpecificSettings() {
        model.settings.googleMaps.consentGiven = false
        model.settings.bluetooth.rememberedDeviceName = "Local"
        let localDeviceID = model.settings.sync.deviceID
        var incoming = model.settings
        incoming.googleMaps.consentGiven = true
        incoming.bluetooth.rememberedDeviceName = "Remote"
        incoming.sync.deviceID = "remote-device"
        incoming.display.brightness = 0.5
        let bundle = SettingsBundle(exportedAt: Date(), deviceName: "テスト端末", settings: incoming, themes: [], presets: [], favorites: [], deviceID: "remote-device")
        let message = model.applyBundle(bundle, strategy: .merge)
        XCTAssertTrue(message.contains("テスト端末"))
        XCTAssertFalse(model.settings.googleMaps.consentGiven, "同意は端末ごと")
        XCTAssertEqual(model.settings.bluetooth.rememberedDeviceName, "Local", "Bluetooth 機器は端末ごと")
        XCTAssertEqual(model.settings.sync.deviceID, localDeviceID, "端末 ID は変えない")
        XCTAssertEqual(model.settings.display.brightness, 0.5, accuracy: 0.001, "表示設定は同期する")
        XCTAssertNotNil(model.settings.sync.lastImportedAt)
        model.settings.display = HUDDisplaySettings()
        model.settings.bluetooth = BluetoothSettings()
    }

    func testSyncFingerprintIgnoresTimestamps() {
        let a = model.syncFingerprint()
        model.settings.sync.lastExportedAt = Date()
        XCTAssertEqual(model.syncFingerprint(), a)
        model.settings.display.brightness = 0.7
        XCTAssertNotEqual(model.syncFingerprint(), a)
        model.settings.display = HUDDisplaySettings()
    }

    func testRecordingNeedsHistoryEnabled() async {
        model.settings.history.enabled = false
        let off = await model.perform(.setRecording(true))
        XCTAssertFalse(model.history.isRecording)
        XCTAssertTrue(off.message.contains("オフ"))
        model.settings.history.enabled = true
        await model.perform(.setRecording(true))
        XCTAssertTrue(model.history.isRecording)
        await model.perform(.setRecording(false))
        XCTAssertFalse(model.history.isRecording)
        model.settings.history.enabled = false
    }

    func testGoogleIsNotUsedWithoutKeyAndConsent() {
        model.settings.map.engine = .googleMaps
        model.settings.googleMaps.consentGiven = false
        XCTAssertFalse(model.usesGoogleSearch)
        XCTAssertFalse(model.usesGoogleRoutes(.transit))
        model.settings.map.engine = .appleMapKit
    }

    func testHeadAndDepthCommands() async {
        model.settings.headTracking = HeadTrackingSettings()
        await model.perform(.setHeadLock(true))
        XCTAssertTrue(model.settings.headTracking.headLock)
        XCTAssertEqual(model.settings.headTracking.source, .airPods, "未設定なら AirPods を使う")
        await model.perform(.setGlanceMode(true))
        XCTAssertTrue(model.settings.headTracking.glanceMode)
        let recenter = await model.perform(.recenterHead)
        XCTAssertFalse(recenter.message.isEmpty)
        model.settings.headTracking = HeadTrackingSettings()

        await model.perform(.setDepth(true))
        XCTAssertTrue(model.settings.depth.enabled)
        let measure = await model.perform(.measureDistance)
        XCTAssertFalse(measure.message.isEmpty, "カメラが動いていなくても理由を答える")
        await model.perform(.setDepth(false))
        XCTAssertFalse(model.settings.depth.enabled)

        await model.perform(.open(.scan3D))
        XCTAssertTrue(model.showsScan3D)
        model.showsScan3D = false
    }

    func testWorkCommands() async {
        let work = model.workspace
        work.data.todos = []
        work.data.notes = []

        await model.perform(.startTimer(seconds: 90))
        XCTAssertTrue(work.countdown.isRunning)
        XCTAssertEqual(work.countdown.remaining(at: Date()), 90, accuracy: 2)
        XCTAssertTrue(model.isWidgetShown(.timer), "タイマーを始めたら HUD に出す")
        await model.perform(.stopTimer)
        XCTAssertFalse(work.countdown.isActive)

        await model.perform(.setFocus(true))
        XCTAssertEqual(work.focus.phase, .work)
        XCTAssertTrue(model.isWidgetShown(.focusTimer))
        await model.perform(.skipFocus)
        XCTAssertTrue(work.focus.phase.isBreak)
        XCTAssertEqual(work.focus.completedRounds, 1)
        await model.perform(.setFocus(false))
        XCTAssertFalse(work.focus.isActive)
        work.resetFocus()

        await model.perform(.addTodo("牛乳を買う"))
        await model.perform(.addTodo("メールを返す"))
        XCTAssertEqual(work.data.pendingTodos.map(\.title), ["牛乳を買う", "メールを返す"])
        let done = await model.perform(.completeTodo(""))
        XCTAssertTrue(done.message.contains("牛乳を買う"))
        await model.perform(.completeTodo("メール"))
        XCTAssertTrue(work.data.pendingTodos.isEmpty)

        await model.perform(.addNote("14時に電話"))
        XCTAssertEqual(work.data.selectedNote?.lines, ["14時に電話"])

        let answer = await model.perform(.calculate("12*(3+4)"))
        XCTAssertEqual(answer.message, "12*(3+4) = 84")

        work.data.script = ""
        let empty = await model.perform(.setTeleprompter(true))
        XCTAssertTrue(empty.message.contains("台本"))
        work.data.script = "こんにちは。今日はよろしくお願いします。"
        await model.perform(.setTeleprompter(true))
        XCTAssertTrue(work.prompter.isRunning)
        await model.perform(.setTeleprompter(false))
        XCTAssertFalse(work.prompter.isRunning)

        await model.perform(.setStopwatch(true))
        XCTAssertTrue(work.stopwatch.isRunning)
        await model.perform(.setStopwatch(false))
        work.resetStopwatch()

        model.selectedTab = .home
        await model.perform(.open(.work))
        XCTAssertEqual(model.selectedTab, .work)
        work.data.todos = []
        work.data.notes = []
        work.data.script = ""
    }

    func testCompactLayoutOpensHiddenTabsAsOverlay() {
        model.isCompactLayout = true
        model.selectedTab = .home
        model.selectedTab = .vision
        XCTAssertEqual(model.selectedTab, .home, "iPhone ではタブを切り替えず、上に重ねて開く")
        XCTAssertEqual(model.overlayScreen, .vision)
        model.overlayScreen = nil
        model.selectedTab = .work
        XCTAssertEqual(model.selectedTab, .work)
        XCTAssertNil(model.overlayScreen)
        model.isCompactLayout = false
        model.selectedTab = .assistant
        XCTAssertEqual(model.selectedTab, .assistant)
        model.selectedTab = .home
    }

    func testLegacyDeskPresetIsUpgraded() {
        let desk = model.presets.first { $0.key == "desk" }!
        XCTAssertFalse(BuiltInContent.isLegacyDeskLayout(desk.layout))
        XCTAssertEqual(model.presets.filter(\.isBuiltIn).count, 12)
    }

    func testHeadGestureRunsConfiguredAction() {
        model.background = .camera
        model.settings.headTracking.shakeAction = .toggleBackground
        model.handleHeadGesture(.shake)
        XCTAssertEqual(model.background, .black)
        model.settings.headTracking.nodAction = .none
        model.handleHeadGesture(.nod)
        XCTAssertEqual(model.background, .black, "「何もしない」は何もしない")
        model.settings.headTracking = HeadTrackingSettings()
    }

    func testHeadTrackingHubRelativePoseAndGlance() {
        let hub = HeadTrackingService()
        var s = HeadTrackingSettings()
        s.source = .device
        s.glanceMode = true
        s.smoothing = 0
        hub.configure(settings: s, active: true, motion: MotionService())
        hub.ingest(HeadPose(yaw: 30, pitch: 0, roll: 0))
        hub.ingest(HeadPose(yaw: 40, pitch: -20, roll: 0))
        XCTAssertEqual(hub.pose?.yaw ?? 0, 10, accuracy: 1e-6, "最初の向きからのずれ")
        XCTAssertTrue(hub.isGlancing, "下を 20 度見たらチラ見")
        hub.recenter()
        XCTAssertEqual(hub.pose, .zero)
        hub.configure(settings: s, active: false, motion: MotionService())
        XCTAssertNil(hub.pose)
        XCTAssertEqual(hub.activeSource, .off)
    }

    func testGlanceModeHidesDetailsUntilLookingDown() {
        model.settings.headTracking = HeadTrackingSettings()
        let all = model.effectivePanels.count
        XCTAssertGreaterThan(all, 0)
        model.settings.headTracking.glanceMode = true
        // 頭の向きがまだない（センサー未接続）ときは全部表示
        XCTAssertEqual(model.effectivePanels.count, all)
        model.settings.headTracking = HeadTrackingSettings()
    }

    func testScanMeshBuilderMakesTrianglesAndOBJ() {
        let builder = MeshBuilder(voxelSize: 0.05)
        var pts: [ColoredPoint] = []
        for x in stride(from: Float(-0.5), through: 0.5, by: 0.02) {
            for y in stride(from: Float(-0.5), through: 0.5, by: 0.02) {
                pts.append(ColoredPoint(Point3(x, y, -1), r: 100, g: 150, b: 200))
            }
        }
        let frame = SpatialScanner.FrameResult(cloud: pts, meshable: pts, origin: Point3(0, 0, 0))
        for _ in 0..<3 { builder.integrate(frame, weight: 0.7) }
        let mesh = builder.extract()
        XCTAssertGreaterThan(mesh.triangleCount, 50, "壁の点から三角形のメッシュができる")
        let obj = mesh.obj()
        XCTAssertTrue(obj.contains("\nv "))
        XCTAssertTrue(obj.contains("\nf "))
        builder.reset(voxelSize: 0.08)
        XCTAssertEqual(builder.extract().triangleCount, 0, "細かさを変えると作り直し")
    }

    func testSuggestionAcceptRunsAction() async throws {
        model.background = .camera
        model.present(Suggestion(key: "test", title: "テスト", message: "黒背景にします", action: .setBackground(.black)))
        XCTAssertNotNil(model.suggestion)
        model.acceptSuggestion()
        XCTAssertNil(model.suggestion)
        for _ in 0..<20 where model.background != .black { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(model.background, .black)
    }
}
