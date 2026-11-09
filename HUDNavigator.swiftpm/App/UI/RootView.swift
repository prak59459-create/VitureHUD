import SwiftUI

/// 端末側の画面。グラスに独立表示している間は「操作画面」になる。
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("ホーム", systemImage: "house", value: AppScreen.home) { HomeView() }
            Tab("HUD", systemImage: "eyeglasses", value: AppScreen.hud) { HUDEditorScreen() }
            Tab("ナビ", systemImage: "map", value: AppScreen.navigation) { NavigationScreen() }
            Tab("ビジョン", systemImage: "viewfinder", value: AppScreen.vision) { VisionScreen() }
            Tab("アシスタント", systemImage: "waveform", value: AppScreen.assistant) { AssistantScreen() }
            Tab("設定", systemImage: "gearshape", value: AppScreen.settings) { SettingsScreen() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .background { KeyboardShortcutsLayer() }
        .onOpenURL { url in model.handleDeepLink(url) }
        .overlay(alignment: .top) { ToastView() }
        .overlay(alignment: .bottomTrailing) { FloatingMicButton().padding(.trailing, 20).padding(.bottom, 90) }
        .overlay {
            if model.isDeviceScreenBlanked {
                BlankScreenView()
            }
        }
        .fullScreenCover(isPresented: $model.isHUDPresented) {
            HUDFullScreenView()
                .environment(model)
        }
        .fullScreenCover(isPresented: $model.showsScan3D) {
            SpatialScanScreen()
                .environment(model)
        }
        .fullScreenCover(isPresented: $model.showsTestPattern) {
            VisibilityTestScreen()
                .environment(model)
        }
        .sheet(isPresented: $model.showsOnboarding) {
            OnboardingView()
                .environment(model)
                .interactiveDismissDisabled()
        }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let text = model.toast {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// どの画面からでも話しかけられるマイクボタン
/// iPad のキーボードで操作する（見えないボタン）
struct KeyboardShortcutsLayer: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            shortcut("u") {
                if model.display.mode != .independent { model.isHUDPresented.toggle() }
            }
            shortcut("b") { model.background = model.background.toggled }
            shortcut(.rightArrow) { model.cyclePreset(1) }
            shortcut(.leftArrow) { model.cyclePreset(-1) }
            shortcut("k") { model.speechInput.toggle() }
            shortcut("r") { Task { await model.perform(.repeatGuidance) } }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func shortcut(_ key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button("", action: action).keyboardShortcut(key, modifiers: .command)
    }
}

struct FloatingMicButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let listening = model.speechInput.isListening
        Button {
            model.speechInput.toggle()
        } label: {
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.black)
                .frame(width: 56, height: 56)
                .background(listening ? Color.orange : UIStyle.accent, in: Circle())
                .shadow(radius: 4)
                .symbolEffect(.variableColor.iterative, isActive: listening)
        }
        .accessibilityLabel(listening ? "聞き取りを止める" : "音声で操作する")
    }
}

/// 端末画面を真っ暗にする（グラスに独立表示中、端末の電力と眩しさを減らす）
struct BlankScreenView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("タップで戻る").font(.caption).foregroundStyle(.white.opacity(0.25)).padding(40)
            }
            .onTapGesture { model.isDeviceScreenBlanked = false }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }
}

/// 端末画面に HUD を全画面表示（ミラー表示・単体利用時）
struct HUDFullScreenView: View {
    @Environment(AppModel.self) private var model
    @State private var showsHint = true

