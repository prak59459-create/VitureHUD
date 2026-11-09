// ショートカット連携（App Intents）。
// 正式アプリ（GitHub Actions → AltStore の IPA）だけでビルドする。Swift Playgrounds 版では FULL_BUILD が無いので除外される。
#if FULL_BUILD
import AppIntents

enum BackgroundModeOption: String, AppEnum {
    case black, camera

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "背景")
    static let caseDisplayRepresentations: [BackgroundModeOption: DisplayRepresentation] = [
        .black: "黒背景",
        .camera: "カメラ",
    ]

    var mode: BackgroundMode { self == .black ? .black : .camera }
}

enum PresetOption: String, AppEnum {
    case walkNav, travel, daily, info, desk, minimal, custom

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "プリセット")
    static let caseDisplayRepresentations: [PresetOption: DisplayRepresentation] = [
        .walkNav: "徒歩ナビ",
        .travel: "旅行",
        .daily: "日常生活",
        .info: "情報表示",
        .desk: "デスクワーク",
        .minimal: "ミニマル",
        .custom: "カスタム",
    ]
}

struct StartHUDIntent: AppIntent {
    static let title: LocalizedStringResource = "HUD を開始"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppModel.shared.perform(.startHUD)
        return .result(dialog: "\(outcome.message)")
    }
}

struct StopHUDIntent: AppIntent {
    static let title: LocalizedStringResource = "HUD を終了"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await AppModel.shared.perform(.stopHUD)
        return .result()
    }
}

struct SetBackgroundIntent: AppIntent {
    static let title: LocalizedStringResource = "背景を切り替え"
    static let openAppWhenRun = true

    @Parameter(title: "背景")
    var mode: BackgroundModeOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppModel.shared.perform(.setBackground(mode.mode))
        return .result(dialog: "\(outcome.message)")
    }
}

struct ApplyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "プリセットを適用"
    static let openAppWhenRun = true

    @Parameter(title: "プリセット")
    var preset: PresetOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppModel.shared.perform(.applyPreset(key: preset.rawValue))
        return .result(dialog: "\(outcome.message)")
    }
}

struct StartNavigationIntent: AppIntent {
    static let title: LocalizedStringResource = "ナビを開始"
    static let openAppWhenRun = true

    @Parameter(title: "目的地")
    var destination: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppModel.shared.perform(.navigate(to: destination))
        return .result(dialog: "\(outcome.message)")
    }
}

struct StopNavigationIntent: AppIntent {
    static let title: LocalizedStringResource = "ナビを終了"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppModel.shared.perform(.stopNavigation)
        return .result(dialog: "\(outcome.message)")
    }
}

struct ToggleVoiceGuidanceIntent: AppIntent {
    static let title: LocalizedStringResource = "音声案内を切り替え"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let outcome = await model.perform(.setVoiceGuidance(!model.settings.voice.guidanceEnabled))
        return .result(dialog: "\(outcome.message)")
    }
}

struct HUDNavigatorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartHUDIntent(),
            phrases: ["\(.applicationName)で HUD を開始", "\(.applicationName)を起動"],
            shortTitle: "HUD を開始",
            systemImageName: "eyeglasses"
        )
        AppShortcut(
            intent: SetBackgroundIntent(),
            phrases: ["\(.applicationName)で背景を\(\.$mode)にする", "\(.applicationName)で背景を切り替え"],
            shortTitle: "背景を切り替え",
            systemImageName: "circle.lefthalf.filled"
        )
        AppShortcut(
            intent: ApplyPresetIntent(),
            phrases: ["\(.applicationName)を\(\.$preset)にする", "\(.applicationName)のプリセットを適用"],
            shortTitle: "プリセットを適用",
            systemImageName: "square.stack"
        )
        AppShortcut(
            intent: StopNavigationIntent(),
            phrases: ["\(.applicationName)でナビを終了"],
            shortTitle: "ナビを終了",
            systemImageName: "xmark.circle"
        )
        AppShortcut(
            intent: ToggleVoiceGuidanceIntent(),
            phrases: ["\(.applicationName)で音声案内を切り替え"],
            shortTitle: "音声案内を切り替え",
            systemImageName: "speaker.wave.2"
        )
    }
}
#endif
