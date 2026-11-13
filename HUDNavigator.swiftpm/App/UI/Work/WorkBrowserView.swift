import SwiftUI

/// ワーク → ブラウザ。
/// グラス（または HUD の全画面）にページを出している間は、この画面がリモコン（トラックパッド・文字入力）になる。
/// どこにも出していないときは、この画面でそのままページを見られる。
struct BrowserSection: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @FocusState private var isEditingAddress: Bool

    var body: some View {
        let browser = model.web
        let remote = browser.activeHost == .glasses || browser.activeHost == .deviceHUD
        VStack(alignment: .leading, spacing: 14) {
            addressBar(browser)
            BookmarkRow(address: $address)
            if remote {
                StatusChip(text: browser.activeHost == .glasses ? "グラスに表示中（下で操作）" : "HUD の全画面に表示中", systemImage: "eyeglasses", color: UIStyle.success, showsDot: true)
                if browser.activeHost == .glasses { WebRemoteCard() }
            } else {
                livePage(browser)
            }
            HStack(spacing: 8) {
                HUDWidgetChip(kind: .webPage)
                Button {
                    model.applyPreset(key: "browser")
                } label: {
                    Label("ブラウザのプリセットにする", systemImage: "globe").font(.footnote.weight(.semibold))
                }
            }
            BrowserSettingsCard()
        }
        .onAppear {
            browser.register(.workScreen)
            model.openBrowserIfNeeded()
            address = WebAddress.display(browser.urlString)
        }
        .onDisappear { browser.unregister(.workScreen) }
        .onChange(of: browser.urlString) { _, new in
            if !isEditingAddress { address = WebAddress.display(new) }
        }
    }

    private func addressBar(_ browser: WebBrowserModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: browser.isLoading ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                        .foregroundStyle(UIStyle.accent)
                        .symbolEffect(.pulse, isActive: browser.isLoading)
                    TextField("アドレスか、検索する言葉", text: $address)
                        .focused($isEditingAddress)
                        .keyboardType(.webSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(go)
                    if !address.isEmpty && isEditingAddress {
                        Button {
                            address = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fieldSurface(radius: 22)
                RoundIconButton(systemImage: "arrow.right", label: "開く", prominent: true, size: 44, action: go)
            }
            HStack(spacing: 10) {
                RoundIconButton(systemImage: "chevron.left", label: "戻る", size: 38) { browser.goBack() }
                    .disabled(!browser.canGoBack)
                    .opacity(browser.canGoBack ? 1 : 0.4)
                RoundIconButton(systemImage: "chevron.right", label: "進む", size: 38) { browser.goForward() }
                    .disabled(!browser.canGoForward)
                    .opacity(browser.canGoForward ? 1 : 0.4)
                RoundIconButton(systemImage: browser.isLoading ? "xmark" : "arrow.clockwise", label: browser.isLoading ? "中止" : "読み込み直す", size: 38) {
                    if browser.isLoading { browser.stopLoading() } else { browser.reload() }
                }
                Text(browser.title.isEmpty ? " " : browser.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if browser.isLoading {
                ProgressView(value: browser.progress).tint(UIStyle.accent)
            }
            if let error = browser.lastError {
                Text(error).font(.caption).foregroundStyle(UIStyle.warning)
            }
        }
    }

    private func livePage(_ browser: WebBrowserModel) -> some View {
        WebHostView(browser: browser, host: .workScreen, isActive: browser.activeHost == .workScreen, allowsTouch: true)
            .frame(height: 440)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(UIStyle.accent.opacity(0.35), lineWidth: 1))
    }

    private func go() {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.web.open(address)
        isEditingAddress = false
    }
}

/// しおり（よく開くページ）
struct BookmarkRow: View {
    @Environment(AppModel.self) private var model
    @Binding var address: String

    var body: some View {
        let work = model.workspace
        let browser = model.web
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(work.data.bookmarks) { bookmark in
                    Button {
                        browser.open(bookmark.url)
                    } label: {
                        SelectablePill(title: bookmark.title, systemImage: "bookmark.fill", isSelected: false)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("ホームにする", systemImage: "house") { work.data.homeURL = bookmark.url }
                        Button("しおりを消す", systemImage: "trash", role: .destructive) {
                            work.data.bookmarks.removeAll { $0.id == bookmark.id }
                        }
                    }
                }
                if !browser.urlString.isEmpty, !work.data.bookmarks.contains(where: { $0.url == browser.urlString }) {
                    Button {
                        let title = browser.title.isEmpty ? WebAddress.host(browser.urlString) : String(browser.title.prefix(16))
                        work.data.bookmarks.append(WebBookmark(title: title, url: browser.urlString))
                        model.showToast("しおりに追加しました")
                    } label: {
                        SelectablePill(title: "このページを追加", systemImage: "plus", isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}

/// グラスに映したページを端末から操作する（トラックパッド・スクロール・文字入力）
struct WebRemoteCard: View {
    @Environment(AppModel.self) private var model
    @State private var lastDrag: CGSize = .zero
    @State private var dragDistance: CGFloat = 0
    @State private var lastScroll: CGFloat = 0
    @State private var text = ""
    @State private var clicks = 0
    @FocusState private var isTyping: Bool

    var body: some View {
        let browser = model.web
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                trackpad(browser)
                scrollStrip(browser)
            }
            .frame(height: 230)

            HStack(spacing: 10) {
                Button {
                    browser.click()
                    clicks += 1
                } label: {
                    Label("押す", systemImage: "cursorarrow.click").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                RoundIconButton(systemImage: "arrow.up", label: "上へ", size: 46) { browser.scroll(byScreens: -0.8) }
                RoundIconButton(systemImage: "arrow.down", label: "下へ", size: 46) { browser.scroll(byScreens: 0.8) }
                RoundIconButton(systemImage: "arrow.up.to.line", label: "いちばん上へ", size: 46) { browser.scrollToTop() }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(browser.isTextFieldFocused ? "入力する文字" : "先に入力欄を押してから、文字を送る", text: $text)
                        .focused($isTyping)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .onSubmit { send(andEnter: true) }
                        .fieldSurface()
                    RoundIconButton(systemImage: "paperplane.fill", label: "文字を送る", prominent: true, size: 44) { send(andEnter: false) }
                }
                HStack(spacing: 8) {
                    Button { browser.deleteBackward() } label: { Label("1 文字消す", systemImage: "delete.left") }
                        .buttonStyle(.secondaryCompact)
                    Button { browser.pressEnter() } label: { Label("Enter", systemImage: "return") }
                        .buttonStyle(.secondaryCompact)
                    Spacer()
                }
                Text("四角の中をなぞるとグラスのカーソルが動き、軽くたたくと押せます。右の帯をなぞるとスクロールします。キーボードの Enter で「送って Enter」になります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .cardSurface()
        .sensoryFeedback(.impact(weight: .light), trigger: clicks)
    }

    private func trackpad(_ browser: WebBrowserModel) -> some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(UIStyle.fieldBackground)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(UIStyle.accent.opacity(0.35), lineWidth: 1)
                // カーソルの今の位置（ページ全体に対する位置）
                Circle()
                    .fill(UIStyle.accent.opacity(0.9))
                    .frame(width: 12, height: 12)
                    .shadow(color: UIStyle.accent.opacity(0.8), radius: 6)
                    .position(x: browser.cursor.x * geo.size.width, y: browser.cursor.y * geo.size.height)
                Label("トラックパッド", systemImage: "hand.point.up.left")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.translation.width - lastDrag.width
                        let dy = value.translation.height - lastDrag.height
                        lastDrag = value.translation
                        dragDistance += abs(dx) + abs(dy)
                        // なぞった量をそのままカーソルの動きにする（1.3 倍速）
                        browser.moveCursor(dx: dx / max(1, geo.size.width) * 1.3, dy: dy / max(1, geo.size.height) * 1.3)
                    }
                    .onEnded { _ in
                        // ほとんど動かさずに離したら「押す」
                        if dragDistance < 8 {
                            browser.click()
                            clicks += 1
                        }
                        lastDrag = .zero
                        dragDistance = 0
                    }
            )
        }
    }

    private func scrollStrip(_ browser: WebBrowserModel) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(UIStyle.fieldBackground)
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(UIStyle.cardStroke, lineWidth: 1)
            VStack {
                Image(systemName: "chevron.up")
                Spacer()
                Image(systemName: "arrow.up.and.down")
                Spacer()
                Image(systemName: "chevron.down")
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 12)
        }
        .frame(width: 58)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let dy = value.translation.height - lastScroll
                    lastScroll = value.translation.height
                    // 指を上に動かすとページが下へ進む（スマホと同じ向き）
                    browser.scroll(dx: 0, dy: Double(-dy) * 3)
                }
                .onEnded { _ in lastScroll = 0 }
        )
        .accessibilityLabel("スクロール")
    }

    private func send(andEnter: Bool) {
        let browser = model.web
        if !text.isEmpty {
            browser.insertText(text)
            text = ""
        }
        if andEnter { browser.pressEnter() }
        isTyping = true
    }
}

struct BrowserSettingsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let browser = model.web
        Card(title: "表示", systemImage: "textformat.size") {
            Toggle("明るいページを暗くする（グラス向け）", isOn: Binding(get: { browser.darkMode }, set: { model.setWeb(darkMode: $0) }))
            Toggle("パソコン用のページを表示", isOn: Binding(get: { browser.desktopMode }, set: { model.setWeb(desktopMode: $0) }))
            HStack {
                Text("大きさ")
                Spacer()
                RoundIconButton(systemImage: "minus", label: "小さく", size: 36) { model.setWeb(zoom: browser.zoom - 0.1) }
                Text("\(Int((browser.zoom * 100).rounded()))%").monospacedDigit().frame(width: 56)
                RoundIconButton(systemImage: "plus", label: "大きく", size: 36) { model.setWeb(zoom: browser.zoom + 0.1) }
            }
            Text("グラスでは黒が透明、白はまぶしく見えるので、白いページは色を反転して暗くします。ログインが必要なページもこのアプリの中だけで開き、閲覧した内容はどこにも送りません。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
