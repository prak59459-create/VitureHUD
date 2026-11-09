import SwiftUI

/// HUD 全体。端末画面・グラス（外部画面）・編集プレビューで共通の View。
/// レイヤー：背景 → 物体認識の枠 → パネル → 通知・警告 → システム表示
struct HUDRootView: View {
    @Environment(AppModel.self) private var model
    let surface: HUDSurface

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let canvas = model.layout.canvas
            let content = CGSize(width: size.width * canvas.scale, height: size.height * canvas.scale)
            let origin = CGPoint(
                x: (size.width - content.width) / 2 + canvas.offsetX * size.width,
                y: (size.height - content.height) / 2 + canvas.offsetY * size.height
            )
            ZStack(alignment: .topLeading) {
                HUDBackgroundLayer(surface: surface)
                    .frame(width: size.width, height: size.height)

                if model.background == .camera && model.detectionActive && model.camera.activeSurface == surface {
                    DetectionOverlay()
                        .frame(width: size.width, height: size.height)
                }

                HUDPanelsLayer(surface: surface, canvasSize: content)
                    .frame(width: content.width, height: content.height)
                    .offset(x: origin.x, y: origin.y)

                if surface.isEditable {
                    EditorInteractionLayer(canvasSize: content)
                        .frame(width: content.width, height: content.height)
                        .offset(x: origin.x, y: origin.y)
                }

                if surface != .thumbnail {
                    HUDAlertLayer(canvasSize: content)
                        .frame(width: content.width, height: content.height)
                        .offset(x: origin.x, y: origin.y)
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
            .clipped()
        }
        .background(Color.black)
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
            minimumFontPixels: model.layout.canvas.minimumFontPixels
        )
        let demand: Set<WidgetRequirement> = (panel.isVisible && surface != .thumbnail) ? panel.widget.requirements : []
        WidgetContentView(panel: panel, style: style, typography: typography, theme: theme, surface: surface)
            .padding(.horizontal, rect.height * 0.12)
            .padding(.vertical, rect.height * 0.08)
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
        var text = d.label == .other ? d.rawLabel : d.label.displayName
        if settings.showsConfidence { text += " \(Int(d.confidence * 100))%" }
        if settings.showsDistanceEstimate, let distance = d.approximateDistance(verticalFieldOfViewDegrees: model.camera.verticalFieldOfView) {
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
