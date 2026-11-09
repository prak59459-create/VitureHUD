import SwiftUI
import UIKit

/// コマンドの結果（読み上げるかどうか）
struct CommandOutcome {
    var message: String
    var speak: Bool = true
    /// 会話画面に小さく表示する補足（AI が実行した操作など）
    var detail: String? = nil
}

extension AppModel {
    // MARK: - コマンド（UI・音声・ショートカット共通）

    @discardableResult
    func perform(_ command: AppCommand) async -> CommandOutcome {
        deviceTest.record("コマンド: \(command.summary)")
        history.recordCommand(command.usageName, viaVoice: commandFromVoice, settings: settings.history)
        commandFromVoice = false
        switch command {
        case .setBackground(let mode):
            background = mode
            return CommandOutcome(message: "背景を\(mode.displayName)にしました。")
        case .toggleBackground:
            background = background.toggled
            return CommandOutcome(message: "背景を\(background.displayName)にしました。")
        case .applyPreset(let key):
            guard let preset = presets.first(where: { $0.key == key || $0.id.uuidString == key }) else {
                return CommandOutcome(message: "そのプリセットは見つかりませんでした。")
            }
            applyPreset(preset.id)
            return CommandOutcome(message: "「\(preset.name)」にしました。")
        case .applyTheme(let key):
            let theme = theme(forRef: key)
            applyTheme(themeRef(theme))
            return CommandOutcome(message: "テーマを「\(theme.name)」にしました。")
        case .showWidget(let kind):
            showWidget(kind)
            return CommandOutcome(message: "\(kind.displayName)を表示しました。")
        case .hideWidget(let kind):
            hideWidget(kind)
            return CommandOutcome(message: "\(kind.displayName)を非表示にしました。")
        case .mapZoom(let direction):
            zoomMaps(direction)
            return CommandOutcome(message: direction == .zoomIn ? "地図を拡大しました。" : "地図を縮小しました。")
        case .setMap3D(let on):
            settings.map.use3D = on
            return CommandOutcome(message: on ? "地図を3D表示にしました。" : "地図を2D表示にしました。")
        case .startNavigation:
            if navigation.isGuiding { return CommandOutcome(message: "すでに案内中です。") }
            if navigation.selectedRoute != nil {
                navigation.start()
                return CommandOutcome(message: "案内を開始します。", speak: false)
            }
            selectedTab = .navigation
            return CommandOutcome(message: "目的地を指定してください。例：「東京駅までナビして」")
        case .stopNavigation:
            guard navigation.isGuiding || navigation.phase == .arrived else { return CommandOutcome(message: "案内は行っていません。") }
            navigation.stop()
            return CommandOutcome(message: "案内を終了しました。")
        case .navigate(let query):
            return await navigate(to: query)
        case .search(let query):
            pendingSearch = query
            selectedTab = .navigation
            return CommandOutcome(message: "「\(query)」を検索します。")
        case .searchNearby(let category):
            return await searchNearby(category)
        case .setVoiceGuidance(let on):
            settings.voice.guidanceEnabled = on
            return CommandOutcome(message: on ? "音声案内をオンにしました。" : "音声案内をオフにしました。", speak: true)
        case .setDetection(let on):
            if on && !settings.detection.hasAcceptedDisclaimer {
                selectedTab = .vision
                showsVisionDisclaimer = true
                return CommandOutcome(message: "物体認識は実験機能です。画面の注意事項を確認してください。")
            }
            settings.detection.enabled = on
            features.objectDetection = on
            return CommandOutcome(message: on ? "物体認識をオンにしました。実験機能のため、検知漏れがあります。" : "物体認識をオフにしました。")
        case .setHazardAlerts(let on):
            if on && !settings.detection.hasAcceptedDisclaimer {
                selectedTab = .vision
                showsVisionDisclaimer = true
                return CommandOutcome(message: "危険検知は実験機能です。画面の注意事項を確認してください。")
            }
            settings.detection.hazardAlertsEnabled = on
            if on { settings.detection.enabled = true }
            features.hazardAlerts = on
            return CommandOutcome(message: on ? "危険検知をオンにしました。安全装置ではありません。" : "危険検知をオフにしました。")
        case .status(let topic):
            return CommandOutcome(message: LocalResponder.respond(to: topic, context: assistantContext()))
        case .startHUD:
            if display.mode == .independent { return CommandOutcome(message: "グラスに HUD を表示しています。") }
            isHUDPresented = true
            return CommandOutcome(message: "HUD を表示します。", speak: false)
        case .stopHUD:
            isHUDPresented = false
            return CommandOutcome(message: "HUD を閉じました。", speak: false)
        case .open(let screen):
            open(screen)
            return CommandOutcome(message: "\(screen.displayName)を開きます。", speak: false)
        case .cameraZoom(let direction):
            let z = settings.camera.zoom * (direction == .zoomIn ? 1.4 : 1 / 1.4)
            settings.camera.zoom = z.clamped(to: 1...4)
            return CommandOutcome(message: "カメラの倍率を\(String(format: "%.1f", settings.camera.zoom))倍にしました。")
        case .cameraExposure(let direction):
            settings.camera.exposureBias = (settings.camera.exposureBias + (direction == .up ? 0.5 : -0.5)).clamped(to: -2...2)
            return CommandOutcome(message: direction == .up ? "カメラを明るくしました。" : "カメラを暗くしました。")
        case .repeatGuidance:
            if let text = navigation.repeatInstruction() {
                speech.speak(text, priority: .normal, force: true)
                return CommandOutcome(message: text, speak: false)
            }
            speech.repeatLast()
            return CommandOutcome(message: "もう一度読み上げます。", speak: false)
        case .autoArrange:
            autoArrange()
            return CommandOutcome(message: "パネルを画面の端に並べました。")
        case .adjustHUDScale(let direction):
            updateCanvas { $0.scale += direction == .up ? 0.05 : -0.05 }
            return CommandOutcome(message: "HUD の大きさを\(HUDFormat.percent(layout.canvas.scale))にしました。")
        case .moveHUD(let direction):
            let step = 0.03
            updateCanvas { c in
                switch direction {
                case .up: c.offsetY -= step
                case .down: c.offsetY += step
                case .left: c.offsetX -= step
                case .right: c.offsetX += step
                }
            }
            return CommandOutcome(message: "HUD を\(direction.displayName)に動かしました。")
        case .adjustTextSize(let direction):
            updateCanvas { $0.textScale += direction == .up ? 0.1 : -0.1 }
            return CommandOutcome(message: "文字の大きさを\(HUDFormat.percent(layout.canvas.textScale))にしました。")
        case .adjustBrightness(let direction):
            settings.display.brightness = (settings.display.brightness + (direction == .up ? 0.1 : -0.1)).clamped(to: 0.2...1)
            return CommandOutcome(message: "HUD の明るさを\(HUDFormat.percent(settings.display.brightness))にしました。")
        case .setNightDim(let on):
            settings.display.nightDimEnabled = on
            return CommandOutcome(message: on ? "夜間は HUD を自動で暗くします。" : "夜間の自動減光をオフにしました。")
        case .setStereo3D(let on):
            settings.display.stereo3D = on
            return CommandOutcome(message: on ? "3D（左右分割）表示にしました。グラスを 3D モードにしてください。" : "3D 表示をオフにしました。")
        case .cyclePreset(let offset):
            cyclePreset(offset >= 0 ? 1 : -1)
            return CommandOutcome(message: "「\(activePreset.name)」にしました。")
        case .nextTheme:
            let themes = allThemes
            let current = themes.firstIndex { themeRef($0) == activePreset.themeRef } ?? 0
            let next = themes[(current + 1) % themes.count]
            applyTheme(themeRef(next))
            return CommandOutcome(message: "テーマを「\(next.name)」にしました。")
        case .connectHeartRate:
            settings.bluetooth.heartRateEnabled = true
            if !layout.contains(widget: .heartRate) { showWidget(.heartRate) }
            heartRate.start()
            if settings.bluetooth.rememberedDeviceID == nil { heartRate.scan() }
            return CommandOutcome(message: "心拍計を探します。心拍計の電源を入れてください。")
        case .syncNow:
            return CommandOutcome(message: await syncNow())
        case .setRecording(let on):
            if on {
                guard settings.history.enabled else {
                    return CommandOutcome(message: "移動履歴の保存がオフです。設定 → 移動履歴 で有効にしてください。")
                }
                if history.isRecording { return CommandOutcome(message: "すでに記録中です。") }
                history.start(settings: settings.history)
                refreshServices()
                return CommandOutcome(message: "移動の記録を開始しました。")
            }
            guard history.isRecording else { return CommandOutcome(message: "記録はしていません。") }
            history.stop(settings: settings.history)
            refreshServices()
            return CommandOutcome(message: "移動の記録を終了して保存しました。")
        case .cancel:
            return CommandOutcome(message: "キャンセルしました。", speak: false)
        case .ask(let question):
            return await askAssistant(question)
        }
    }

