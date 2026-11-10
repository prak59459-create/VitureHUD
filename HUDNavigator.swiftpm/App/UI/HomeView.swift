import SwiftUI

/// ホーム：グラスの状態・HUD のプレビュー・よく使う操作をまとめたダッシュボード
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HomeHeader()
                    if model.suggestion != nil { SuggestionCard() }
                    HeroCard()
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "クイック操作")
                        QuickTiles()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "プリセット", trailing: "編集") { model.selectedTab = .hud }
                        PresetStrip()
                    }
                    NavigationSummaryCard()
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "状態")
                        StatusGrid()
                    }
                    NoticeBanner(text: "運転中は使用しないでください。歩行中も周囲の安全を優先してください。", systemImage: "exclamationmark.shield")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 110)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// アプリ名と、グラスの接続状態
struct HomeHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HUD Navigator")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(HUDFormat.date(Date()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConnectionChip()
        }
    }
}

struct ConnectionChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.display.mode {
        case .independent: StatusChip(text: "グラス接続中", color: UIStyle.success, showsDot: true)
        case .mirror: StatusChip(text: "ミラー表示", color: UIStyle.accent, showsDot: true)
        case .local: StatusChip(text: "グラス未接続", color: .secondary, showsDot: true)
        }
    }
}

/// AI からの提案（ボタンで実行）
struct SuggestionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let s = model.suggestion {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(UIStyle.accent)
                    Text("提案").font(.subheadline.weight(.semibold)).foregroundStyle(UIStyle.accent)
                    Spacer()
                    Button {
                        model.suggestion = nil
                    } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("閉じる")
                }
                Text(s.title).font(.headline)
                Text(s.message).font(.subheadline).foregroundStyle(.secondary)
                if let action = s.action {
                    Button(action.summary) { model.acceptSuggestion() }
                        .buttonStyle(.primaryCompact)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(highlighted: true)
        }
    }
}

