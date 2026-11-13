import XCTest
import SwiftUI
@testable import HUDNavigator

/// HUD の見た目を PNG に書き出す（GitHub Actions のアーティファクト「hud-snapshots」で確認できる）。
/// 実機・グラスなしで、配置崩れ・文字の大きさ・テーマの見え方を確かめるためのもの。
@MainActor
final class SnapshotTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func makeModel(preset key: String) -> AppModel {
        let model = AppModel()
        model.showsOnboarding = false
        if let p = model.presets.first(where: { $0.key == key }) { model.resetPreset(p.id); model.applyPreset(p.id) }
        model.background = .black
        // 時刻によって明るさが変わらないように
        model.settings.display = HUDDisplaySettings()
        model.settings.display.nightDimEnabled = false
        return model
    }

    /// ナビ中の状態を作る（デモルートの途中）
    private func simulateNavigation(_ model: AppModel) {
        model.navigation.startDemo()
        let wp = DemoRoutes.waypoints
        model.navigation.handle(LocationSample(coordinate: Geo.interpolate(wp[1], wp[2], fraction: 0.75), timestamp: Date(), speed: 1.3, course: 300, horizontalAccuracy: 5))
    }

    private func render<V: View>(_ view: V, model: AppModel, size: CGSize, name: String) throws {
        let content = view
            .environment(model)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage, "描画できません: \(name)")
        let data = try XCTUnwrap(image.pngData())
        XCTAssertEqual(image.size.width, size.width, accuracy: 1)
        XCTAssertGreaterThan(data.count, 500)
        if let dir = outputDirectory {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("\(name).png"))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private let glasses = CGSize(width: 1920, height: 1080)

    /// ワーク（やること・メモ・台本・タイマー）に見本のデータを入れる
    private func seedWorkspace(_ model: AppModel) {
        let work = model.workspace
        work.data.todos = []
        work.data.notes = []
        for title in ["企画書の下書き", "見積もりを送る", "経費の精算", "会議室を予約"] { work.data.addTodo(title) }
        work.data.completeNextTodo()
        work.data.addNote(title: "打ち合わせ", text: "・来週までに試作\n・予算は 30 万円まで\n・次回は木曜 14 時")
        work.data.script = "本日はお集まりいただきありがとうございます。\nこれから新しい取り組みについて、3 つの点をお話しします。\nまず 1 つ目は、これまでの結果です。\n次に、今後の計画をご説明します。"
        work.startFocus()
        work.startTimer(seconds: 180, label: "お茶")
    }

    func testEveryPresetOnGlasses() throws {
        for preset in BuiltInContent.makePresets() {
            let model = makeModel(preset: preset.key!)
            seedWorkspace(model)
            defer {
                model.workspace.stopFocus()
                model.workspace.stopTimer()
            }
            if preset.key == "walkNav" || preset.key == "travel" || preset.key == "minimal" { simulateNavigation(model) }
            try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "preset-\(preset.key!)-1920x1080")
        }
    }

    func testEveryThemeOnWalkingLayout() throws {
        for theme in BuiltInContent.themes {
            let model = makeModel(preset: "walkNav")
            simulateNavigation(model)
            model.applyTheme(theme.key!)
            try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "theme-\(theme.key!)")
        }
    }

    func testDeviceSizes() throws {
        let model = makeModel(preset: "daily")
        try render(HUDRootView(surface: .thumbnail), model: model, size: CGSize(width: 844, height: 390), name: "device-iphone15-landscape")
        try render(HUDRootView(surface: .thumbnail), model: model, size: CGSize(width: 1180, height: 820), name: "device-ipad-landscape")
        try render(HUDRootView(surface: .thumbnail), model: model, size: CGSize(width: 1280, height: 720), name: "glasses-720p")
    }

    func testEditorAndAlerts() throws {
        let model = makeModel(preset: "info")
        model.selectedPanelIDs = [model.layout.panels[0].id]
        try render(HUDRootView(surface: .editorPreview), model: model, size: glasses, name: "editor-info")
        let alertModel = makeModel(preset: "walkNav")
        simulateNavigation(alertModel)
        alertModel.alerts.post(HUDAlert(category: .reroute, title: "ルート変更", message: "ルートを再検索しました。残り350メートルです。", priority: .important, duration: 60))
        alertModel.alerts.post(HUDAlert(category: .hazard, title: "自転車に注意（実験）", message: "接近中（推定 約1.2秒）", priority: .critical, duration: 60))
        try render(HUDRootView(surface: .external), model: alertModel, size: glasses, name: "alerts-walkNav")
    }

    func testCanvasAdjustmentAndMinimumFont() throws {
        let model = makeModel(preset: "walkNav")
        simulateNavigation(model)
        model.updateCanvas { $0.scale = 0.8; $0.offsetY = 0.05; $0.minimumFontPixels = 36 }
        try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "canvas-scaled-80-minfont36")
    }

    func testNewWidgets() throws {
        let model = makeModel(preset: "daily")
        model.nearbyCategory = .cafe
        model.nearbyResults = [
            PlaceResult(name: "カフェ（デモ1）", address: "デモ", coordinate: DemoRoutes.waypoints[1], category: "カフェ", distance: 120),
            PlaceResult(name: "カフェ（デモ2）", address: "デモ", coordinate: DemoRoutes.waypoints[2], category: "カフェ", distance: 340),
        ]
        var text = HUDPanel(widget: .customText, frame: NormalizedRect(x: 0.03, y: 0.8, width: 0.5, height: 0.1), zIndex: 5)
        text.config.text = "{preset}・心拍{hr}"
        var l = model.layout
        l.panels = [
            HUDPanel(widget: .heartRate, frame: NormalizedRect(x: 0.03, y: 0.05, width: 0.22, height: 0.14), zIndex: 1),
            HUDPanel(widget: .horizon, frame: NormalizedRect(x: 0.03, y: 0.25, width: 0.22, height: 0.18), zIndex: 2),
            HUDPanel(widget: .hourlyForecast, frame: NormalizedRect(x: 0.3, y: 0.05, width: 0.4, height: 0.2), zIndex: 3),
            HUDPanel(widget: .nearbyPlaces, frame: NormalizedRect(x: 0.72, y: 0.05, width: 0.25, height: 0.22), zIndex: 4),
            text,
        ]
        model.layout = l
        try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "widgets-new")
        model.updateCanvas { $0.textScale = 1.4 }
        try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "widgets-new-text140")
    }

    func testSensorWidgets() throws {
        let model = makeModel(preset: "daily")
        var l = model.layout
        l.panels = [
            HUDPanel(widget: .distance, frame: NormalizedRect(x: 0.03, y: 0.05, width: 0.2, height: 0.13), zIndex: 1),
            HUDPanel(widget: .headPose, frame: NormalizedRect(x: 0.03, y: 0.22, width: 0.16, height: 0.2), zIndex: 2),
            HUDPanel(widget: .steps, frame: NormalizedRect(x: 0.25, y: 0.05, width: 0.2, height: 0.13), zIndex: 3),
        ]
        model.layout = l
        try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "widgets-sensors")
    }

    func testStereoSideBySide() throws {
        let model = makeModel(preset: "minimal")
        model.settings.display.stereo3D = true
        model.settings.display.stereoDepth = 20
        try render(HUDRootView(surface: .external), model: model, size: glasses, name: "stereo-sbs-minimal")
        // グラスが 3D モード（3840×1080）でつながった場合は、設定に関係なく左右に描き分ける
        model.settings.display.stereo3D = false
        try render(HUDRootView(surface: .external), model: model, size: CGSize(width: 3840, height: 1080), name: "stereo-full-sbs-3840x1080")
        model.settings.display.stereo3D = false
        model.settings.display.brightness = 0.5
        try render(HUDRootView(surface: .external), model: model, size: glasses, name: "brightness-50-minimal")
        model.settings.display = HUDDisplaySettings()
    }

    func testWorkWidgets() throws {
        let model = makeModel(preset: "daily")
        seedWorkspace(model)
        defer {
            model.workspace.stopFocus()
            model.workspace.stopTimer()
        }
        var l = model.layout
        l.panels = [
            HUDPanel(widget: .focusTimer, frame: NormalizedRect(x: 0.03, y: 0.04, width: 0.2, height: 0.14), zIndex: 1),
            HUDPanel(widget: .timer, frame: NormalizedRect(x: 0.25, y: 0.04, width: 0.16, height: 0.12), zIndex: 2),
            HUDPanel(widget: .todo, frame: NormalizedRect(x: 0.03, y: 0.22, width: 0.24, height: 0.32), zIndex: 3),
            HUDPanel(widget: .notes, frame: NormalizedRect(x: 0.03, y: 0.58, width: 0.24, height: 0.36), zIndex: 4),
            HUDPanel(widget: .teleprompter, frame: NormalizedRect(x: 0.3, y: 0.22, width: 0.42, height: 0.3), zIndex: 5),
            HUDPanel(widget: .webPage, frame: NormalizedRect(x: 0.3, y: 0.56, width: 0.42, height: 0.38), zIndex: 6),
            HUDPanel(widget: .calendar, frame: NormalizedRect(x: 0.75, y: 0.04, width: 0.22, height: 0.26), zIndex: 7),
            HUDPanel(widget: .worldClock, frame: NormalizedRect(x: 0.75, y: 0.34, width: 0.22, height: 0.18), zIndex: 8),
        ]
        model.layout = l
        try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "widgets-work")
        model.applyTheme("cyberpunk")
        try render(HUDRootView(surface: .thumbnail), model: model, size: glasses, name: "widgets-work-cyberpunk")
    }

    func testVisibilityPattern() throws {
        let model = makeModel(preset: "minimal")
        try render(VisibilityTestPattern(), model: model, size: glasses, name: "visibility-test-pattern")
    }
}