    /// 音声入力・テキスト入力をコマンドに変換して実行する
    func handleUtterance(_ text: String, viaVoice: Bool = false) async {
        assistant.append(ChatMessage(role: .user, text: text))
        var userPresets: [String: String] = [:]
        for p in presets where !p.isBuiltIn { userPresets[p.name] = p.id.uuidString }
        var userThemeNames: [String: String] = [:]
        for t in userThemes { userThemeNames[t.name] = t.id.uuidString }
        let parser = IntentParser(userPresetNames: userPresets, userThemeNames: userThemeNames)
        let command = parser.parse(text)
        assistant.setThinking(true)
        commandFromVoice = viaVoice
        let outcome = await perform(command)
        assistant.setThinking(false)
        var reply = ChatMessage(role: .assistant, text: outcome.message)
        if case .ask = command { reply.command = outcome.detail } else { reply.command = command.summary }
        assistant.append(reply)
        if outcome.speak && settings.assistant.speaksResponses {
            speech.speak(outcome.message, priority: .normal, force: true)
        }
    }

    func assistantContext() -> AssistantContext {
        AssistantContext(
            now: Date(),
            batteryLevel: device.batteryLevel >= 0 ? device.batteryLevel : nil,
            isCharging: device.isCharging,
            speedMetersPerSecond: location.lastSample.flatMap { $0.hasValidSpeed ? $0.speed : nil },
            speedUnit: .kilometersPerHour,
            navigationDestination: navigation.activeRoute?.destinationName,
            remainingDistance: navigation.progress?.remainingDistance,
            remainingTime: navigation.progress?.remainingTime,
            weatherSummary: weather.snapshot?.spokenSummary,
            placeName: location.placeName,
            headingDegrees: location.heading,
            isOnline: network.isOnline
        )
    }

