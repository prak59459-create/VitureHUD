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
