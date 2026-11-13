import XCTest
import SwiftUI
import UIKit
@testable import HUDNavigator

/// 端末側の操作画面を、実際の画面と同じように描いて PNG にする（アーティファクト「hud-snapshots」の ui-*.jpg）。
/// デザインの確認と、AltStore に載せるスクリーンショットに使う。
@MainActor
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func makeModel() -> AppModel {
        let model = AppModel()
        model.showsOnboarding = false
        if let p = model.presets.first(where: { $0.key == "walkNav" }) { model.resetPreset(p.id); model.applyPreset(p.id) }
        model.background = .black
        model.settings.display = HUDDisplaySettings()
        model.suggestion = nil
        return model
    }

    private func shoot<V: View>(_ view: V, model: AppModel, name: String, height: CGFloat? = nil) throws {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.session.role == .windowApplication }) else {
            throw XCTSkip("画面がありません")
        }
        var size = scene.screen.bounds.size
        if let height { size.height = height }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = .dark
        let content = view
            .environment(model)
            .tint(UIStyle.accent)
            .fontDesign(.rounded)
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        // グラデーションの多い画面は PNG だと 5MB を超えるので JPEG にする
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.88))
        XCTAssertGreaterThan(data.count, 2000)
        if let dir = outputDirectory {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("ui-\(name).jpg"))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "ui-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHome() throws {
        let model = makeModel()
        try shoot(HomeView(), model: model, name: "home")
        try shoot(HomeView(), model: model, name: "home-full", height: 1750)
    }

    func testHomeWhileGuiding() throws {
        let model = makeModel()
        model.navigation.startDemo()
        let wp = DemoRoutes.waypoints
        model.navigation.handle(LocationSample(coordinate: Geo.interpolate(wp[1], wp[2], fraction: 0.75), timestamp: Date(), speed: 1.3, course: 300, horizontalAccuracy: 5))
        model.present(Suggestion(key: "shot", title: "雨が降りそうです", message: "15時ごろ降水確率70%。傘をお持ちください。", action: .showWidget(.hourlyForecast)))
        try shoot(HomeView(), model: model, name: "home-guiding", height: 1900)
        model.navigation.stop()
    }

    func testWorkScreens() throws {
        let model = makeModel()
        let work = model.workspace
        work.data.todos = []
        work.data.notes = []
        for title in ["企画書の下書き", "見積もりを送る", "経費の精算", "会議室を予約"] { work.data.addTodo(title) }
        work.data.completeNextTodo()
        work.data.addNote(title: "打ち合わせ", text: "・来週までに試作\n・予算は 30 万円まで\n・次回は木曜 14 時")
        work.data.script = "本日はお集まりいただきありがとうございます。\nこれから新しい取り組みについて、3 つの点をお話しします。"
        work.startFocus()
        defer { work.stopFocus() }
        model.workSection = .focus
        try shoot(WorkScreen(), model: model, name: "work-focus")
        try shoot(WorkScreen(), model: model, name: "work-focus-full", height: 1700)
        model.workSection = .todo
        try shoot(WorkScreen(), model: model, name: "work-todo")
        model.workSection = .notes
        try shoot(WorkScreen(), model: model, name: "work-notes", height: 1100)
        model.workSection = .script
        try shoot(WorkScreen(), model: model, name: "work-script", height: 1200)
        model.workSection = .agenda
        try shoot(WorkScreen(), model: model, name: "work-agenda", height: 1100)
        // ブラウザ：グラスに映している想定（端末はリモコン）。ネットワークを使わないよう空のページを開く
        model.web.open("about:blank")
        model.web.register(.glasses)
        model.workSection = .browser
        try shoot(WorkScreen(), model: model, name: "work-browser-remote", height: 1300)
        model.web.unregister(.glasses)
        try shoot(NavigationStack { VitureTrackingGuideView() }, model: model, name: "viture-3dof-guide", height: 1300)
    }

    func testEditorAssistantSettings() throws {
        let model = makeModel()
        try shoot(HUDEditorScreen(), model: model, name: "hud-editor")
        try shoot(AssistantScreen(), model: model, name: "assistant")
        model.assistant.append(ChatMessage(role: .user, text: "黒背景にして"))
        var reply = ChatMessage(role: .assistant, text: "背景を黒背景にしました。")
        reply.command = "背景を黒背景に変更"
        model.assistant.append(reply)
        try shoot(AssistantScreen(), model: model, name: "assistant-chat")
        model.assistant.clear()
        try shoot(SettingsScreen(), model: model, name: "settings")
        try shoot(NavigationStack { DisplaySettingsView().appBackground() }, model: model, name: "settings-display")
        try shoot(OnboardingView(), model: model, name: "onboarding", height: 1300)
    }
}
