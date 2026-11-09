import XCTest
@testable import HUDNavigator

@MainActor
final class AppModelTests: XCTestCase {
    private var _model: AppModel?
    private var model: AppModel {
        if let m = _model { return m }
        let m = AppModel()
        let walk = m.presets.first { $0.key == "walkNav" }!.id
        m.resetPreset(walk)
        m.applyPreset(walk)
        _model = m
        return m
    }

    func testBackgroundCommands() async {
        await model.perform(.setBackground(.camera))
        XCTAssertEqual(model.background, .camera)
        await model.perform(.toggleBackground)
        XCTAssertEqual(model.background, .black)
    }

    func testVoiceCommandRoundTrip() async {
        await model.handleUtterance("黒背景にして")
        XCTAssertEqual(model.background, .black)
        await model.handleUtterance("ミニマルモードにして")
        XCTAssertEqual(model.activePreset.key, "minimal")
        await model.handleUtterance("速度を表示して")
        XCTAssertTrue(model.layout.contains(widget: .speed))
        await model.handleUtterance("速度を消して")
        XCTAssertFalse(model.layout.contains(widget: .speed))
        XCTAssertGreaterThanOrEqual(model.assistant.messages.count, 8)
    }

    func testPresetAndThemeCommands() async {
        await model.perform(.applyPreset(key: "travel"))
        XCTAssertEqual(model.activePreset.key, "travel")
        await model.perform(.applyTheme(key: "neon"))
        XCTAssertEqual(model.activeTheme.key, "neon")
        let unknown = await model.perform(.applyPreset(key: "does-not-exist"))
        XCTAssertTrue(unknown.message.contains("見つかりません"))
    }

    func testPanelEditingAndUndo() {
        let before = model.layout.panels.count
        model.addWidget(.weather)
        XCTAssertEqual(model.layout.panels.count, before + 1)
        let added = model.selectedPanelIDs.first!
        XCTAssertFalse(model.layout.panels.filter { $0.id != added }.contains { $0.frame.intersects(model.layout.panel(id: added)!.frame) },
                       "空いている場所に追加される")
        model.duplicatePanel(added)
        XCTAssertEqual(model.layout.panels.count, before + 2)
        model.undo()
        XCTAssertEqual(model.layout.panels.count, before + 1)
        model.undo()
        XCTAssertEqual(model.layout.panels.count, before)
    }

    func testEditsArePerPreset() {
        let walk = model.activePresetID
        model.addWidget(.customText)
        let walkCount = model.layout.panels.count
        model.applyPreset(model.presets.first { $0.key == "desk" }!.id)
        XCTAssertNotEqual(model.layout.panels.count, walkCount)
        model.applyPreset(walk)
        XCTAssertEqual(model.layout.panels.count, walkCount)
        model.resetPreset(walk)
        XCTAssertEqual(model.layout.panels.count, BuiltInContent.makePresets().first { $0.key == "walkNav" }!.layout.panels.count)
    }

    func testMovingReducesInformation() {
        model.applyPreset(model.presets.first { $0.key == "info" }!.id)
        let all = model.effectivePanels.count
        XCTAssertGreaterThan(all, 0)
        XCTAssertTrue(model.features.reduceWhileMoving)
    }

    func testDetectionNeedsDisclaimer() async {
        model.settings.detection.hasAcceptedDisclaimer = false
        let outcome = await model.perform(.setDetection(true))
        XCTAssertFalse(model.settings.detection.enabled)
        XCTAssertTrue(model.showsVisionDisclaimer)
        XCTAssertTrue(outcome.message.contains("実験"))
    }

    func testStatusQuestionsWork() async {
        let time = await model.perform(.status(.time))
        XCTAssertTrue(time.message.contains("時"))
        let eta = await model.perform(.status(.eta))
        XCTAssertTrue(eta.message.contains("ナビゲーションは行っていません"))
    }

    func testAskWithoutCloudFallsBackLocally() async {
        model.settings.assistant.provider = .localOnly
        let outcome = await model.perform(.ask("おすすめのカフェは？"))
        XCTAssertTrue(outcome.message.contains("端末内"))
        XCTAssertTrue(model.network.entries.isEmpty, "クラウド未設定なら通信しない")
    }

    func testDemoNavigationProgress() {
        model.navigation.startDemo()
        XCTAssertTrue(model.navigation.isGuiding)
        let wp = DemoRoutes.waypoints
        model.navigation.handle(LocationSample(coordinate: Geo.interpolate(wp[1], wp[2], fraction: 0.7), timestamp: Date(), speed: 1.3))
        XCTAssertNotNil(model.navigation.progress)
        XCTAssertNotNil(model.navigation.nextStep)
        model.navigation.handle(LocationSample(coordinate: wp.last!, timestamp: Date().addingTimeInterval(5), speed: 0))
        XCTAssertEqual(model.navigation.phase, .arrived)
        model.navigation.stop()
        XCTAssertEqual(model.navigation.phase, .idle)
    }

    func testExportImportRoundTrip() throws {
        let theme = model.duplicateTheme(BuiltInContent.themes[2])
        model.saveCurrentAsNewPreset(named: "テスト用")
        let url = try XCTUnwrap(model.exportBundleFile(includeHistory: false))
        let other = AppModel()
        other.userThemes = []
        let message = other.importFile(url, strategy: .merge)
        XCTAssertTrue(message.contains("読み込みました"), message)
        XCTAssertTrue(other.userThemes.contains { $0.id == theme.id })
        XCTAssertTrue(other.presets.contains { $0.name == "テスト用" })
    }

    func testThemeFileImport() throws {
        let t = Theme(name: "共有テーマ", style: PanelStyle(textColor: .yellow))
        let url = try XCTUnwrap(model.exportThemesFile([t]))
        let message = model.importFile(url, strategy: .merge)
        XCTAssertTrue(message.contains("テーマを1件"), message)
        XCTAssertTrue(model.userThemes.contains { $0.id == t.id })
    }

    func testAlertsAreShownAndDeduplicated() {
        model.alerts.post(HUDAlert(category: .battery, title: "残量20%", priority: .important))
        model.alerts.post(HUDAlert(category: .battery, title: "残量20%", priority: .important))
        XCTAssertEqual(model.alerts.visible.count, 1)
    }

    func testMapZoomCommandChangesMiniMap() async {
        let before = model.layout.panels.first { $0.widget == .miniMap }!.config.mapSpanMeters
        await model.perform(.mapZoom(.zoomIn))
        let after = model.layout.panels.first { $0.widget == .miniMap }!.config.mapSpanMeters
        XCTAssertLessThan(after, before)
    }
}
