import SwiftUI
import UniformTypeIdentifiers

enum SettingsRoute: Hashable {
    case display, mapVoice, notifications, sensors, history, weather, sync, privacy, assistant, shortcuts, advanced, deviceTest, about, themes, presets, canvas
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.settingsPath) {
            List {
                Section("表示") {
                    link(.display, "外部ディスプレイ（グラス）", "eyeglasses", detail: model.display.mode.displayName)
                    link(.canvas, "表示位置・大きさ", "rectangle.dashed")
                    link(.themes, "テーマ", "paintpalette", detail: model.activeTheme.name)
                    link(.presets, "プリセット", "square.stack", detail: model.activePreset.name)
                }
                Section("ナビ・音声") {
                    link(.mapVoice, "地図・ナビ・音声案内", "map")
                    link(.notifications, "通知・警告", "bell.badge")
                    link(.assistant, "AIアシスタント", "waveform", detail: model.settings.assistant.provider.isCloud ? "クラウド" : "端末内")
                }
                Section("情報") {
                    link(.weather, "天気・環境情報", "cloud.sun")
                    link(.sensors, "センサー情報", "gyroscope")
                    link(.history, "履歴・分析", "chart.xyaxis.line", detail: model.settings.history.enabled ? "記録する" : "記録しない")
                }
                Section("データ") {
                    link(.sync, "データ・同期", "arrow.triangle.2.circlepath")
                    link(.privacy, "プライバシー・通信ログ", "hand.raised")
                    link(.shortcuts, "ショートカット", "square.on.square")
                }
                Section("その他") {
                    link(.advanced, "詳細・診断", "wrench.and.screwdriver")
                    link(.deviceTest, "実機テストモード", "checklist")
                    link(.about, "このアプリについて・安全", "info.circle")
                }
            }
            .navigationTitle("設定")
            .navigationDestination(for: SettingsRoute.self) { route in
                destination(route)
            }
        }
    }

    private func link(_ route: SettingsRoute, _ title: String, _ icon: String, detail: String? = nil) -> some View {
        NavigationLink(value: route) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let detail { Text(detail).foregroundStyle(.secondary).font(.subheadline) }
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: SettingsRoute) -> some View {
        switch route {
        case .display: DisplaySettingsView()
        case .mapVoice: MapVoiceSettingsView()
        case .notifications: NotificationSettingsView()
        case .sensors: SensorsView()
        case .history: HistoryView()
        case .weather: WeatherDetailView()
        case .sync: SyncView()
        case .privacy: PrivacyView()
        case .assistant: AssistantSettingsView()
        case .shortcuts: ShortcutsInfoView()
        case .advanced: AdvancedView()
        case .deviceTest: DeviceTestView()
        case .about: AboutView()
        case .themes: ThemeManagerView()
        case .presets: PresetManagerView()
        case .canvas: CanvasSettingsView()
        }
    }
}

// MARK: - 外部ディスプレイ

