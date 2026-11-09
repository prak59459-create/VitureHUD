import SwiftUI
import MapKit

/// ウィジェットの中身（種類ごと）
struct WidgetContentView: View {
    let panel: HUDPanel
    let style: PanelStyle
    let typography: HUDTypography
    let theme: Theme
    let surface: HUDSurface

    var body: some View {
        let ctx = WidgetContext(panel: panel, style: style, typography: typography, theme: theme, surface: surface)
        switch panel.widget {
        case .clock: ClockWidget(ctx: ctx)
        case .date: DateWidget(ctx: ctx)
        case .battery: BatteryWidget(ctx: ctx)
        case .speed: SpeedWidget(ctx: ctx)
        case .compass: CompassWidget(ctx: ctx)
        case .miniMap:
            if surface == .thumbnail { SchematicMiniMap(ctx: ctx) } else { MiniMapWidget(ctx: ctx) }
        case .weather: WeatherWidget(ctx: ctx)
        case .temperature: TemperatureWidget(ctx: ctx)
        case .precipitation: PrecipitationWidget(ctx: ctx)
        case .airQuality: AirQualityWidget(ctx: ctx)
        case .tripDistance: TripDistanceWidget(ctx: ctx)
        case .eta: ETAWidget(ctx: ctx)
        case .nextTurn: NextTurnWidget(ctx: ctx)
        case .notifications: NotificationsWidget(ctx: ctx)
        case .gpsStatus: GPSStatusWidget(ctx: ctx)
        case .sensors: SensorsWidget(ctx: ctx)
        case .assistant: AssistantWidget(ctx: ctx)
        case .detections: DetectionsWidget(ctx: ctx)
        case .customText: CustomTextWidget(ctx: ctx)
        case .heartRate: HeartRateWidget(ctx: ctx)
        case .horizon: HorizonWidget(ctx: ctx)
        case .hourlyForecast: HourlyForecastWidget(ctx: ctx)
        case .nearbyPlaces: NearbyPlacesWidget(ctx: ctx)
        }
    }
}

struct WidgetContext {
    let panel: HUDPanel
    let style: PanelStyle
    let typography: HUDTypography
    let theme: Theme
    let surface: HUDSurface

    var config: WidgetConfig { panel.config }
    var text: Color { Color(style.textColor) }
    var secondary: Color { Color(style.secondaryTextColor) }
    var accent: Color { Color(style.accentColor) }
    var warning: Color { Color(theme.warningColor) }
    var danger: Color { Color(theme.dangerColor) }
}

/// 値（大）＋説明（小）＋アイコンの共通レイアウト
struct MetricView: View {
    let ctx: WidgetContext
    var icon: String?
    var value: String
    var unit: String?
    var caption: String?
    var valueColor: Color?
    var iconRotation: Double = 0

    var body: some View {
        let t = ctx.typography
        HStack(spacing: t.size(0.12)) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: t.iconSize, weight: .semibold))
                    .foregroundStyle(ctx.accent)
                    .rotationEffect(.degrees(iconRotation))
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: t.size(0.04)) {
                    Text(value)
                        .font(t.primary)
                        .foregroundStyle(valueColor ?? ctx.text)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit).font(t.secondary).foregroundStyle(ctx.secondary)
                    }
                }
                if let caption, ctx.config.showsLabel {
                    Text(caption)
                        .font(t.secondary)
                        .foregroundStyle(ctx.secondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.35)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(ctx.style.animation == .pulse ? nil : ctx.style.animation.animation, value: value)
    }
}

struct ClockWidget: View {
    let ctx: WidgetContext
    var body: some View {
        TimelineView(.periodic(from: .now, by: ctx.config.showsSeconds ? 1 : 10)) { timeline in
            MetricView(ctx: ctx, value: HUDFormat.clock(timeline.date, seconds: ctx.config.showsSeconds, use24Hour: ctx.config.uses24Hour))
        }
    }
}