    /// AI への質問。クラウドは同意と API キーがある場合のみ。
    func askAssistant(_ question: String) async -> CommandOutcome {
        let s = settings.assistant
        let cloudReady = s.provider.isCloud && s.cloudConsentGiven
        guard cloudReady, network.isOnline else {
            return CommandOutcome(message: LocalResponder.fallbackAnswer(for: question, cloudAvailable: cloudReady, isOnline: network.isOnline))
        }
        // AI に渡す情報は最小限（位置は地名レベル、許可した場合のみ）
        let c = assistantContext()
        var lines = ["現在時刻: \(HUDFormat.clock(c.now))"]
        if let dest = c.navigationDestination { lines.append("案内中の目的地: \(dest)") }
        if let t = c.remainingTime { lines.append("到着まで: \(HUDFormat.duration(t))") }
        if s.sharesApproximateLocation, let place = c.placeName { lines.append("現在地付近: \(place)") }
        if let w = weather.snapshot { lines.append("天気: \(w.conditionText) \(w.temperature.map { "\(Int($0.rounded()))度" } ?? "")") }
        lines.append("表示中のプリセット: \(activePreset.name)・背景: \(background.displayName)")
        if let bpm = heartRate.bpm, heartRate.isFresh { lines.append("心拍数: \(bpm)") }
        if settings.history.recordsUsage { lines.append("利用状況:\n" + history.usage.summaryText) }
        do {
            let extra = s.allowsAICommands ? AICommandCodec.catalog : ""
            let answer = try await CloudAssistant.ask(question, context: lines.joined(separator: "\n"), settings: s, network: network, extraSystem: extra)
            if s.allowsAICommands { return await runAIPlan(answer) }
            return CommandOutcome(message: answer)
        } catch {
            return CommandOutcome(message: error.localizedDescription)
        }
    }

    func open(_ screen: AppScreen) {
        switch screen {
        case .home, .hud, .navigation, .vision, .assistant, .settings:
            selectedTab = screen
        case .hudEditor:
            selectedTab = .hud
        case .history:
            selectedTab = .settings
            settingsPath = [.history]
        case .weather:
            selectedTab = .settings
            settingsPath = [.weather]
        }
    }

    private func navigate(to query: String) async -> CommandOutcome {
        do {
            let results = try await searchPlaces(query)
            guard let place = results.first else { return CommandOutcome(message: "「\(query)」が見つかりませんでした。") }
            await navigation.plan(to: place, transport: settings.map.defaultTransport)
            if navigation.phase == .choosing {
                navigation.start()
                return CommandOutcome(message: "\(place.name)までの案内を開始します。", speak: false)
            }
            selectedTab = .navigation
            return CommandOutcome(message: navigation.message ?? "ルートが見つかりませんでした。")
        } catch {
            return CommandOutcome(message: "検索できませんでした。\(network.isOnline ? "" : "オフラインです。")")
        }
    }

