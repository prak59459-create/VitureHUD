import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if model.suggestion != nil { SuggestionCard() }
                    DisplayStatusCard()
                    QuickActionsCard()
                    PresetPickerCard()
                    NavigationSummaryCard()
                    HStack(alignment: .top, spacing: 14) {
                        WeatherSummaryCard()
                        DeviceSummaryCard()
                    }
                    NoticeBanner(text: "運転中は使用しないでください。歩行中も周囲の安全を優先してください。", systemImage: "exclamationmark.shield")
                }
                .padding()
            }
            .navigationTitle("HUD Navigator")
        }
    }
}

/// AI からの提案（ボタンで実行）
struct SuggestionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.suggestion {
            Card(title: "提案", systemImage: "lightbulb") {
                Text(s.title).font(.headline)
                Text(s.message).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    if let action = s.action {
                        Button(action.summary) { model.acceptSuggestion() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("閉じる") { model.suggestion = nil }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct DisplayStatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let display = model.display
        Card(title: "グラス", systemImage: display.mode.systemImage) {
            Text(display.statusDescription).font(.headline)
            switch display.mode {
            case .local:
                Text("VITURE を USB-C でつなぐと HUD を表示します。グラスがなくても「HUD を表示」で端末画面に表示できます。")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .mirror:
                Text("端末の画面がそのままグラスに映っています。HUD を全画面にして、端末を横向きにするとグラスいっぱいに表示されます。")
                    .font(.subheadline).foregroundStyle(.secondary)
            case .independent:
                Text("グラスに HUD、この画面は操作パネルです。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button {
                    model.isDeviceScreenBlanked = true
                } label: {
                    Label("この画面を暗くする（省電力）", systemImage: "moon")
                }
            }
            HUDRootView(surface: .thumbnail)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
        }
    }
}

struct QuickActionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "クイック操作", systemImage: "bolt") {
            HStack(spacing: 10) {
                if model.display.mode != .independent {
                    Button {
                        model.isHUDPresented = true
                    } label: {
                        Label("HUD を表示", systemImage: "eyeglasses").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    model.background = model.background.toggled
                } label: {
                    Label(model.background == .black ? "カメラ背景" : "黒背景", systemImage: model.background == .black ? "camera" : "circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            HStack(spacing: 10) {
                Button {
                    model.selectedTab = .navigation
                } label: {
                    Label("ナビ", systemImage: "map").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    model.settings.voice.guidanceEnabled.toggle()
                } label: {
                    Label(model.settings.voice.guidanceEnabled ? "音声案内オン" : "音声案内オフ", systemImage: model.settings.voice.guidanceEnabled ? "speaker.wave.2" : "speaker.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct PresetPickerCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "プリセット", systemImage: "square.stack") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                ForEach(model.presets) { preset in
                    Button {
                        model.applyPreset(preset.id)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.symbol).font(.title3)
                            Text(preset.name).font(.footnote).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(preset.id == model.activePresetID ? UIStyle.accent.opacity(0.25) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(preset.id == model.activePresetID ? UIStyle.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NavigationSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let nav = model.navigation
        Card(title: "ナビゲーション", systemImage: "location.north.line") {
            if nav.isGuiding, let route = nav.activeRoute {
                Text("\(route.destinationName)へ案内中").font(.headline)
                if let p = nav.progress {
                    Text("残り \(HUDFormat.distance(p.remainingDistance))・約\(HUDFormat.duration(p.remainingTime))・到着 \(HUDFormat.clock(p.eta(from: Date())))")
                        .font(.subheadline)
                }
                if let step = nav.nextStep, let d = nav.progress?.distanceToNextManeuver {
                    Label("\(HUDFormat.distance(d)) 先：\(step.instruction)", systemImage: step.maneuver.systemImage)
                        .font(.subheadline)
                }
                Button(role: .destructive) { nav.stop() } label: { Label("案内を終了", systemImage: "xmark.circle") }
            } else {
                Text("「東京駅までナビして」と話しかけるか、ナビ画面で目的地を選んでください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Button { model.selectedTab = .navigation } label: { Label("目的地を探す", systemImage: "magnifyingglass") }
                        .buttonStyle(.bordered)
                    Button {
                        startDemo()
                    } label: {
                        Label("デモ案内", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func startDemo() {
        let route = DemoRoutes.walkingRoute()
        model.location.startSimulation(points: route.polyline, speed: 1.6, name: "デモ（皇居外苑）")
        model.navigation.startDemo()
        model.refreshServices()
    }
}

struct WeatherSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "天気", systemImage: "cloud.sun") {
            if let w = model.weather.snapshot {
                HStack {
                    Image(systemName: w.symbolName).font(.title)
                    VStack(alignment: .leading) {
                        Text(w.temperature.map { "\(Int($0.rounded()))°C" } ?? "--").font(.title2.bold())
                        Text(w.conditionText).font(.subheadline)
                    }
                }
                Text("出典 \(w.source)・\(HUDFormat.clock(w.fetchedAt)) 取得").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(model.settings.privacy.weatherEnabled ? "天気ウィジェットを表示すると取得します" : "天気はオフです")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("詳しく") { model.open(.weather) }.font(.footnote)
        }
        .serviceDemand([.weather, .location])
    }
}

struct DeviceSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.device
        Card(title: "端末", systemImage: "iphone") {
            Text("電池 \(d.batteryLevel >= 0 ? HUDFormat.percent(d.batteryLevel) : "--")\(d.isCharging ? "（充電中）" : "")")
            Text("温度 \(d.thermal.displayName)")
                .foregroundStyle(d.thermal >= .serious ? UIStyle.danger : .primary)
            Text("省電力 \(model.powerProfile.quality.displayName)")
            if d.isLowPowerMode { Text("低電力モード").foregroundStyle(UIStyle.warning) }
        }
        .font(.subheadline)
    }
}
