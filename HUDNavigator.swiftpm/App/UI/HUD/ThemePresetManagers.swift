import SwiftUI
import UniformTypeIdentifiers

struct ThemeManagerView: View {
    @Environment(AppModel.self) private var model
    @State private var share: ShareItem?
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        List {
            Section("組み込みテーマ") {
                ForEach(BuiltInContent.themes) { theme in
                    ThemeRow(theme: theme)
                }
            }
            Section {
                ForEach(model.userThemes) { theme in
                    NavigationLink {
                        ThemeEditorView(themeID: theme.id)
                    } label: {
                        ThemeRow(theme: theme)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { model.deleteTheme(model.userThemes[i].id) }
                }
                if model.userThemes.isEmpty {
                    Text("組み込みテーマを「複製」すると、自分用に編集できます。").foregroundStyle(.secondary)
                }
            } header: {
                Text("自分のテーマ")
            }
            Section {
                Button {
                    if let url = model.exportThemesFile(model.userThemes) { share = ShareItem(url: url) }
                } label: {
                    Label("自分のテーマを書き出す", systemImage: "square.and.arrow.up")
                }
                .disabled(model.userThemes.isEmpty)
                Button {
                    importing = true
                } label: {
                    Label("テーマを読み込む", systemImage: "square.and.arrow.down")
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("書き出したファイルは iCloud Drive に保存すれば、iPad と iPhone で共有できます。")
            }
        }
        .navigationTitle("テーマ")
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { message = model.importFile(url, strategy: .merge) }
        }
    }
}

struct ThemeRow: View {
    @Environment(AppModel.self) private var model
    let theme: Theme

    var body: some View {
        HStack {
            ThemeSwatch(theme: theme)
            VStack(alignment: .leading) {
                Text(theme.name)
                if !theme.visibilityWarnings.isEmpty {
                    Text("グラスで見えにくい可能性あり").font(.caption).foregroundStyle(UIStyle.warning)
                }
            }
            Spacer()
            if model.activeTheme.id == theme.id {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(UIStyle.accent)
            }
            Menu {
                Button("このテーマを使う") { model.applyTheme(model.themeRef(theme)) }
                Button("複製して編集") { model.duplicateTheme(theme) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct ThemeSwatch: View {
    let theme: Theme
    var body: some View {
        let s = theme.style
        Text("12:34")
            .font(.system(size: 13, weight: s.fontWeight.swiftUI, design: s.fontDesign.swiftUI))
            .foregroundStyle(Color(s.textColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black)
            .background(Color(s.backgroundColor).opacity(s.backgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius: min(10, s.cornerRadius)))
            .overlay(RoundedRectangle(cornerRadius: min(10, s.cornerRadius)).stroke(Color(s.borderColor), lineWidth: max(1, s.borderWidth)))
            .shadow(color: Color(s.glowColor).opacity(s.glowRadius > 0 ? 0.8 : 0), radius: s.glowRadius / 2)
    }
}

struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model
    let themeID: UUID

    private var theme: Binding<Theme> {
        Binding(
            get: { model.userThemes.first { $0.id == themeID } ?? BuiltInContent.themes[0] },
            set: { model.updateTheme($0) }
        )
    }

    var body: some View {
        let t = theme
        Form {
            Section("名前") {
                TextField("テーマ名", text: t.name)
            }
            Section("色") {
                TokenColorPicker(title: "文字色", token: t.style.textColor)
                TokenColorPicker(title: "補助文字色", token: t.style.secondaryTextColor)
                TokenColorPicker(title: "強調色", token: t.style.accentColor)
                TokenColorPicker(title: "背景色", token: t.style.backgroundColor)
                TokenColorPicker(title: "枠線の色", token: t.style.borderColor)
                TokenColorPicker(title: "発光の色", token: t.style.glowColor)
                TokenColorPicker(title: "注意の色", token: t.warningColor)
                TokenColorPicker(title: "危険の色", token: t.dangerColor)
            }
            Section("文字") {
                Picker("フォント", selection: t.style.fontDesign) {
                    ForEach(HUDFontDesign.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("太さ", selection: t.style.fontWeight) {
                    ForEach(HUDFontWeight.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledSlider(title: "文字サイズ", value: t.style.fontScale, range: 0.5...2, format: { "×\(String(format: "%.2f", $0))" })
            }
            Section("パネル") {
                LabeledSlider(title: "背景の不透明度", value: t.style.backgroundOpacity, range: 0...1, format: { "\(Int($0 * 100))%" })
                LabeledSlider(title: "枠線", value: t.style.borderWidth, range: 0...6, format: { String(format: "%.1f", $0) })
                LabeledSlider(title: "角丸", value: t.style.cornerRadius, range: 0...40, format: { "\(Int($0))" })
                LabeledSlider(title: "影", value: t.style.shadowRadius, range: 0...20, format: { "\(Int($0))" })
                LabeledSlider(title: "発光", value: t.style.glowRadius, range: 0...24, format: { "\(Int($0))" })
                Picker("アニメーション", selection: t.style.animation) {
                    ForEach(HUDAnimationStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section {
                ForEach(t.wrappedValue.visibilityWarnings, id: \.self) { NoticeBanner(text: $0) }
                Text("VITURE では黒は透明に見えます。暗い色・半透明の背景はほとんど見えません。明るい文字色をおすすめします。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("グラスでの見え方")
            }
            Section {
                Button("このテーマを使う") { model.applyTheme(themeID.uuidString) }
            }
        }
        .navigationTitle(t.wrappedValue.name)
    }
}

struct PresetManagerView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var renaming: Preset?
    @State private var renameText = ""
    @State private var share: ShareItem?

    var body: some View {
        List {
            Section {
                ForEach(model.presets) { preset in
                    HStack {
                        Image(systemName: preset.symbol).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text("\(preset.layout.panels.count)パネル・\(model.theme(forRef: preset.themeRef).name)・\(preset.background.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preset.id == model.activePresetID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(UIStyle.accent)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.applyPreset(preset.id) }
                    .swipeActions {
                        if preset.isBuiltIn {
                            Button("初期化") { model.resetPreset(preset.id) }.tint(.orange)
                        } else {
                            Button("削除", role: .destructive) { model.deletePreset(preset.id) }
                        }
                        Button("名前") { renaming = preset; renameText = preset.name }.tint(.blue)
                    }
                }
            } header: {
                Text("プリセット")
            } footer: {
                Text("タップで切り替え。左にスワイプで名前変更・削除（組み込みは初期化）。HUD全画面表示中は左右スワイプで切り替えられます。")
            }
            Section("現在の配置を保存") {
                TextField("新しいプリセット名", text: $newName)
                Button("新しいプリセットとして保存") {
                    model.saveCurrentAsNewPreset(named: newName)
                    newName = ""
                }
            }
            Section {
                Button {
                    if let url = model.exportBundleFile(includeHistory: false) { share = ShareItem(url: url) }
                } label: {
                    Label("設定・プリセットを書き出す", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("読み込みは 設定 → データ・同期 から行えます。")
            }
        }
        .navigationTitle("プリセット")
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .alert("名前を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名前", text: $renameText)
            Button("変更") {
                if let p = renaming { model.renamePreset(p.id, to: renameText) }
                renaming = nil
            }
            Button("キャンセル", role: .cancel) { renaming = nil }
        }
    }
}