    private func searchNearby(_ category: NearbyCategory) async -> CommandOutcome {
        guard let origin = location.lastSample?.coordinate else {
            location.start()
            return CommandOutcome(message: "現在地を取得できていません。少し待ってからもう一度お試しください。")
        }
        do {
            let results = try await nearbyPlaces(category, near: origin)
            nearbyResults = results
            nearbyCategory = category
            selectedTab = .navigation
            guard let first = results.first else { return CommandOutcome(message: "近くに\(category.displayName)は見つかりませんでした。") }
            let distance = first.distance.map { "、約\(HUDFormat.spokenDistance($0))" } ?? ""
            return CommandOutcome(message: "近くの\(category.displayName)が\(results.count)件見つかりました。一番近いのは\(first.name)\(distance)です。")
        } catch {
            return CommandOutcome(message: "検索できませんでした。")
        }
    }

    // MARK: - パネル編集

    func updatePanel(_ id: UUID, _ change: (inout HUDPanel) -> Void) {
        var l = layout
        guard let i = l.panels.firstIndex(where: { $0.id == id }) else { return }
        change(&l.panels[i])
        layout = l
    }

    func updateCanvas(_ change: (inout CanvasSettings) -> Void) {
        var l = layout
        change(&l.canvas)
        l.canvas = l.canvas.sanitized()
        layout = l
    }

    func addWidget(_ kind: WidgetKind) {
        pushUndo()
        var l = layout
        let size = kind.defaultSize
        let frame = LayoutEngine.freeSpot(for: size, avoiding: l.panels, margin: l.canvas.safeMargin)
        let panel = HUDPanel(widget: kind, frame: frame, zIndex: l.maxZIndex + 1)
        l.panels.append(panel)
        layout = l
        selectedPanelIDs = [panel.id]
    }

    func showWidget(_ kind: WidgetKind) {
        if layout.panels.contains(where: { $0.widget == kind }) {
            var l = layout
            for i in l.panels.indices where l.panels[i].widget == kind { l.panels[i].isVisible = true }
            layout = l
        } else {
            addWidget(kind)
        }
    }

    func hideWidget(_ kind: WidgetKind) {
        var l = layout
        for i in l.panels.indices where l.panels[i].widget == kind { l.panels[i].isVisible = false }
        layout = l
    }

    func deletePanels(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pushUndo()
        var l = layout
        l.panels.removeAll { ids.contains($0.id) }
        layout = l
        selectedPanelIDs.subtract(ids)
    }

    func duplicatePanel(_ id: UUID) {
        pushUndo()
        let (l, newID) = LayoutEngine.duplicate(id, in: layout)
        layout = l
        if let newID { selectedPanelIDs = [newID] }
    }

    func bringToFront(_ id: UUID) { layout = LayoutEngine.bringToFront(id, in: layout) }
    func sendToBack(_ id: UUID) { layout = LayoutEngine.sendToBack(id, in: layout) }

    func align(_ edge: AlignmentEdge) {
        let ids = selectedPanelIDs
        guard ids.count >= 2 else { return }
        pushUndo()
        var l = layout
        let selected = l.panels.filter { ids.contains($0.id) }
        let aligned = LayoutEngine.align(selected, edge: edge)
        for p in aligned { l.update(p) }
        layout = l
    }

    func autoArrange() {
        pushUndo()
        var l = layout
        l.panels = LayoutEngine.autoArrange(l.panels, margin: l.canvas.safeMargin)
        layout = l
    }

    func resolveOverlaps(pinned: UUID?) {
        var l = layout
        l.panels = LayoutEngine.resolveOverlaps(l.panels, pinned: pinned, margin: l.canvas.safeMargin)
        layout = l
    }

    func zoomMaps(_ direction: ZoomDirection) {
        let factor = direction == .zoomIn ? 0.6 : 1.6
        var l = layout
        for i in l.panels.indices where l.panels[i].widget == .miniMap {
            l.panels[i].config.mapSpanMeters = (l.panels[i].config.mapSpanMeters * factor).clamped(to: 100...5000)
        }
        layout = l
        navigationMapZoom = (navigationMapZoom * factor).clamped(to: 0.1...10)
    }

    // MARK: - プリセット

    func applyPreset(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        activePresetID = id
        undoStack.removeAll()
        selectedPanelIDs = []
        settings.voice.guidanceEnabled = preset.features.voiceGuidance
        if settings.detection.hasAcceptedDisclaimer {
            settings.detection.enabled = preset.features.objectDetection
            settings.detection.hazardAlertsEnabled = preset.features.hazardAlerts
        }
        refreshServices()
    }