struct DateWidget: View {
    let ctx: WidgetContext
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            MetricView(ctx: ctx, icon: ctx.config.compact ? nil : "calendar", value: HUDFormat.date(timeline.date))
        }
    }
}

struct BatteryWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let level = model.device.batteryLevel
        let icon: String
        switch level {
        case ..<0: icon = "battery.0percent"
        case ..<0.15: icon = "battery.0percent"
        case ..<0.4: icon = "battery.25percent"
        case ..<0.65: icon = "battery.50percent"
        case ..<0.9: icon = "battery.75percent"
        default: icon = "battery.100percent"
        }
        return MetricView(
            ctx: ctx,
            icon: model.device.isCharging ? "battery.100percent.bolt" : icon,
            value: level >= 0 ? HUDFormat.percent(level) : "--",
            caption: model.device.isCharging ? "充電中" : (model.device.isLowPowerMode ? "低電力モード" : nil),
            valueColor: level >= 0 && level < 0.2 && !model.device.isCharging ? ctx.warning : nil
        )
    }
}

struct SpeedWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let sample = model.location.lastSample
        let valid = sample?.hasValidSpeed == true && (sample?.isAccurateEnough ?? false)
        MetricView(
            ctx: ctx,
            icon: ctx.config.compact ? nil : "speedometer",
            value: valid ? HUDFormat.speed(sample!.speed, unit: ctx.config.speedUnit) : "--",
            unit: ctx.config.speedUnit.symbol,
            caption: model.movement.isMoving ? model.movement.displayName : "速度"
        )
    }
}

struct CompassWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let heading = model.location.heading ?? (model.location.lastSample.flatMap { $0.hasValidCourse ? $0.course : nil })
        let t = ctx.typography
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(ctx.secondary.opacity(0.5), lineWidth: 1)
                Image(systemName: "location.north.fill")
                    .font(.system(size: t.size(0.32)))
                    .foregroundStyle(ctx.accent)
                    .rotationEffect(.degrees(-(heading ?? 0)))
                Text("N")
                    .font(.system(size: t.size(0.13), weight: .bold))
                    .foregroundStyle(ctx.danger)
                    .offset(y: -t.size(0.3))
                    .rotationEffect(.degrees(-(heading ?? 0)))
            }
            .aspectRatio(1, contentMode: .fit)
            Text(heading.map { "\(Geo.cardinalName($0)) \(Int($0.rounded()))°" } ?? "方位 --")
                .font(t.secondary)
                .foregroundStyle(ctx.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MiniMapWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let sample = model.location.lastSample
        let headingUp = model.settings.map.orientation == .headingUp
        let heading = headingUp ? (model.location.heading ?? sample.flatMap { $0.hasValidCourse ? $0.course : nil } ?? 0) : 0
        let use3D = model.settings.map.use3D
        let position = cameraPosition(sample: sample, heading: heading, use3D: use3D)
        let route = model.navigation.activeRoute
        Map(position: .constant(position), interactionModes: []) {
            if let route {
                MapPolyline(coordinates: route.polyline.map(\.clCoordinate))
                    .stroke(ctx.accent, lineWidth: 5)
                if let dest = route.destination {
                    Marker("目的地", systemImage: "flag.checkered", coordinate: dest.clCoordinate)
                        .tint(ctx.warning)
                }
            }
            if let sample {
                Annotation("", coordinate: sample.coordinate.clCoordinate) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(ctx.accent)
                        .rotationEffect(.degrees(headingUp ? 0 : (model.location.heading ?? 0)))
                }
            }
        }
        .mapStyle(.standard(elevation: use3D ? .realistic : .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: max(4, ctx.style.cornerRadius * 0.7), style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if sample == nil {
                Text("現在地を取得中…")
                    .font(ctx.typography.font(0.07))
                    .foregroundStyle(ctx.secondary)
                    .padding(6)
            }
        }
        .allowsHitTesting(false)
    }

    private func cameraPosition(sample: LocationSample?, heading: Double, use3D: Bool) -> MapCameraPosition {
        guard let sample else { return .userLocation(fallback: .automatic) }
        let camera = MapCamera(centerCoordinate: sample.coordinate.clCoordinate, distance: ctx.config.mapSpanMeters * 2.2, heading: heading, pitch: use3D ? 50 : 0)
        return .camera(camera)
    }
}