/// グラスに映る HUD のプレビューと、いちばん大事な操作
struct HeroCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let display = model.display
        VStack(alignment: .leading, spacing: 14) {
            HUDRootView(surface: .thumbnail)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UIStyle.accent.opacity(0.35), lineWidth: 1))
                .shadow(color: UIStyle.accent.opacity(0.18), radius: 18, y: 6)
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                StatusChip(text: model.activePreset.name, systemImage: model.activePreset.symbol)
                StatusChip(text: model.background.displayName, systemImage: model.background == .black ? "moon.fill" : "camera.fill", color: .white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(display.statusDescription).font(.headline)
                Text(heroDescription(display.mode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch display.mode {
            case .independent:
                Button {
                    model.isDeviceScreenBlanked = true
                } label: {
                    Label("この画面を暗くする（省電力）", systemImage: "moon.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondaryAction)
            case .mirror, .local:
                Button {
                    model.isHUDPresented = true
                } label: {
                    Label("HUD を表示", systemImage: "eyeglasses").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                if display.mode == .local {
                    Button {
                        model.selectedTab = .settings
                        model.settingsPath = [.display]
                    } label: {
                        Label("つないでいるのに「未接続」のとき", systemImage: "questionmark.circle")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func heroDescription(_ mode: DisplayOutputMode) -> String {
        switch mode {
        case .local: return "VITURE を USB-C でつなぐと HUD を表示します。グラスがなくても端末の画面で試せます。"
        case .mirror: return "端末の画面がそのままグラスに映ります。HUD を全画面にして、端末を横向きにしてください。"
        case .independent: return "グラスに HUD を表示中。この画面は操作パネルです。"
        }
    }
}

/// よく使う操作（オンのものはシアンに光る）
struct QuickTiles: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let listening = model.speechInput.isListening
        let guidance = model.settings.voice.guidanceEnabled
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ActionTile(title: "背景", subtitle: model.background.displayName,
                       systemImage: model.background == .black ? "moon.fill" : "camera.fill", isOn: model.background == .camera) {
                model.background = model.background.toggled
            }
            ActionTile(title: "ナビ", subtitle: model.navigation.isGuiding ? "案内中" : "目的地を探す",
                       systemImage: "location.north.line.fill", isOn: model.navigation.isGuiding) {
                model.selectedTab = .navigation
            }
            ActionTile(title: "話しかける", subtitle: listening ? "聞き取り中…" : "音声で操作",
                       systemImage: listening ? "waveform" : "mic.fill", isOn: listening) {
                model.speechInput.toggle()
            }
            ActionTile(title: "音声案内", subtitle: guidance ? "オン" : "オフ",
                       systemImage: guidance ? "speaker.wave.2.fill" : "speaker.slash.fill", isOn: guidance) {
                model.settings.voice.guidanceEnabled.toggle()
            }
            ActionTile(title: "物体認識", subtitle: model.detectionActive ? "オン（実験）" : "オフ",
                       systemImage: "viewfinder", isOn: model.detectionActive) {
                let on = !model.detectionActive
                Task { await model.perform(.setDetection(on)) }
            }
            ActionTile(title: "距離", subtitle: model.settings.depth.enabled ? (model.depth.centerDistance.map { String(format: "正面 %.1f m", $0) } ?? "オン") : "オフ",
                       systemImage: "ruler.fill", isOn: model.settings.depth.enabled) {
                model.settings.depth.enabled.toggle()
            }
            ActionTile(title: "3D スキャン", subtitle: "周りを立体で記録", systemImage: "cube.transparent") {
                model.showsScan3D = true
            }
            ActionTile(title: "HUD を編集", subtitle: "配置・テーマ", systemImage: "slider.horizontal.3") {
                model.selectedTab = .hud
            }
        }
    }
}

/// プリセットを横に並べて切り替える
struct PresetStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.presets) { preset in
                    Button {
                        model.applyPreset(preset.id)
                    } label: {
                        SelectablePill(title: preset.name, systemImage: preset.symbol, isSelected: preset.id == model.activePresetID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

struct NavigationSummaryCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let nav = model.navigation
        if nav.isGuiding, let route = nav.activeRoute {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusChip(text: "案内中", systemImage: "location.north.line.fill", color: UIStyle.success)
                    Spacer()
                    Text(route.destinationName).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                if let step = nav.nextStep, let d = nav.progress?.distanceToNextManeuver {
                    HStack(spacing: 14) {
                        Image(systemName: step.maneuver.systemImage)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 60, height: 60)
                            .background(UIStyle.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(HUDFormat.distance(d)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(step.instruction).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                if let p = nav.progress {
                    HStack(spacing: 8) {
                        StatusChip(text: "残り \(HUDFormat.distance(p.remainingDistance))", color: .white)
                        StatusChip(text: "約\(HUDFormat.duration(p.remainingTime))", color: .white)
                        StatusChip(text: "到着 \(HUDFormat.clock(p.eta(from: Date())))", color: .white)
                    }
                }
                Button(role: .destructive) {
                    nav.stop()
                } label: {
                    Label("案内を終了", systemImage: "xmark.circle.fill").font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(highlighted: true)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "ナビゲーション")
                Button {
                    model.selectedTab = .navigation
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(UIStyle.accent)
                        Text("目的地を検索").foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .cardSurface(radius: UIStyle.tileRadius)
                }
                .buttonStyle(TilePressStyle())
                HStack(spacing: 10) {
                    Button {
                        startDemo()
                    } label: {
                        Label("デモ案内を試す", systemImage: "play.fill")
                    }
                    .buttonStyle(.secondaryCompact)
                    Text("「東京駅までナビして」と話しかけても始められます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

/// 端末・センサー・天気の状態
struct StatusGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.device
        let w = model.weather.snapshot
        let sample = model.location.lastSample
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(
                title: "電池",
                value: d.batteryLevel >= 0 ? HUDFormat.percent(d.batteryLevel) : "--",
                detail: d.isCharging ? "充電中" : (d.isLowPowerMode ? "低電力モード" : "省電力：\(model.powerProfile.quality.displayName)"),
                systemImage: d.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                tint: d.batteryLevel >= 0 && d.batteryLevel <= 0.2 && !d.isCharging ? UIStyle.danger : UIStyle.success
            )
            StatTile(
                title: "端末の温度",
                value: d.thermal.displayName,
                detail: d.memoryMB.map { "メモリ \(Int($0)) MB" },
                systemImage: "thermometer.medium",
                tint: d.thermal >= .serious ? UIStyle.danger : (d.thermal >= .fair ? UIStyle.warning : UIStyle.accent)
            )
            StatTile(
                title: "位置",
                value: sample.map { $0.horizontalAccuracy >= 0 ? "±\(Int($0.horizontalAccuracy)) m" : "--" } ?? "--",
                detail: model.location.placeName ?? (sample == nil ? "取得していません" : nil),
                systemImage: "location.fill"
            )
            Button {
                model.open(.weather)
            } label: {
                StatTile(
                    title: "天気",
                    value: w?.temperature.map { "\(Int($0.rounded()))°C" } ?? "--",
                    detail: w?.conditionText ?? (model.settings.privacy.weatherEnabled ? "取得中…" : "オフ"),
                    systemImage: w?.symbolName ?? "cloud.sun.fill",
                    tint: UIStyle.warning
                )
            }
            .buttonStyle(TilePressStyle())
        }
        .serviceDemand([.weather, .location])
    }
}