struct DisplaySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let display = model.display
        Form {
            Section("状態") {
                LabeledContent("出力", value: display.mode.displayName)
                if let size = display.externalScreenSize {
                    LabeledContent("グラスの画面", value: "\(Int(size.width))×\(Int(size.height)) pt")
                }
                if let native = display.externalNativeSize {
                    LabeledContent("実解像度", value: "\(Int(native.width))×\(Int(native.height)) px")
                }
                if let fps = display.externalMaximumFPS { LabeledContent("リフレッシュレート", value: "\(fps) Hz") }
                if display.attachedViaFallback {
                    Text("Swift Playgrounds などでの実行のため、代替の方法で独立表示しています。").font(.caption).foregroundStyle(.secondary)
                }
                if display.mode == .mirror {
                    Text("独立表示ができない環境のため、ミラー表示になっています（Swift Playgrounds 内で実行している場合など）。正式アプリ（AltStore でインストールした IPA）では独立表示を試みます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("出力の方法", selection: $model.settings.displayOutput) {
                    ForEach(DisplayOutputPreference.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("接続したら自動で HUD を表示（ミラー時）", isOn: $model.settings.autoStartHUDOnConnect)
                Toggle("HUD 表示中は自動ロックしない", isOn: $model.settings.power.keepsScreenAwake)
                if display.mode == .independent {
                    Button("端末の画面を暗くする") { model.isDeviceScreenBlanked = true }
                }
            } header: {
                Text("動作")
            } footer: {
                Text("「ミラーのみ」にすると、独立表示できる場合も端末とグラスの両方に HUD を表示します。")
            }
            Section {
                NavigationLink("表示位置・大きさ・最小文字サイズ") { CanvasSettingsView() }
                Button("視認性テストを表示（長押しで閉じる）") { model.showsTestPattern = true }
            } header: {
                Text("見え方の調整")
            } footer: {
                Text("黒（#000000）はグラス上で透明になります。視認性テストで、読める文字サイズ・色を確かめてください。")
            }
            if !display.events.isEmpty {
                Section("接続の記録") {
                    ForEach(display.events.reversed(), id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
        }
        .navigationTitle("外部ディスプレイ")
    }
}

// MARK: - 地図・ナビ・音声

struct MapVoiceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("地図エンジン", selection: Binding(get: { model.settings.map.engine }, set: { e in if e.isAvailable { model.settings.map.engine = e } })) {
                    ForEach(MapEngine.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("3D表示", isOn: $model.settings.map.use3D)
                Picker("ミニマップの向き", selection: $model.settings.map.orientation) {
                    ForEach(MapOrientation.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("現在地を追従", isOn: $model.settings.map.followsUser)
                Picker("標準の移動手段", selection: $model.settings.map.defaultTransport) {
                    ForEach(TransportMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("地図")
            } footer: {
                Text("Google Maps は APIキー・請求先の登録と従量課金が必要なため、現在は未対応です。公共交通は所要時間のみ表示し、経路は Apple マップのアプリで確認します。")
            }
            Section("音声案内") {
                Toggle("音声案内", isOn: $model.settings.voice.guidanceEnabled)
                LabeledSlider(title: "音量", value: $model.settings.voice.volume, range: 0...1, format: { "\(Int($0 * 100))%" })
                LabeledSlider(title: "話す速さ", value: $model.settings.voice.rate, range: 0.3...0.65, format: { String(format: "%.2f", $0) })
                LabeledSlider(title: "声の高さ", value: $model.settings.voice.pitch, range: 0.5...2, format: { String(format: "%.2f", $0) })
                Picker("声", selection: Binding(get: { model.settings.voice.voiceIdentifier ?? "" }, set: { model.settings.voice.voiceIdentifier = $0.isEmpty ? nil : $0 })) {
                    Text("標準（日本語）").tag("")
                    ForEach(model.speech.availableVoices, id: \.id) { v in
                        Text("\(v.name)（\(v.quality)）").tag(v.id)
                    }
                }
                Picker("案内の頻度", selection: $model.settings.voice.frequency) {
                    ForEach(GuidanceFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("到着予定時刻を定期的に読み上げ", isOn: $model.settings.voice.announceETA)
                Button("試しに読み上げる") {
                    model.speech.speak("200メートル先、右折です。到着予定は\(HUDFormat.spokenClock(Date().addingTimeInterval(600)))です。", force: true)
                }
                Text("より自然な声は、設定アプリ → アクセシビリティ → 読み上げコンテンツ → 声 から「拡張」「プレミアム」の日本語音声をダウンロードすると選べます（無料）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("地図・ナビ・音声")
        .onAppear { model.speech.loadVoices() }
    }
}

// MARK: - 通知

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model

    private func binding(_ category: AlertCategory, _ keyPath: WritableKeyPath<AlertChannelSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings.notifications.channel(for: category)[keyPath: keyPath] },
            set: { v in
                var c = model.settings.notifications.channel(for: category)
                c[keyPath: keyPath] = v
                model.settings.notifications.channels[category] = c
            }
        )
    }

    var body: some View {
        Form {
            ForEach(AlertCategory.allCases, id: \.self) { category in
                Section(category.displayName) {
                    Toggle("HUD に表示", isOn: binding(category, \.showsBanner))
                    Toggle("読み上げ", isOn: binding(category, \.speaks))
                    Toggle("警告音・振動", isOn: binding(category, \.playsSound))
                }
            }
            Section {
                Stepper("同じ通知を繰り返さない間隔：\(Int(model.settings.notifications.cooldownSeconds))秒",
                        value: Binding(get: { model.settings.notifications.cooldownSeconds }, set: { model.settings.notifications.cooldownSeconds = $0 }),
                        in: 5...300, step: 5)
                Button("端末の通知を許可する") { model.alerts.requestNotificationPermission() }
            } footer: {
                Text("移動中は重要度の低い通知を HUD に出しません（視界を優先）。アプリがバックグラウンドのとき、重要な通知は端末の通知で知らせます。")
            }
        }
        .navigationTitle("通知・警告")
    }
}

// MARK: - センサー

struct SensorsView: View {
    @Environment(AppModel.self) private var model
    @State private var importingGPX = false

    var body: some View {
        let loc = model.location
        let m = model.motion
        let d = model.device
        Form {
            Section("位置情報") {
                LabeledContent("許可", value: loc.authorization.displayName)
                if let s = loc.lastSample {
                    LabeledContent("緯度・経度", value: String(format: "%.5f, %.5f", s.coordinate.latitude, s.coordinate.longitude))
                    LabeledContent("精度", value: s.horizontalAccuracy >= 0 ? "±\(Int(s.horizontalAccuracy))m" : "--")
                    LabeledContent("速度", value: s.hasValidSpeed ? "\(HUDFormat.speed(s.speed, unit: .kilometersPerHour)) km/h" : "--")
                    LabeledContent("進行方向", value: s.hasValidCourse ? "\(Int(s.course))°" : "--")
                    LabeledContent("高度", value: s.altitude.map { "\(Int($0))m" } ?? "--")
                    LabeledContent("時刻", value: HUDFormat.clock(s.timestamp, seconds: true))
                } else {
                    Text("位置を取得中…（iPad の Wi-Fi モデルは GPS を搭載していません）").font(.caption)
                }
                if let place = loc.placeName { LabeledContent("地名", value: place) }
                if let e = loc.lastError { Text(e).font(.caption).foregroundStyle(UIStyle.warning) }
                if loc.authorization == .notDetermined { Button("位置情報を許可する") { loc.requestPermission() } }
            }
            Section("コンパス") {
                LabeledContent("方位", value: loc.heading.map { "\(Int($0))° \(Geo.cardinalName($0))" } ?? "--")
                LabeledContent("精度", value: loc.headingAccuracy.map { $0 >= 0 ? "±\(Int($0))°" : "要調整" } ?? "--")
            }
            Section("モーション") {
                if let a = m.attitude {
                    LabeledContent("ピッチ / ロール / ヨー", value: String(format: "%.0f° / %.0f° / %.0f°", a.pitch, a.roll, a.yaw))
                }
                LabeledContent("加速度", value: String(format: "%.3f G", m.userAcceleration))
                LabeledContent("回転", value: String(format: "%.2f rad/s", m.rotationRate))
                LabeledContent("移動状態（推定）", value: model.movement.displayName)
                LabeledContent("移動状態（モーション）", value: m.isActivityAvailable ? m.activity.displayName : "非対応")
                if m.isShakeDetected { Text("シェイクを検出").foregroundStyle(.orange) }
            }
            Section {
                if m.isHeadphoneMotionAvailable {
                    Toggle("AirPods の頭の向きを使う", isOn: Binding(get: { m.isHeadphoneTracking }, set: { $0 ? m.startHeadphoneTracking() : m.stopHeadphoneTracking() }))
                    if let h = m.headphoneAttitude {
                        LabeledContent("頭の向き", value: String(format: "上下 %.0f° / 左右 %.0f°", h.pitch, h.yaw))
                    }
                } else {
                    Text("対応する AirPods を接続すると、頭の向きを取得できます（VITURE の頭部トラッキングは iOS アプリから取得できません）。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("AirPods（頭の向き）")
            }
            Section("バッテリー・発熱") {
                LabeledContent("残量", value: d.batteryLevel >= 0 ? HUDFormat.percent(d.batteryLevel) : "--")
                LabeledContent("充電", value: d.isCharging ? "充電中" : "していない")
                LabeledContent("温度状態", value: d.thermal.displayName)
                LabeledContent("低電力モード", value: d.isLowPowerMode ? "オン" : "オフ")
                LabeledContent("省電力レベル", value: model.powerProfile.quality.displayName)
                if let mem = d.memoryMB { LabeledContent("メモリ", value: "\(Int(mem)) MB") }
            }
            Section {
                if loc.isSimulating {
                    LabeledContent("再生中", value: loc.simulationName ?? "")
                    Button("シミュレーションを止める", role: .destructive) { loc.stopSimulation() }
                } else {
                    Button("デモルートを再生（皇居外苑）") {
                        loc.startSimulation(points: DemoRoutes.densePolyline(), speed: 1.4, name: "デモ（皇居外苑）")
                        model.refreshServices()
                    }
                    Button("GPX ファイルを再生") { importingGPX = true }
                }
            } header: {
                Text("位置のシミュレーション")
            } footer: {
                Text("GPS のない iPad でもナビの動作を確かめられます。シミュレーション中は HUD に表示されます。")
            }
        }
        .navigationTitle("センサー情報")
        .serviceDemand([.location, .heading, .motion])
        .onAppear { m.startActivity() }
        .onDisappear { m.stopActivity() }
        .fileImporter(isPresented: $importingGPX, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml, .data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), loc.startSimulation(gpx: data, name: url.lastPathComponent) {
                model.refreshServices()
            } else {
                model.showToast("GPX を読み込めませんでした")
            }
        }
    }
}