/// 軽量な簡易ミニマップ（サムネイル・スナップショット用。MapKit を使わずルートと現在地だけを描く）
struct SchematicMiniMap: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext

    var body: some View {
        let route = model.navigation.activeRoute
        let center = model.location.lastSample?.coordinate ?? model.navigation.progress?.snappedCoordinate ?? route?.polyline.first
        let heading = model.settings.map.orientation == .headingUp ? (model.navigation.progress?.routeBearing ?? model.location.heading ?? 0) : 0
        let span = ctx.config.mapSpanMeters * 2.2
        Canvas { context, size in
            let gridColor = ctx.secondary.opacity(0.18)
            for i in 1..<4 {
                let x = size.width * Double(i) / 4
                let y = size.height * Double(i) / 4
                var grid = Path()
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(gridColor), lineWidth: 1)
            }
            guard let center else { return }
            let metersPerPoint = span / max(1, min(size.width, size.height))
            // 進行方向が上になるように、地図を進行方向の角度だけ回す
            let rad = heading * .pi / 180
            func project(_ c: GeoCoordinate) -> CGPoint {
                let dx = (c.longitude - center.longitude) * cos(center.latitude * .pi / 180) * 111_320
                let dy = (c.latitude - center.latitude) * 110_540
                let rx = dx * cos(rad) - dy * sin(rad)
                let ry = dx * sin(rad) + dy * cos(rad)
                return CGPoint(x: size.width / 2 + rx / metersPerPoint, y: size.height / 2 - ry / metersPerPoint)
            }
            if let route, route.polyline.count > 1 {
                var path = Path()
                path.move(to: project(route.polyline[0]))
                for p in route.polyline.dropFirst() { path.addLine(to: project(p)) }
                context.stroke(path, with: .color(ctx.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                if let dest = route.destination {
                    let d = project(dest)
                    context.fill(Path(ellipseIn: CGRect(x: d.x - 7, y: d.y - 7, width: 14, height: 14)), with: .color(ctx.warning))
                }
            }
            var arrow = Path()
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            arrow.move(to: CGPoint(x: c.x, y: c.y - 12))
            arrow.addLine(to: CGPoint(x: c.x + 9, y: c.y + 10))
            arrow.addLine(to: CGPoint(x: c.x, y: c.y + 4))
            arrow.addLine(to: CGPoint(x: c.x - 9, y: c.y + 10))
            arrow.closeSubpath()
            context.fill(arrow, with: .color(ctx.text))
        }
        .clipShape(RoundedRectangle(cornerRadius: max(4, ctx.style.cornerRadius * 0.7), style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if center == nil {
                Text("現在地を取得中…").font(ctx.typography.font(0.07)).foregroundStyle(ctx.secondary).padding(6)
            }
        }
    }
}

struct WeatherWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        if let w = model.weather.snapshot {
            MetricView(
                ctx: ctx,
                icon: w.symbolName,
                value: w.temperature.map { "\(Int($0.rounded()))°" } ?? "--",
                caption: "\(w.conditionText)・\(w.source) \(HUDFormat.clock(w.fetchedAt))"
            )
        } else {
            MetricView(ctx: ctx, icon: "cloud", value: "--", caption: weatherStatus)
        }
    }

    private var weatherStatus: String {
        if !model.settings.privacy.weatherEnabled { return "天気はオフ" }
        if model.weather.isLoading { return "取得中…" }
        if let e = model.weather.lastError { return e }
        return model.location.lastSample == nil ? "現在地を待っています" : "取得中…"
    }
}

struct TemperatureWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let w = model.weather.snapshot
        MetricView(
            ctx: ctx,
            icon: ctx.config.compact ? nil : "thermometer.medium",
            value: w?.temperature.map { "\(Int($0.rounded()))°" } ?? "--",
            caption: w?.apparentTemperature.map { "体感 \(Int($0.rounded()))°" } ?? "気温"
        )
    }
}

