import SwiftUI
import UniformTypeIdentifiers

/// 共有シート（書き出したファイルを「ファイル」アプリ・iCloud Drive などに保存する）
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// HUD タブ：プレビュー＋編集
struct HUDEditorScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showsCanvasSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HUDStatusBar()
                    EditorCanvas()
                    EditorToolbar()
                    if let id = model.selectedPanelIDs.first, model.selectedPanelIDs.count == 1, model.layout.panel(id: id) != nil {
                        PanelInspector(panelID: id)
                    } else {
                        LayoutOverview()
                    }
                }
                .padding()
                .padding(.bottom, 90)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle("HUD")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { PresetManagerView() } label: { Label("プリセット", systemImage: "square.stack") }
                    NavigationLink { ThemeManagerView() } label: { Label("テーマ", systemImage: "paintpalette") }
                }
            }
        }
    }
}

/// プリセット・テーマ・背景の切り替え
struct HUDStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(model.presets) { preset in
                        Button {
                            model.applyPreset(preset.id)
                        } label: {
                            SelectablePill(title: preset.name, systemImage: preset.symbol, isSelected: preset.id == model.activePresetID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Picker("背景", selection: Binding(get: { model.background }, set: { model.background = $0 })) {
                    ForEach(BackgroundMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                Spacer()
                if model.display.mode != .independent {
                    Button {
                        model.isHUDPresented = true
                    } label: {
                        Label("全画面", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.primaryCompact)
                } else {
                    StatusChip(text: "グラスに表示中", systemImage: "eyeglasses", color: UIStyle.success)
                }
            }
            Menu {
                ForEach(model.allThemes) { theme in
                    Button {
                        model.applyTheme(model.themeRef(theme))
                    } label: {
                        if model.activeTheme.id == theme.id { Label(theme.name, systemImage: "checkmark") } else { Text(theme.name) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette.fill")
                    Text("テーマ：\(model.activeTheme.name)").lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(UIStyle.fieldBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(UIStyle.cardStroke, lineWidth: 1))
            }
        }
    }
}

/// 編集用プレビュー（グラスの画面比率で表示）
struct EditorCanvas: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let size = model.display.externalScreenSize ?? CGSize(width: 1920, height: 1080)
        let aspect = size.width / max(1, size.height)
        HUDRootView(surface: .editorPreview)
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UIStyle.accent.opacity(0.35), lineWidth: 1))
            .shadow(color: UIStyle.accent.opacity(0.15), radius: 16, y: 4)
            .overlay(alignment: .bottomTrailing) {
                Text("グラスの画面（\(Int(size.width))×\(Int(size.height))）")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(6)
                    .allowsHitTesting(false)
            }
    }
}

struct EditorToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 12) {
            Menu {
                ForEach(WidgetKind.allCases, id: \.self) { kind in
                    Button { model.addWidget(kind) } label: { Label(kind.displayName, systemImage: kind.systemImage) }
                }
            } label: {
                Label("追加", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.borderedProminent)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .accessibilityLabel("元に戻す")

            Button { model.autoArrange() } label: { Label("整列", systemImage: "rectangle.3.group") }

            Menu {
                ForEach(AlignmentEdge.allCases, id: \.self) { edge in
                    Button(edge.displayName) { model.align(edge) }
                }
            } label: {
                Label("揃える", systemImage: "align.horizontal.left")
            }
            .disabled(model.selectedPanelIDs.count < 2)

            Toggle(isOn: Binding(get: { model.layout.canvas.snapToGrid }, set: { v in model.updateCanvas { $0.snapToGrid = v } })) {
                Image(systemName: "grid")
            }
            .toggleStyle(.button)
            .accessibilityLabel("グリッドに吸着")

            Toggle(isOn: Binding(get: { model.layout.canvas.preventOverlap }, set: { v in model.updateCanvas { $0.preventOverlap = v } })) {
                Image(systemName: "square.on.square.dashed")
            }
            .toggleStyle(.button)
            .accessibilityLabel("重なりを防ぐ")
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 2)
        }
    }
}

