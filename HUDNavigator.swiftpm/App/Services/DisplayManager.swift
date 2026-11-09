import SwiftUI
import UIKit
import Observation

/// 外部ディスプレイ（VITURE）への出力方式。
enum DisplayOutputMode: String {
    /// グラス未接続
    case local
    /// 端末画面がそのままグラスに映っている（独立表示が使えない環境）
    case mirror
    /// グラス＝HUD、端末＝操作画面
    case independent

    var displayName: String {
        switch self {
        case .local: return "グラス未接続"
        case .mirror: return "ミラー表示"
        case .independent: return "独立表示（グラス＝HUD）"
        }
    }

    var systemImage: String {
        switch self {
        case .local: return "iphone"
        case .mirror: return "rectangle.on.rectangle"
        case .independent: return "eyeglasses"
        }
    }
}

/// HUD を描画する場所。カメラ映像は同時に1か所だけに出す（優先度の高い場所）。
enum HUDSurface: String, Hashable, CaseIterable {
    case external, deviceFullScreen, visionLab, editorPreview, thumbnail

    var cameraPriority: Int {
        switch self {
        case .external: return 4
        case .deviceFullScreen: return 3
        case .visionLab: return 2
        case .editorPreview: return 1
        case .thumbnail: return 0
        }
    }

    var isEditable: Bool { self == .editorPreview }
}

@MainActor
@Observable
final class DisplayManager {
    private(set) var mode: DisplayOutputMode = .local
    private(set) var externalScreenSize: CGSize?
    private(set) var externalNativeSize: CGSize?
    private(set) var externalScale: CGFloat = 1
    private(set) var externalMaximumFPS: Int?
    private(set) var hasExternalScreen = false
    private(set) var events: [String] = []
    /// 外部ディスプレイのシーンを自分で作れたか（Swift Playgrounds 内では作れない場合がある）
    private(set) var attachedViaFallback = false

    @ObservationIgnored private var externalWindow: UIWindow?
    @ObservationIgnored private weak var externalScene: UIWindowScene?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var makeHUDView: (() -> AnyView)?
    @ObservationIgnored var onModeChange: ((DisplayOutputMode) -> Void)?

    var isExternalConnected: Bool { mode != .local }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIScreen.didConnectNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.log("外部画面が接続されました")
                self?.refresh()
                // 少し待ってもシーンが来なければ、フォールバックで接続を試す
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.attachFallbackIfNeeded()
            }
        })
        observers.append(center.addObserver(forName: UIScreen.didDisconnectNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.log("外部画面が切断されました")
                self?.refresh()
            }
        })
        observers.append(center.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] note in
            guard let scene = note.object as? UIWindowScene else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.considerFallback(scene)
            }
        })
        refresh()
        attachFallbackIfNeeded()
    }

    // MARK: - 外部シーン

    /// ExternalDisplaySceneDelegate から呼ばれる
    func attach(windowScene: UIWindowScene, viaFallback: Bool = false) {
        guard externalScene !== windowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let content = makeHUDView?() ?? AnyView(Color.black)
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.backgroundColor = .black
        window.isHidden = false
        externalWindow = window
        externalScene = windowScene
        attachedViaFallback = viaFallback
        let screen = windowScene.screen
        externalScreenSize = screen.bounds.size
        externalNativeSize = screen.nativeBounds.size
        externalScale = screen.scale
        externalMaximumFPS = screen.maximumFramesPerSecond
        log("独立表示を開始（\(Int(screen.bounds.width))×\(Int(screen.bounds.height))、\(screen.maximumFramesPerSecond)Hz\(viaFallback ? "、フォールバック" : "")）")
        refresh()
    }

    func detach(windowScene: UIWindowScene) {
        guard externalScene === windowScene else { return }
        externalWindow?.isHidden = true
        externalWindow = nil
        externalScene = nil
        attachedViaFallback = false
        log("独立表示を終了")
        refresh()
    }

    private func considerFallback(_ scene: UIWindowScene) {
        guard scene.session.role == .windowExternalDisplayNonInteractive else { return }
        guard externalScene == nil, scene.windows.isEmpty else { return }
        attach(windowScene: scene, viaFallback: true)
    }

    private func attachFallbackIfNeeded() {
        guard externalScene == nil else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes
        where scene.session.role == .windowExternalDisplayNonInteractive && scene.windows.isEmpty {
            attach(windowScene: scene, viaFallback: true)
            return
        }
    }

    func refresh() {
        let screens = UIScreen.screens
        hasExternalScreen = screens.count > 1
        let newMode: DisplayOutputMode
        if externalScene != nil {
            newMode = .independent
        } else if hasExternalScreen {
            newMode = .mirror
            if let external = screens.last {
                externalScreenSize = external.bounds.size
                externalNativeSize = external.nativeBounds.size
                externalMaximumFPS = external.maximumFramesPerSecond
            }
        } else {
            newMode = .local
            externalScreenSize = nil
            externalNativeSize = nil
            externalMaximumFPS = nil
        }
        if newMode != mode {
            mode = newMode
            log("出力モード: \(newMode.displayName)")
            onModeChange?(newMode)
        }
    }

    private func log(_ message: String) {
        let line = "\(HUDFormat.clock(Date(), seconds: true)) \(message)"
        events.append(line)
        if events.count > 50 { events.removeFirst(events.count - 50) }
    }

    var statusDescription: String {
        guard let size = externalScreenSize else { return mode.displayName }
        var text = "\(mode.displayName)：\(Int(size.width))×\(Int(size.height))"
        if let fps = externalMaximumFPS { text += "・\(fps)Hz" }
        return text
    }
}

/// アプリの起動・シーン構成。外部ディスプレイ用のシーンをコードで返す（Info.plist の編集が不要）。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return configuration
    }
}

/// グラス側のシーン。HUD だけを表示する。
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppModel.shared.display.attach(windowScene: windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppModel.shared.display.detach(windowScene: windowScene)
    }
}