struct PrecipitationWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let w = model.weather.snapshot
        MetricView(
            ctx: ctx,
            icon: ctx.config.compact ? nil : "umbrella",
            value: w?.precipitationProbability.map { "\(Int($0.rounded()))%" } ?? "--",
            caption: w?.precipitation.map { String(format: "降水量 %.1fmm", $0) } ?? "降水確率"
        )
    }
}

struct AirQualityWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let w = model.weather.snapshot
        MetricView(
            ctx: ctx,
            icon: ctx.config.compact ? nil : "aqi.medium",
            value: w?.pm25.map { "\(Int($0.rounded()))" } ?? "--",
            unit: "PM2.5",
            caption: [w?.airQualityText, w?.uvIndex.map { String(format: "UV %.0f", $0) }].compactMap { $0 }.joined(separator: "・")
        )
    }
}

struct TripDistanceWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let distance = model.history.isRecording ? model.history.currentDistance : model.history.sessionDistance
        MetricView(ctx: ctx, icon: ctx.config.compact ? nil : "figure.walk", value: HUDFormat.distance(distance), caption: model.history.isRecording ? "記録中" : "移動距離")
    }
}

struct ETAWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        if let p = model.navigation.progress, model.navigation.isGuiding {
            TimelineView(.periodic(from: .now, by: 15)) { timeline in
                MetricView(
                    ctx: ctx,
                    icon: ctx.config.compact ? nil : "flag.checkered",
                    value: HUDFormat.clock(p.eta(from: timeline.date)),
                    caption: "あと\(HUDFormat.duration(p.remainingTime))・\(HUDFormat.distance(p.remainingDistance))"
                )
            }
        } else if model.navigation.phase == .arrived {
            MetricView(ctx: ctx, icon: "flag.checkered", value: "到着", caption: model.navigation.activeRoute?.destinationName)
        } else {
            MetricView(ctx: ctx, icon: "flag", value: "--:--", caption: "ナビ未設定")
        }
    }
}

struct NextTurnWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let nav = model.navigation
        if nav.phase == .arrived {
            MetricView(ctx: ctx, icon: "flag.checkered", value: "到着", caption: nav.activeRoute?.destinationName, valueColor: ctx.accent)
        } else if let step = nav.nextStep, let distance = nav.progress?.distanceToNextManeuver {
            let near = distance < 30
            MetricView(
                ctx: ctx,
                icon: step.maneuver.systemImage,
                value: HUDFormat.distance(distance),
                caption: ctx.config.compact ? nil : (step.roadName.map { "\(step.maneuver.spokenName)・\($0)" } ?? step.instruction),
                valueColor: near ? ctx.warning : nil
            )
        } else if nav.isGuiding {
            MetricView(ctx: ctx, icon: "location", value: "--", caption: "現在地を待っています")
        } else {
            MetricView(ctx: ctx, icon: "arrow.triangle.turn.up.right.diamond", value: "--", caption: "目的地未設定")
        }
    }
}

struct NotificationsWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        if let latest = model.alerts.history.first {
            MetricView(ctx: ctx, icon: "bell", value: latest.title, caption: latest.message.isEmpty ? HUDFormat.clock(latest.createdAt) : latest.message)
        } else {
            MetricView(ctx: ctx, icon: "bell.slash", value: "通知なし")
        }
    }
}

struct GPSStatusWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let loc = model.location
        if !loc.authorization.isAuthorized && !loc.isSimulating {
            MetricView(ctx: ctx, icon: "location.slash", value: "許可なし", valueColor: ctx.warning)
        } else if let s = loc.lastSample {
            let good = s.horizontalAccuracy >= 0 && s.horizontalAccuracy <= 15
            MetricView(
                ctx: ctx,
                icon: loc.isSimulating ? "location.slash" : "location.fill",
                value: s.horizontalAccuracy >= 0 ? "±\(Int(s.horizontalAccuracy.rounded()))m" : "--",
                caption: loc.isSimulating ? "シミュレーション" : (good ? "GPS 良好" : "精度低"),
                valueColor: good ? nil : ctx.warning
            )
        } else {
            MetricView(ctx: ctx, icon: "location", value: "--", caption: "測位中")
        }
    }
}