/// 何も選択していないとき：パネル一覧と視界のチェック
struct LayoutOverview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let panels = model.layout.panelsInDrawingOrder
        let coverage = LayoutEngine.coverageRatio(panels)
        let blocking = LayoutEngine.panelsBlockingCenter(panels)
        VStack(alignment: .leading, spacing: 12) {
            Card(title: "視界のチェック", systemImage: "eye") {
                Text("パネルが画面を覆う割合：\(Int((coverage * 100).rounded()))%")
                if coverage > 0.2 {
                    NoticeBanner(text: "歩行中は画面の15〜20%以下を目安にしてください。")
                }
                if !blocking.isEmpty {
                    NoticeBanner(text: "中央（前方の視界）にあるパネル：\(blocking.map(\.widget.displayName).joined(separator: "、"))")
                }
                ForEach(model.activeTheme.visibilityWarnings, id: \.self) { NoticeBanner(text: $0) }
                Text("パネルをタップで選択、ドラッグで移動、右下の丸でサイズ変更、長押しで複数選択。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Card(title: "パネル（\(panels.count)）", systemImage: "square.grid.2x2") {
                ForEach(panels) { panel in
                    HStack {
                        Image(systemName: panel.widget.systemImage).frame(width: 24)
                        Text(panel.widget.displayName)
                        Spacer()
                        Button {
                            model.updatePanel(panel.id) { $0.isVisible.toggle() }
                        } label: {
                            Image(systemName: panel.isVisible ? "eye" : "eye.slash")
                        }
                        .buttonStyle(.borderless)
                        Button {
                            model.selectedPanelIDs = [panel.id]
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if panels.isEmpty { Text("「追加」からウィジェットを置いてください。").foregroundStyle(.secondary) }
            }
            NavigationLink {
                CanvasSettingsView()
            } label: {
                Label("表示位置・拡大率・最小文字サイズ", systemImage: "rectangle.dashed")
            }
        }
    }
}

/// 選択したパネルの設定
struct PanelInspector: View {
    @Environment(AppModel.self) private var model
    let panelID: UUID
    @State private var showsStyle = false

    private func binding<T>(_ keyPath: WritableKeyPath<HUDPanel, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { model.layout.panel(id: panelID)?[keyPath: keyPath] ?? fallback },
            set: { value in model.updatePanel(panelID) { $0[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        if let panel = model.layout.panel(id: panelID) {
            let base = model.activeTheme.style
            VStack(alignment: .leading, spacing: 12) {
                Card(title: panel.widget.displayName, systemImage: panel.widget.systemImage) {
                    Toggle("表示", isOn: binding(\.isVisible, true))
                    LabeledSlider(title: "透明度", value: binding(\.opacity, 1), range: 0.2...1, format: { "\(Int($0 * 100))%" })
                    HStack {
                        Button { model.bringToFront(panelID) } label: { Label("前面へ", systemImage: "square.3.layers.3d.top.filled") }
                        Button { model.sendToBack(panelID) } label: { Label("背面へ", systemImage: "square.3.layers.3d.bottom.filled") }
                        Spacer()
                        Button { model.duplicatePanel(panelID) } label: { Image(systemName: "plus.square.on.square") }
                            .accessibilityLabel("複製")
                        Button(role: .destructive) { model.deletePanels([panelID]) } label: { Image(systemName: "trash") }
                            .accessibilityLabel("削除")
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                }
                Card(title: "位置・大きさ", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                    LabeledSlider(title: "左右", value: binding(\.frame.x, 0), range: 0...0.98, format: { "\(Int($0 * 100))%" })
                    LabeledSlider(title: "上下", value: binding(\.frame.y, 0), range: 0...0.98, format: { "\(Int($0 * 100))%" })
                    LabeledSlider(title: "幅", value: binding(\.frame.width, 0.2), range: 0.04...1, format: { "\(Int($0 * 100))%" })
                    LabeledSlider(title: "高さ", value: binding(\.frame.height, 0.1), range: 0.04...1, format: { "\(Int($0 * 100))%" })
                }
                WidgetConfigEditor(panelID: panelID, kind: panel.widget)
                Card(title: "見た目（このパネルだけ）", systemImage: "paintbrush") {
                    DisclosureGroup("文字・色・枠・発光", isExpanded: $showsStyle) {
                        StyleOverrideEditor(style: binding(\.style, PanelStyleOverride()), base: base)
                    }
                    if !panel.style.isEmpty {
                        Button("テーマの見た目に戻す") { model.updatePanel(panelID) { $0.style = PanelStyleOverride() } }
                    }
                }
            }
        }
    }
}

struct WidgetConfigEditor: View {
    @Environment(AppModel.self) private var model
    let panelID: UUID
    let kind: WidgetKind

    private func binding<T>(_ keyPath: WritableKeyPath<WidgetConfig, T>, _ fallback: T) -> Binding<T> {
        Binding(
            get: { model.layout.panel(id: panelID)?.config[keyPath: keyPath] ?? fallback },
            set: { value in model.updatePanel(panelID) { $0.config[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        Card(title: "ウィジェットの設定", systemImage: "gearshape") {
            Toggle("説明文を表示", isOn: binding(\.showsLabel, true))
            Toggle("コンパクト表示", isOn: binding(\.compact, false))
            switch kind {
            case .clock:
                Toggle("秒を表示", isOn: binding(\.showsSeconds, false))
                Toggle("24時間表示", isOn: binding(\.uses24Hour, true))
            case .speed:
                Picker("単位", selection: binding(\.speedUnit, .kilometersPerHour)) {
                    ForEach(SpeedUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
            case .miniMap:
                LabeledSlider(title: "表示範囲", value: binding(\.mapSpanMeters, 400), range: 100...3000, format: { HUDFormat.distance($0) })
            case .customText:
                TextField("表示するテキスト", text: binding(\.text, ""))
                    .textFieldStyle(.roundedBorder)
                Text("使える記号：" + TemplateRenderer.tokens.map { "\($0.token)＝\($0.description)" }.joined(separator: "、"))
                    .font(.caption2).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }
}

/// スタイルの個別上書き
struct StyleOverrideEditor: View {
    @Binding var style: PanelStyleOverride
    let base: PanelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OptionalTokenColorPicker(title: "文字色", token: $style.textColor, fallback: base.textColor)
            OptionalTokenColorPicker(title: "補助文字色", token: $style.secondaryTextColor, fallback: base.secondaryTextColor)
            OptionalTokenColorPicker(title: "強調色", token: $style.accentColor, fallback: base.accentColor)
            OptionalTokenColorPicker(title: "背景色", token: $style.backgroundColor, fallback: base.backgroundColor)
            OptionalTokenColorPicker(title: "枠線の色", token: $style.borderColor, fallback: base.borderColor)
            OptionalTokenColorPicker(title: "発光の色", token: $style.glowColor, fallback: base.glowColor)
            Picker("フォント", selection: Binding(get: { style.fontDesign ?? base.fontDesign }, set: { style.fontDesign = $0 })) {
                ForEach(HUDFontDesign.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("文字の太さ", selection: Binding(get: { style.fontWeight ?? base.fontWeight }, set: { style.fontWeight = $0 })) {
                ForEach(HUDFontWeight.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("アニメーション", selection: Binding(get: { style.animation ?? base.animation }, set: { style.animation = $0 })) {
                ForEach(HUDAnimationStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            LabeledSlider(title: "文字サイズ", value: Binding(get: { style.fontScale ?? base.fontScale }, set: { style.fontScale = $0 }), range: 0.5...2, format: { "×\(String(format: "%.2f", $0))" })
            LabeledSlider(title: "背景の不透明度", value: Binding(get: { style.backgroundOpacity ?? base.backgroundOpacity }, set: { style.backgroundOpacity = $0 }), range: 0...1, format: { "\(Int($0 * 100))%" })
            LabeledSlider(title: "枠線", value: Binding(get: { style.borderWidth ?? base.borderWidth }, set: { style.borderWidth = $0 }), range: 0...6, format: { String(format: "%.1f", $0) })
            LabeledSlider(title: "角丸", value: Binding(get: { style.cornerRadius ?? base.cornerRadius }, set: { style.cornerRadius = $0 }), range: 0...40, format: { "\(Int($0))" })
            LabeledSlider(title: "影", value: Binding(get: { style.shadowRadius ?? base.shadowRadius }, set: { style.shadowRadius = $0 }), range: 0...20, format: { "\(Int($0))" })
            LabeledSlider(title: "発光", value: Binding(get: { style.glowRadius ?? base.glowRadius }, set: { style.glowRadius = $0 }), range: 0...24, format: { "\(Int($0))" })
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

/// キャンバス全体の調整（グラスの見え方）
struct CanvasSettingsView: View {
    @Environment(AppModel.self) private var model

    private func binding(_ keyPath: WritableKeyPath<CanvasSettings, Double>) -> Binding<Double> {
        Binding(get: { model.layout.canvas[keyPath: keyPath] }, set: { v in model.updateCanvas { $0[keyPath: keyPath] = v } })
    }

    var body: some View {
        Form {
            Section {
                LabeledSlider(title: "左右の位置", value: binding(\.offsetX), range: -0.3...0.3, format: { "\(Int($0 * 100))%" })
                LabeledSlider(title: "上下の位置", value: binding(\.offsetY), range: -0.3...0.3, format: { "\(Int($0 * 100))%" })
                LabeledSlider(title: "全体の大きさ", value: binding(\.scale), range: 0.5...1.2, format: { "\(Int($0 * 100))%" })
                LabeledSlider(title: "画面端の余白", value: binding(\.safeMargin), range: 0...0.2, format: { "\(Int($0 * 100))%" })
                Button("位置と大きさを元に戻す") {
                    model.updateCanvas { $0.offsetX = 0; $0.offsetY = 0; $0.scale = 1 }
                }
            } header: {
                Text("グラスでの表示位置")
            } footer: {
                Text("グラスの視野の端が見えにくい場合は、全体を小さくしたり位置をずらしたりしてください。この設定はプリセットごとに保存されます。")
            }
            Section {
                LabeledSlider(title: "最小文字サイズ（1080p換算）", value: binding(\.minimumFontPixels), range: 10...60, format: { "\(Int($0))px" })
            } footer: {
                Text("設定→詳細→視認性テストで、グラス越しに読める最小サイズを確かめてから設定してください。")
            }
            Section("グリッド") {
                Stepper("分割数：\(model.layout.canvas.gridDivisions)", value: Binding(get: { model.layout.canvas.gridDivisions }, set: { v in model.updateCanvas { $0.gridDivisions = v } }), in: 8...96, step: 8)
            }
        }
        .navigationTitle("表示位置・大きさ")
    }
}
