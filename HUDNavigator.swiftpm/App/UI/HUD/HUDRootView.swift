import SwiftUI

/// HUD 全体。端末画面・グラス（外部画面）・編集プレビューで共通の View。
/// レイヤー：背景 → 物体認識の枠 → パネル → 通知・警告 → システム表示
struct HUDRootView: View {
    @Environment(AppModel.self) private var model
    let surface: HUDSurface

    enum StereoLayout: Equatable {
        /// ふつうの表示（2D）
        case none
        /// 16:9 の信号を左右に分ける（グラスが横に2倍に引き伸ばす）。設定で 3D を ON にしたとき
        case halfSideBySide
        /// 32:9（3840×1080 など）の信号：左右それぞれに 16:9 をそのまま描く。
        /// VITURE は 3D モードで 3840×1080（左右合計）を受け取るため、この大きさなら自動でこちらにする
        case fullSideBySide
    }

    static func stereoLayout(surface: HUDSurface, size: CGSize, stereoSetting: Bool) -> StereoLayout {
        guard surface == .external, size.width > 0, size.height > 0 else { return .none }
        if size.width / size.height >= 3 { return .fullSideBySide }
        return stereoSetting ? .halfSideBySide : .none
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // 奥行きは左右の画像の横のずらしで表現する（1080p 換算 px）
            let depth = model.settings.display.stereoDepth * size.height / 1080
            Group {
                switch Self.stereoLayout(surface: surface, size: size, stereoSetting: model.settings.display.stereo3D) {
                case .none:
                    scene(size: size, parallax: 0, stereo: false)
                case .halfSideBySide:
                    HStack(spacing: 0) {
                        halfEye(size: size, parallax: depth / 2)
                        halfEye(size: size, parallax: -depth / 2)
                            .environment(\.hudEyeIndex, 1)
                    }
                case .fullSideBySide:
                    let eye = CGSize(width: size.width / 2, height: size.height)
                    HStack(spacing: 0) {
                        scene(size: eye, parallax: depth / 2, stereo: true)
                            .frame(width: eye.width, height: eye.height)
                            .clipped()
                        scene(size: eye, parallax: -depth / 2, stereo: true)
                            .frame(width: eye.width, height: eye.height)
                            .clipped()
                            .environment(\.hudEyeIndex, 1)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .background(Color.black)
    }

    private func halfEye(size: CGSize, parallax: CGFloat) -> some View {
        scene(size: size, parallax: parallax, stereo: true)
            .frame(width: size.width, height: size.height)
            .scaleEffect(x: 0.5, y: 1)
            .frame(width: size.width / 2, height: size.height)
            .clipped()
    }

    private func scene(size: CGSize, parallax: CGFloat, stereo: Bool) -> some View {
        let canvas = model.layout.canvas
        let content = CGSize(width: size.width * canvas.scale, height: size.height * canvas.scale)
        let head = headLockOffset(size: size)
        let headRoll = headLockRoll
        let origin = CGPoint(
            x: (size.width - content.width) / 2 + canvas.offsetX * size.width + head.width + parallax,
            y: (size.height - content.height) / 2 + canvas.offsetY * size.height + head.height
        )
        // 明るさ（夜間は自動で暗く）。編集中・サムネイルは常に 100%
        let brightness = surface.isEditable || surface == .thumbnail ? 1 : model.hudBrightness
        return ZStack(alignment: .topLeading) {
            if stereo {
                // 3D では背景は黒（＝透明）。カメラ映像は左右に複製できないため。
                Color.black.frame(width: size.width, height: size.height)
            } else {
                HUDBackgroundLayer(surface: surface)
                    .frame(width: size.width, height: size.height)

                if model.background == .camera && model.detectionActive && model.camera.activeSurface == surface {
                    DetectionOverlay()
                        .frame(width: size.width, height: size.height)
                } else if model.background == .black && model.detectionActive && model.settings.detection.showsBoxesOnBlack
                            && (surface == .external || surface == .deviceFullScreen) && model.camera.isRunning {
                    // 黒背景：カメラ映像は出さず、検出した物の位置（おおよそ）だけ描く
                    DetectionOverlay()
                        .frame(width: size.width, height: size.height)
                }
                if model.settings.depth.enabled && surface != .thumbnail && !surface.isEditable && model.depth.isFresh {
                    DepthOverlay()
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                }
            }

            HUDPanelsLayer(surface: surface, canvasSize: content)
                .frame(width: content.width, height: content.height)
                .rotationEffect(.degrees(headRoll))
                .offset(x: origin.x, y: origin.y)
                .opacity(brightness)

            if surface.isEditable {
                EditorInteractionLayer(canvasSize: content)
                    .frame(width: content.width, height: content.height)
                    .offset(x: origin.x, y: origin.y)
            }

            if surface != .thumbnail {
                HUDAlertLayer(canvasSize: content)
                    .frame(width: content.width, height: content.height)
                    .offset(x: origin.x, y: origin.y)
                    .opacity(max(brightness, 0.7))
                    .allowsHitTesting(false)

                SystemIndicatorLayer(surface: surface, canvasSize: size)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }

            if surface == .external && model.showsTestPattern {
                VisibilityTestPattern()
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// 頭の向きで HUD を逆向きにずらす（頭を動かしても HUD が空間に留まって見える）
    private func headLockOffset(size: CGSize) -> CGSize {
        let h = model.settings.headTracking
        guard h.headLock, !surface.isEditable, surface != .thumbnail, let pose = model.headTracking.pose else { return .zero }
        let o = HeadLock.offset(for: pose, pixelsPerDegree: h.strength * size.height / 1080, width: size.width, height: size.height)
        return CGSize(width: o.x, height: o.y)
    }

    /// 頭を傾けたとき HUD を逆に回す（水平を保つ）
    private var headLockRoll: Double {
        let h = model.settings.headTracking
        guard h.headLock, h.compensatesRoll, !surface.isEditable, surface != .thumbnail, let pose = model.headTracking.pose else { return 0 }
        return -pose.roll
    }
}

// MARK: - 背景

struct HUDBackgroundLayer: View {
    @Environment(AppModel.self) private var model
    let surface: HUDSurface

    var body: some View {
        if model.background == .camera && surface != .thumbnail {
            CameraBackground(surface: surface)
        } else if model.background == .camera {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
        } else {
            // 純粋な黒（#000000）＝グラス上では透明
            Color.black
        }
    }
}

struct CameraBackground: View {
    @Environment(AppModel.self) private var model
    let surface: HUDSurface

    var body: some View {
        let camera = model.camera
        ZStack {
            Color.black
            CameraPreviewView(session: camera.pipeline.session, isActive: camera.activeSurface == surface, rotationAngle: camera.rotationAngle)
                .contrast(model.settings.camera.contrast)
            if camera.authorization == .denied {
                Label("カメラが許可されていません", systemImage: "video.slash")
                    .foregroundStyle(.white)
            } else if let active = camera.activeSurface, active != surface {
                Label(active == .external ? "カメラ映像はグラスに表示中" : "カメラ映像は別の画面に表示中", systemImage: "video")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else if let error = camera.lastError {
                Text(error).font(.caption).foregroundStyle(.white)
            }
        }
        .onAppear { camera.acquire(surface) }
        .onDisappear { camera.release(surface) }
    }
}

// MARK: - パネル

struct HUDPanelsLayer: View {
    @Environment(AppModel.self) private var model
    let surface: HUDSurface
    let canvasSize: CGSize

    var body: some View {
        let theme = model.activeTheme
        let panels = surface.isEditable ? model.layout.panelsInDrawingOrder : model.effectivePanels
        ZStack(alignment: .topLeading) {
            ForEach(panels) { panel in
                HUDPanelView(panel: panel, theme: theme, canvasSize: canvasSize, surface: surface)
            }
            if model.hudMinimizedForSpeed && !surface.isEditable {
                Text("移動速度が速いため HUD を最小化しています")
                    .font(.system(size: max(14, canvasSize.height * 0.03), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(theme.warningColor))
                    .position(x: canvasSize.width / 2, y: canvasSize.height * 0.9)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

struct HUDPanelView: View {
    @Environment(AppModel.self) private var model
    let panel: HUDPanel
    let theme: Theme
    let canvasSize: CGSize
    let surface: HUDSurface

    var body: some View {
        let rect = panel.frame.denormalized(in: HUDSize(width: canvasSize.width, height: canvasSize.height))
        let style = panel.style.applied(to: theme.style)
        let typography = HUDTypography(
            panelHeight: rect.height,
            canvasHeight: canvasSize.height,
            style: style,
            minimumFontPixels: model.layout.canvas.minimumFontPixels,
            textScale: model.layout.canvas.textScale
        )
        let demand: Set<WidgetRequirement> = (panel.isVisible && surface != .thumbnail) ? panel.widget.requirements : []
        // 行を並べるウィジェット（メモ・ブラウザなど）は背が高いので、余白を画面全体の大きさから決める
        let listStyle = panel.widget.isListStyle
        let listPadding = canvasSize.height * (panel.widget == .webPage ? 0.006 : 0.016)
        WidgetContentView(panel: panel, style: style, typography: typography, theme: theme, surface: surface)
            .padding(.horizontal, listStyle ? listPadding : rect.height * 0.12)
            .padding(.vertical, listStyle ? listPadding : rect.height * 0.08)
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .background(PanelChrome(style: style, allowsGlow: model.powerProfile.allowsGlowEffects))
            .opacity(panel.isVisible ? panel.opacity : 0.25)
            .position(x: rect.midX, y: rect.midY)
            .serviceDemand(demand)
    }
}

/// パネルの背景・枠・影・発光
struct PanelChrome: View {
    let style: PanelStyle
    var allowsGlow: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        shape
            .fill(Color(style.backgroundColor).opacity(style.backgroundOpacity))
            .overlay(shape.stroke(Color(style.borderColor), lineWidth: style.borderWidth))
            .shadow(color: .black.opacity(style.shadowRadius > 0 ? 0.6 : 0), radius: style.shadowRadius)
            .shadow(color: Color(style.glowColor).opacity(allowsGlow && style.glowRadius > 0 ? 0.9 : 0), radius: allowsGlow ? style.glowRadius : 0)
    }
}

// MARK: - 物体認識の枠

struct DetectionOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let aspect = max(0.1, model.camera.imageAspect)
            let viewAspect = size.width / max(1, size.height)
            // プレビューは aspect fill なので、表示されている画像の大きさを求める
            let displayW = viewAspect > aspect ? size.width : size.height * aspect
            let displayH = viewAspect > aspect ? size.width / aspect : size.height
            let ox = (size.width - displayW) / 2
            let oy = (size.height - displayH) / 2
            let settings = model.settings.detection
            let theme = model.activeTheme
            ZStack(alignment: .topLeading) {
                if settings.detectsLanes {
                    // 路面の線の候補（実験）
                    Path { p in
                        for line in model.vision.lanes {
                            p.move(to: CGPoint(x: ox + line.start.x * displayW, y: oy + line.start.y * displayH))
                            p.addLine(to: CGPoint(x: ox + line.end.x * displayW, y: oy + line.end.y * displayH))
                        }
                    }
                    .stroke(Color(theme.style.accentColor).opacity(0.8), style: StrokeStyle(lineWidth: max(3, size.height * 0.006), lineCap: .round, dash: [size.height * 0.03, size.height * 0.015]))
                }
                if settings.readsSigns {
                    ForEach(model.vision.signs) { sign in
                        let r = CGRect(x: ox + sign.box.x * displayW, y: oy + sign.box.y * displayH, width: sign.box.width * displayW, height: sign.box.height * displayH)
                        let color: Color = sign.reading.isImportant ? Color(theme.warningColor) : Color(theme.style.secondaryTextColor)
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                        Text(sign.reading.kind)
                            .font(.system(size: max(12, size.height * 0.022), weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .position(x: r.midX, y: min(size.height - 10, r.maxY + size.height * 0.02))
                    }
                }
                ForEach(model.vision.detections) { d in
                    let r = CGRect(x: ox + d.box.x * displayW, y: oy + d.box.y * displayH, width: d.box.width * displayW, height: d.box.height * displayH)
                    let level = model.vision.hazards.first { $0.trackID == d.trackID }?.level ?? .none
                    let color: Color = level >= .high ? Color(theme.dangerColor) : level >= .medium ? Color(theme.warningColor) : Color(theme.style.accentColor)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color, lineWidth: level >= .medium ? 4 : 2)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                    if settings.showsLabels {
                        Text(label(for: d, settings: settings))
                            .font(.system(size: max(12, size.height * 0.022), weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.5), in: Capsule())
                            .position(x: r.midX, y: max(10, r.minY - size.height * 0.02))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func label(for d: Detection, settings: DetectionSettings) -> String {
        var text = ObjectLabels.displayName(label: d.label, raw: d.rawLabel)
        if settings.showsConfidence { text += " \(Int(d.confidence * 100))%" }
        if model.settings.depth.enabled && model.settings.depth.showsObjectDistance, let measured = model.depth.distance(for: d.box) {
            text += " \(String(format: "%.1f", measured))m"
        } else if settings.showsDistanceEstimate, let distance = d.approximateDistance(verticalFieldOfViewDegrees: model.camera.verticalFieldOfView) {
            text += " 約\(Int(distance.rounded()))m(目安)"
        }
        return text
    }
}

// MARK: - 通知・警告

struct HUDAlertLayer: View {
    @Environment(AppModel.self) private var model
    let canvasSize: CGSize

    var body: some View {
        let theme = model.activeTheme
        let fontSize = max(14, canvasSize.height * 0.032)
        ZStack(alignment: .top) {
            if model.alerts.hazardFlash > .none {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(model.alerts.hazardFlash >= .high ? theme.dangerColor : theme.warningColor), lineWidth: max(6, canvasSize.height * 0.012))
                    .padding(4)
                    .transition(.opacity)
            }
            VStack(spacing: canvasSize.height * 0.01) {
                ForEach(model.alerts.visible) { alert in
                    HStack(spacing: 8) {
                        Image(systemName: icon(alert))
                            .font(.system(size: fontSize, weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title).font(.system(size: fontSize, weight: .bold, design: .rounded))
                            if !alert.message.isEmpty {
                                Text(alert.message).font(.system(size: fontSize * 0.7, weight: .medium, design: .rounded)).lineLimit(2)
                            }
                        }
                    }
                    .foregroundStyle(color(alert, theme: theme))
                    .padding(.horizontal, fontSize * 0.8)
                    .padding(.vertical, fontSize * 0.4)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(color(alert, theme: theme).opacity(0.6), lineWidth: 1))
                    .frame(maxWidth: canvasSize.width * 0.5)
                }
            }
            .padding(.top, canvasSize.height * 0.2)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .animation(.easeOut(duration: 0.25), value: model.alerts.visible.map(\.id))
    }

    private func icon(_ a: HUDAlert) -> String {
        switch a.category {
        case .hazard: return "exclamationmark.triangle.fill"
        case .arrival: return "flag.checkered"
        case .reroute: return "arrow.triangle.branch"
        case .battery: return "battery.25percent"
        case .connection: return "eyeglasses"
        case .weather: return "cloud.sun"
        case .assistant: return "waveform"
        default: return "bell"
        }
    }

    private func color(_ a: HUDAlert, theme: Theme) -> Color {
        switch a.priority {
        case .critical: return Color(theme.dangerColor)
        case .important: return Color(theme.warningColor)
        default: return Color(theme.style.textColor)
        }
    }
}

// MARK: - システム表示（カメラ使用中など。非表示にできない）

struct SystemIndicatorLayer: View {
    @Environment(AppModel.self) private var model
    let surface: HUDSurface
    let canvasSize: CGSize

    var body: some View {
        let fontSize = max(10, canvasSize.height * 0.018)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if model.camera.activeSurface != nil && model.camera.isRunning {
                    indicator("カメラ使用中", systemImage: "circle.fill", color: .red)
                }
                if model.detectionActive && model.background == .camera {
                    indicator("物体認識（実験）", systemImage: "viewfinder", color: .yellow)
                }
                if model.location.isSimulating {
                    indicator("位置シミュレーション", systemImage: "location.slash", color: .orange)
                }
                if model.speechInput.isListening {
                    indicator("聞き取り中", systemImage: "mic.fill", color: .orange)
                }
                if model.powerProfile.quality != .normal {
                    indicator("省電力：\(model.powerProfile.quality.displayName)", systemImage: "leaf", color: .green)
                }
                if model.settings.headTracking.headLock && model.headTracking.pose != nil {
                    indicator("空間固定（\(model.settings.headTracking.source.displayName)）", systemImage: "move.3d", color: .cyan)
                }
                if model.settings.depth.enabled && model.depth.isFresh {
                    indicator("距離：\(model.depth.sourceLabel)", systemImage: "ruler", color: .mint)
                }
                if model.workspace.focus.isRunning && !model.layout.contains(widget: .focusTimer) {
                    indicator(model.workspace.focus.phase.displayName, systemImage: "timer", color: .cyan)
                }
            }
            if model.settings.showsMetricsOverlay {
                Text(metricsText)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .padding(canvasSize.height * 0.015)
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }

    private var metricsText: String {
        var parts = ["\(Int(model.metrics.fps.rounded()))fps"]
        if model.vision.isActive { parts.append("推論\(String(format: "%.1f", model.vision.inferenceFPS))fps") }
        parts.append("温度:\(model.device.thermal.displayName)")
        if model.device.batteryLevel >= 0 { parts.append("電池\(HUDFormat.percent(model.device.batteryLevel))") }
        if let mem = model.device.memoryMB { parts.append("\(Int(mem))MB") }
        return parts.joined(separator: " ")
    }

    private func indicator(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.5), in: Capsule())
    }
}

// MARK: - サービスの要求

/// ウィジェットが表示されている間だけ、必要なセンサーなどを動かす
struct ServiceDemandModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    let requirements: Set<WidgetRequirement>
    @State private var held: Set<WidgetRequirement> = []

    func body(content: Content) -> some View {
        content
            .onAppear { swap(to: requirements) }
            .onDisappear { swap(to: []) }
            .onChange(of: requirements) { _, new in swap(to: new) }
    }

    private func swap(to new: Set<WidgetRequirement>) {
        guard new != held else { return }
        model.release(held)
        model.acquire(new)
        held = new
    }
}

extension View {
    func serviceDemand(_ requirements: Set<WidgetRequirement>) -> some View {
        modifier(ServiceDemandModifier(requirements: requirements))
    }
}

// MARK: - 距離の表示

/// 距離の格子（数字・色）・中央の照準・近い物の警告。カメラ映像の位置に合わせて描く（黒背景ではおおよそ）
struct DepthOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let aspect = max(0.1, model.camera.imageAspect)
            let viewAspect = size.width / max(1, size.height)
            let displayW = viewAspect > aspect ? size.width : size.height * aspect
            let displayH = viewAspect > aspect ? size.width / aspect : size.height
            let ox = (size.width - displayW) / 2
            let oy = (size.height - displayH) / 2
            let s = model.settings.depth
            let theme = model.activeTheme
            let fontSize = max(11, size.height * 0.02)
            ZStack(alignment: .topLeading) {
                if let grid = model.depth.grid {
                    // 粗い格子（4 列 × 5 行）で数字を出す
                    let cols = 4, rows = 5
                    if s.showsHeatmap && grid.isMetric {
                        ForEach(0..<(grid.columns * grid.rows), id: \.self) { i in
                            let c = i % grid.columns, r = i / grid.columns
                            if let v = grid.value(column: c, row: r) {
                                Rectangle()
                                    .fill(Self.color(for: Double(v)).opacity(0.28))
                                    .frame(width: displayW / CGFloat(grid.columns), height: displayH / CGFloat(grid.rows))
                                    .position(x: ox + (CGFloat(c) + 0.5) * displayW / CGFloat(grid.columns), y: oy + (CGFloat(r) + 0.5) * displayH / CGFloat(grid.rows))
                            }
                        }
                    }
                    if s.showsGrid {
                        ForEach(0..<(cols * rows), id: \.self) { i in
                            let c = i % cols, r = i / cols
                            let rect = NormalizedRect(x: Double(c) / Double(cols), y: Double(r) / Double(rows), width: 1 / Double(cols), height: 1 / Double(rows))
                            if let v = grid.median(in: rect) {
                                Text(grid.isMetric ? String(format: "%.1f", v) : (v > 0.66 ? "近" : v > 0.33 ? "中" : "遠"))
                                    .font(.system(size: fontSize, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(grid.isMetric ? Self.color(for: Double(v)) : Color(theme.style.secondaryTextColor))
                                    .position(x: ox + (CGFloat(c) + 0.5) * displayW / CGFloat(cols), y: oy + (CGFloat(r) + 0.5) * displayH / CGFloat(rows))
                            }
                        }
                    }
                }
                if s.showsReticle {
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    Circle()
                        .stroke(Color(theme.style.accentColor), lineWidth: 2)
                        .frame(width: fontSize * 1.6, height: fontSize * 1.6)
                        .position(center)
                    Text(model.depth.centerDistance.map { String(format: "%.2f m", $0) } ?? "--")
                        .font(.system(size: fontSize * 1.2, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color(theme.style.accentColor))
                        .padding(.horizontal, 6)
                        .background(Color.black.opacity(0.45), in: Capsule())
                        .position(x: center.x, y: center.y + fontSize * 1.8)
                }
                if let o = model.depth.obstacle {
                    let color = o.level >= .high ? Color(theme.dangerColor) : Color(theme.warningColor)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color, lineWidth: 4)
                        .frame(width: displayW * 0.18, height: displayH * 0.18)
                        .position(x: ox + o.x * displayW, y: size.height * 0.5)
                }
            }
        }
    }

    /// 近い＝赤、2m＝黄、5m 以上＝緑
    static func color(for meters: Double) -> Color {
        if meters < 1 { return .red }
        if meters < 2 { return .orange }
        if meters < 3.5 { return .yellow }
        if meters < 6 { return .green }
        return .cyan
    }
}