struct SensorsWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let m = model.motion
        let t = ctx.typography
        VStack(alignment: .leading, spacing: 1) {
            row("傾き", m.attitude.map { String(format: "%+.0f° / %+.0f°", $0.pitch, $0.roll) } ?? "--")
            row("向き", m.attitude.map { String(format: "%.0f°", $0.yaw) } ?? "--")
            row("加速度", String(format: "%.2f G", m.userAcceleration))
            row("状態", model.movement.displayName)
        }
        .font(t.font(0.13, weight: .medium))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(ctx.secondary)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(ctx.text).monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

struct AssistantWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let input = model.speechInput
        if input.isListening {
            MetricView(ctx: ctx, icon: "waveform", value: input.transcript.isEmpty ? "聞き取り中…" : input.transcript, valueColor: ctx.accent)
        } else if model.assistant.isThinking {
            MetricView(ctx: ctx, icon: "ellipsis", value: "考え中…")
        } else if let r = model.assistant.lastResponse {
            Text(r)
                .font(ctx.typography.font(0.2, weight: .medium))
                .foregroundStyle(ctx.text)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            MetricView(ctx: ctx, icon: "mic", value: "話しかけてください", caption: "例：「黒背景にして」")
        }
    }
}

struct DetectionsWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let v = model.vision
        if !model.detectionActive {
            MetricView(ctx: ctx, icon: "viewfinder", value: "認識オフ", caption: "ビジョン画面でオン")
        } else if model.background != .camera {
            MetricView(ctx: ctx, icon: "viewfinder", value: "--", caption: "カメラ背景で動作")
        } else {
            let counts = Dictionary(grouping: v.detections, by: \.label).map { "\($0.key.displayName)\($0.value.count)" }.sorted().joined(separator: " ")
            let level = v.highestHazard
            MetricView(
                ctx: ctx,
                icon: level >= .medium ? "exclamationmark.triangle.fill" : "viewfinder",
                value: counts.isEmpty ? "なし" : counts,
                caption: level > .none ? "危険度：\(level.displayName)（実験）" : "物体認識（実験）",
                valueColor: level >= .high ? ctx.danger : (level >= .medium ? ctx.warning : nil)
            )
        }
    }
}

struct CustomTextWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let template = ctx.config.text.isEmpty ? "テキスト" : ctx.config.text
        if TemplateRenderer.usesTokens(template) {
            // {time} などを含む場合は 1 秒ごとに更新
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(TemplateRenderer.render(template, values: model.templateValues(now: context.date)))
            }
        } else {
            label(template)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(ctx.typography.primary)
            .foregroundStyle(ctx.text)
            .lineLimit(2)
            .minimumScaleFactor(0.3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// 心拍数（Bluetooth の心拍計）
struct HeartRateWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let hr = model.heartRate
        if let bpm = hr.bpm, hr.isFresh {
            let zone = HeartRateParser.zone(bpm: bpm)
            MetricView(
                ctx: ctx,
                icon: ctx.config.compact ? nil : "heart.fill",
                value: "\(bpm)",
                unit: "bpm",
                caption: "ゾーン\(zone.index)・\(zone.name)",
                valueColor: zone.index >= 5 ? ctx.danger : zone.index >= 4 ? ctx.warning : nil
            )
        } else {
            MetricView(ctx: ctx, icon: "heart", value: "--", unit: "bpm", caption: status(hr))
        }
    }

    private func status(_ hr: HeartRateService) -> String {
        if !model.settings.bluetooth.heartRateEnabled { return "設定で心拍計を ON" }
        return hr.state.displayName
    }
}