    func cyclePreset(_ offset: Int) {
        guard let i = presets.firstIndex(where: { $0.id == activePresetID }), !presets.isEmpty else { return }
        let next = presets[(i + offset + presets.count) % presets.count]
        applyPreset(next.id)
        showToast("プリセット：\(next.name)")
    }

    func saveCurrentAsNewPreset(named name: String) {
        var copy = activePreset.duplicated(name: name.isEmpty ? nil : name)
        copy.symbol = "star"
        presets.append(copy)
        applyPreset(copy.id)
    }

    func renamePreset(_ id: UUID, to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        presets[i].name = name
    }

    func deletePreset(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }), !preset.isBuiltIn else { return }
        presets.removeAll { $0.id == id }
        if activePresetID == id, let first = presets.first { applyPreset(first.id) }
    }

    /// 組み込みプリセットを初期状態に戻す
    func resetPreset(_ id: UUID) {
        guard let i = presets.firstIndex(where: { $0.id == id }), let key = presets[i].key,
              let fresh = BuiltInContent.makePresets().first(where: { $0.key == key }) else { return }
        presets[i] = fresh
        undoStack.removeAll()
    }

    // MARK: - テーマ

    func applyTheme(_ ref: String) {
        updateActivePreset { $0.themeRef = ref }
    }

    @discardableResult
    func duplicateTheme(_ theme: Theme) -> Theme {
        let copy = theme.duplicated()
        userThemes.append(copy)
        return copy
    }

    func updateTheme(_ theme: Theme) {
        guard let i = userThemes.firstIndex(where: { $0.id == theme.id }) else { return }
        userThemes[i] = theme
    }

    func deleteTheme(_ id: UUID) {
        userThemes.removeAll { $0.id == id }
        for i in presets.indices where presets[i].themeRef == id.uuidString {
            presets[i].themeRef = BuiltInContent.defaultThemeKey
        }
    }

    // MARK: - 書き出し・読み込み（iCloud Drive などで端末間を同期）

    func exportBundleFile(includeHistory: Bool) -> URL? {
        let bundle = SettingsBundle(
            exportedAt: Date(),
            deviceName: UIDevice.current.name,
            settings: settings,
            themes: userThemes,
            presets: presets,
            favorites: favorites,
            trips: includeHistory ? history.trips : nil,
            visits: includeHistory ? history.visits : nil,
            deviceID: settings.sync.deviceID
        )
        return writeTemp(name: "HUDNavigator-設定", data: try? bundle.encoded())
    }

    func exportThemesFile(_ themes: [Theme]) -> URL? {
        writeTemp(name: "HUDNavigator-テーマ", data: try? HUDJSON.encode(themes))
    }

    private func writeTemp(name: String, data: Data?) -> URL? {
        guard let data else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(formatter.string(from: Date())).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// 設定ファイル・テーマファイルのどちらでも読み込める
    func importFile(_ url: URL, strategy: SettingsBundle.MergeStrategy) -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return "ファイルを読み込めませんでした。" }
        if let themes = try? HUDJSON.decode([Theme].self, from: data), !themes.isEmpty {
            let incoming = themes.filter { !$0.isBuiltIn }
            userThemes = SettingsBundle.merged(userThemes, incoming: incoming, strategy: .merge, isBuiltIn: { _ in false })
            return "テーマを\(incoming.count)件読み込みました。"
        }
        do {
            let bundle = try SettingsBundle.decode(data)
            // 端末ごとの状態（同意・Bluetooth・同期の設定）は引き継がない
            return applyBundle(bundle, strategy: strategy)
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - お気に入り

    func addFavorite(_ place: PlaceResult) {
        guard !favorites.contains(where: { Geo.distance($0.coordinate, place.coordinate) < 15 }) else { return }
        favorites.append(FavoritePlace(name: place.name, address: place.address, coordinate: place.coordinate))
    }

    func removeFavorite(_ id: UUID) {
        favorites.removeAll { $0.id == id }
    }

    // MARK: - データ削除

    func deleteAllData() {
        navigation.stop()
        history.deleteAll()
        store.deleteAll()
        KeychainStore.deleteAll()
        vision.removeCustomModel()
        network.clear()
        alerts.clearHistory()
        assistant.clear()
        deviceTest.reset()
        weather.clear()
        userThemes = []
        favorites = []
        presets = BuiltInContent.makePresets()
        let fresh = AppSettings()
        settings = fresh
        activePresetID = presets.first { $0.key == BuiltInContent.defaultPresetKey }?.id ?? presets[0].id
        showsOnboarding = true
        saveNow()
    }
}