    var body: some View {
        HUDRootView(surface: .deviceFullScreen)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) * 1.5 {
                            model.cyclePreset(dx < 0 ? 1 : -1)
                        } else if dy > 120 {
                            model.isHUDPresented = false
                        }
                    }
            )
            .onTapGesture(count: 2) {
                model.background = model.background.toggled
                model.showToast("背景：\(model.background.displayName)")
            }
            .onLongPressGesture(minimumDuration: 0.8) {
                model.speechInput.toggle()
            }
            .overlay(alignment: .bottom) {
                if showsHint {
                    Text("2回タップ：背景切替　左右スワイプ：プリセット　長押し：音声　下にスワイプ：閉じる")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) { ToastView() }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { showsHint = false }
            }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("HUD Navigator へようこそ", systemImage: "eyeglasses")
                    .font(.title2.bold())
                Text("VITURE などの XR グラスに、ナビや情報を浮かべて表示するアプリです。")
                Card(title: "安全のために", systemImage: "exclamationmark.shield") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("・自動車・自転車などの運転中には使わないでください（運転中の画面注視は法律で禁止されています）。")
                        Text("・歩行中も周囲の安全を最優先にしてください。HUD は視界を遮らない配置をおすすめします。")
                        Text("・物体認識・危険検知は実験的な補助機能で、安全装置ではありません。誤検知・検知漏れがあります。")
                        Text("・距離などの推定値は目安です。")
                    }
                    .font(.subheadline)
                }
                Card(title: "プライバシー", systemImage: "hand.raised") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("・カメラ映像は端末内でのみ処理し、保存・送信しません。")
                        Text("・位置情報は端末内で使います。天気の取得時のみ、丸めた座標を Open-Meteo に送ります。")
                        Text("・AIアシスタントのクラウド機能は、あなたが API キーを入れて同意した場合のみ使います。")
                        Text("・移動履歴の保存は初期設定でオフです。")
                    }
                    .font(.subheadline)
                }
                Card(title: "グラスの使い方", systemImage: "cable.connector") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("・USB-C でグラスをつなぐと、自動で HUD を表示します。")
                        Text("・黒い部分はグラス上で透明に見えます。")
                        Text("・Swift Playgrounds 版ではミラー表示になる場合があります。")
                    }
                    .font(.subheadline)
                }
                Button {
                    model.completeOnboarding()
                } label: {
                    Text("理解して始める")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
    }
}

// MARK: - 視認性テスト（S0-2）

struct VisibilityTestScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VisibilityTestPattern()
            .ignoresSafeArea()
            .onLongPressGesture(minimumDuration: 0.6) { model.showsTestPattern = false }
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
    }
}

/// 文字サイズ・色・太さの見本。グラス越しに読める最小サイズを確かめる。
struct VisibilityTestPattern: View {
    private let sizes: [Double] = [14, 18, 22, 28, 36, 48, 64]
    private let colors: [(String, ColorToken)] = [
        ("白", .white), ("シアン", .cyan), ("緑", .green), ("黄", .yellow), ("橙", .orange), ("赤", .red),
        ("灰", .gray), ("濃い灰", ColorToken(hex: "#5A5A5A")!), ("暗い青", ColorToken(hex: "#1E3A8A")!),
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.height / 1080
            ZStack(alignment: .topLeading) {
                Color.black
                // 四隅と端（見える範囲の確認）
                Rectangle().stroke(Color.white, lineWidth: 2).padding(2)
                ForEach([0.05, 0.1, 0.15], id: \.self) { inset in
                    Rectangle()
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                        .frame(width: geo.size.width * (1 - inset * 2), height: geo.size.height * (1 - inset * 2))
                        .offset(x: geo.size.width * inset, y: geo.size.height * inset)
                }
                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text("視認性テスト（長押しで閉じる）").font(.system(size: 28 * scale, weight: .bold)).foregroundStyle(.white)
                    ForEach(sizes, id: \.self) { s in
                        HStack(spacing: 16 * scale) {
                            Text("\(Int(s))px").font(.system(size: 18 * scale, design: .monospaced)).foregroundStyle(.gray).frame(width: 70 * scale, alignment: .leading)
                            Text("次の角を右 120m").font(.system(size: s * scale, weight: .regular, design: .rounded)).foregroundStyle(.white)
                            Text("12:34").font(.system(size: s * scale, weight: .bold, design: .rounded)).foregroundStyle(Color(ColorToken.cyan))
                        }
                    }
                    HStack(spacing: 12 * scale) {
                        ForEach(colors, id: \.0) { name, token in
                            Text(name).font(.system(size: 30 * scale, weight: .semibold, design: .rounded)).foregroundStyle(Color(token))
                        }
                    }
                    HStack(spacing: 12 * scale) {
                        ForEach(HUDFontWeight.allCases, id: \.self) { w in
                            Text(w.displayName).font(.system(size: 30 * scale, weight: w.swiftUI, design: .rounded)).foregroundStyle(.white)
                        }
                    }
                    HStack(spacing: 12 * scale) {
                        ForEach([0.15, 0.35, 0.6, 1.0], id: \.self) { opacity in
                            Text("背景\(Int(opacity * 100))%")
                                .font(.system(size: 24 * scale, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8 * scale)
                                .background(Color(white: 0.3).opacity(opacity), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.leading, geo.size.width * 0.08)
                .padding(.top, geo.size.height * 0.08)
            }
        }
    }
}