/// 水平器（端末の傾き）
struct HorizonWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let a = model.motion.attitude
        let roll = a?.roll ?? 0
        let pitch = a?.pitch ?? 0
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let level = abs(roll) < 2 && abs(pitch) < 2
            ZStack {
                // 固定の目盛り
                Path { p in
                    p.move(to: CGPoint(x: w * 0.1, y: h / 2))
                    p.addLine(to: CGPoint(x: w * 0.35, y: h / 2))
                    p.move(to: CGPoint(x: w * 0.65, y: h / 2))
                    p.addLine(to: CGPoint(x: w * 0.9, y: h / 2))
                }
                .stroke(ctx.secondary, lineWidth: 2)
                // 傾きに合わせて回る水平線
                Capsule()
                    .fill(level ? ctx.accent : ctx.text)
                    .frame(width: w * 0.7, height: max(3, h * 0.05))
                    .rotationEffect(.degrees(-roll))
                    .offset(y: CGFloat(pitch / 90) * h / 2)
                Text(a == nil ? "--" : String(format: "%+.0f°", roll))
                    .font(ctx.typography.font(0.2, weight: .semibold))
                    .foregroundStyle(ctx.secondary)
                    .monospacedDigit()
                    .position(x: w / 2, y: h * 0.88)
            }
        }
        .animation(.linear(duration: 0.1), value: roll)
    }
}

/// 数時間先までの天気
struct HourlyForecastWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let now = Date()
        let hours = (model.weather.snapshot?.hourly ?? []).filter { $0.time > now.addingTimeInterval(-1800) }.prefix(ctx.config.compact ? 4 : 6)
        let t = ctx.typography
        if hours.isEmpty {
            MetricView(ctx: ctx, icon: "clock.badge.questionmark", value: "--", caption: "1時間ごとの予報")
        } else {
            HStack(spacing: t.size(0.06)) {
                ForEach(Array(hours), id: \.time) { h in
                    VStack(spacing: 1) {
                        Text(Calendar.current.component(.hour, from: h.time).description + "時")
                            .font(t.font(0.15, weight: .medium))
                            .foregroundStyle(ctx.secondary)
                        Image(systemName: h.symbolName)
                            .font(.system(size: t.size(0.24)))
                            .foregroundStyle(ctx.accent)
                        Text(h.temperature.map { "\(Int($0.rounded()))°" } ?? "--")
                            .font(t.font(0.18, weight: .semibold))
                            .foregroundStyle(ctx.text)
                        Text(h.precipitationProbability.map { "\(Int($0))%" } ?? "")
                            .font(t.font(0.13, weight: .medium))
                            .foregroundStyle((h.precipitationProbability ?? 0) >= 50 ? ctx.warning : ctx.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 近くの施設（直近に検索した結果）
struct NearbyPlacesWidget: View {
    @Environment(AppModel.self) private var model
    let ctx: WidgetContext
    var body: some View {
        let t = ctx.typography
        let places = Array(model.nearbyResults.prefix(3))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: model.nearbyCategory?.systemImage ?? "mappin.and.ellipse")
                    .foregroundStyle(ctx.accent)
                Text(model.nearbyCategory.map { "近くの\($0.displayName)" } ?? "近くの施設")
                    .foregroundStyle(ctx.secondary)
            }
            .font(t.font(0.15, weight: .semibold))
            if places.isEmpty {
                Text("「近くのカフェ」などと話しかけてください")
                    .font(t.font(0.14, weight: .medium))
                    .foregroundStyle(ctx.secondary)
            }
            ForEach(places) { p in
                HStack {
                    Text(p.name).foregroundStyle(ctx.text)
                    Spacer(minLength: 4)
                    if let d = currentDistance(p) {
                        Text(HUDFormat.distance(d)).foregroundStyle(ctx.secondary).monospacedDigit()
                    }
                }
                .font(t.font(0.17, weight: .medium))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func currentDistance(_ p: PlaceResult) -> Double? {
        if let here = model.location.lastSample?.coordinate { return Geo.distance(here, p.coordinate) }
        return p.distance
    }
}
