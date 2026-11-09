import SwiftUI
import UIKit

extension AppCommand {
    /// 利用統計に使う名前（ユーザーが話した内容は含めない）
    var usageName: String {
        switch self {
        case .navigate: return "目的地へのナビ"
        case .search: return "場所の検索"
        case .ask: return "AIへの質問"
        case .applyPreset: return "プリセットの切り替え"
        case .applyTheme: return "テーマの切り替え"
        default: return summary
        }
    }
}

/// 追加機能（Google Maps・AI の操作・提案・同期・心拍・URL 操作・テンプレート）
extension AppModel {
    // MARK: - 起動

    func configureFeatures() {
        advisor.settings = settings.proactive
        heartRate.remembered = { [unowned self] in
            self.settings.bluetooth.rememberedDeviceID.flatMap(UUID.init(uuidString:))
        }
        heartRate.onConnected = { [unowned self] id, name in
            if self.settings.bluetooth.rememberedDeviceID != id.uuidString {
                self.settings.bluetooth.rememberedDeviceID = id.uuidString
                self.settings.bluetooth.rememberedDeviceName = name
            }
            self.showToast("心拍計「\(name)」に接続しました")
        }
        history.placeNameLookup = { coordinate in
            await MapSearch.placeName(for: coordinate)
        }
        navigation.routeProvider = { [unowned self] origin, place, transport in
            try await self.findRoutes(from: origin, to: place, transport: transport)
        }
        // 距離（LiDAR・2 つのカメラ・AI）
        depth.geometry = { [unowned self] in (self.motion.cameraPitchDown, self.camera.verticalFieldOfView) }
        depth.onObstacle = { [unowned self] o in self.postObstacle(o) }
        depth.attach(to: camera, settings: settings.depth, enabled: settings.depth.enabled)
        // 頭の動き
        if settings.display.headLockWithAirPods && settings.headTracking.source == .off {
            // 旧設定（AirPods で空間固定）を引き継ぐ
            settings.headTracking.source = .airPods
            settings.headTracking.headLock = true
            settings.display.headLockWithAirPods = false
        }
        headTracking.onGesture = { [unowned self] g in self.handleHeadGesture(g) }
        headTracking.isBackCameraBusy = { [unowned self] in self.camera.isInUse }
        headTracking.ble.remembered = { [unowned self] in
            self.settings.headTracking.rememberedSensorID.flatMap(UUID.init(uuidString:))
        }
        headTracking.ble.onConnected = { [unowned self] id, name in
            if self.settings.headTracking.rememberedSensorID != id.uuidString {
                self.settings.headTracking.rememberedSensorID = id.uuidString
                self.settings.headTracking.rememberedSensorName = name
            }
            self.showToast("動きセンサー「\(name)」に接続しました")
        }
        featureTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.featureTimerFired() }
        }
        Task { await importFromSyncFolderIfNewer() }
    }

    /// 10 秒ごと：利用時間の記録・移動時間の計測・1 分ごとに提案
    func featureTimerFired() {
        featureTick += 1
        if isHUDVisible && !isInBackground {
            history.recordHUD(seconds: 10, preset: activePreset.name, settings: settings.history)
        }
        let now = Date()
        if movement.isMoving {
            if movingSince == nil { movingSince = now }
            lastMovingAt = now
        } else if let last = lastMovingAt, now.timeIntervalSince(last) > 180 {
            movingSince = nil
            lastMovingAt = nil
        }
        if featureTick % 6 == 0 { runAdvisor(now: now) }
    }

    // MARK: - 頭の動き

    /// 頭の向きを取るか（表示中で、空間固定・ジェスチャー・チラ見のどれかを使う、または画面・ウィジェットで見ている）
    var headTrackingWanted: Bool {
        let h = settings.headTracking
        guard h.source != .off else { return false }
        return needs(.headTracking) || (isHUDVisible && (h.headLock || h.gesturesEnabled || h.glanceMode))
    }

    func handleHeadGesture(_ g: HeadGesture) {
        let action = settings.headTracking.action(for: g)
        guard action != .none else { return }
        deviceTest.record("頭のジェスチャー: \(g.displayName) → \(action.displayName)")
        showToast("\(g.displayName)：\(action.displayName)")
        switch action {
        case .none: break
        case .acceptSuggestion:
            if suggestion != nil { acceptSuggestion() }
        case .dismissAlerts: alerts.dismissAll()
        case .repeatGuidance: Task { await perform(.repeatGuidance) }
        case .nextPreset: cyclePreset(1)
        case .previousPreset: cyclePreset(-1)
        case .toggleBackground: background = background.toggled
        case .recenter: headTracking.recenter()
        case .startVoice: if !speechInput.isListening { speechInput.toggle() }
        }
    }

    // MARK: - 距離・障害物

    func postObstacle(_ o: Obstacle) {
        let distance = HUDFormat.distance(o.distance)
        alerts.post(HUDAlert(
            category: .hazard,
            title: "\(o.direction) \(distance)に物があります",
            message: "距離は目安です（\(depth.sourceLabel)）",
            priority: o.level == .high ? .critical : .important,
            duration: 2.5,
            dedupeKey: "obstacle-\(o.direction)",
            spokenText: "\(o.direction)、\(HUDFormat.spokenDistance(o.distance))"
        ))
    }

    func measureDistanceOutcome() -> CommandOutcome {
        guard settings.depth.enabled else {
            settings.depth.enabled = true
            return CommandOutcome(message: "距離の推定を始めました。数秒後にもう一度聞いてください。")
        }
        if let d = depth.centerDistance {
            return CommandOutcome(message: "正面まで約\(HUDFormat.spokenDistance(d))です（\(depth.sourceLabel)）。")
        }
        if depth.grid != nil && !(depth.grid?.isMetric ?? false) {
            return CommandOutcome(message: "距離をメートルに直せません。端末を少し下に向けて、地面が映るようにしてください。")
        }
        if !camera.isRunning {
            return CommandOutcome(message: "カメラが動いていません。HUD を表示するか、ビジョン画面を開いてください。")
        }
        return CommandOutcome(message: "まだ測れていません。少し待ってからもう一度聞いてください。")
    }

    // MARK: - 提案（プロアクティブ）

    func runAdvisor(now: Date = Date()) {
        let input = AdvisorInput(
            now: now,
            weather: weather.snapshot,
            batteryLevel: device.batteryLevel,
            isCharging: device.isCharging,
            thermal: device.thermal,
            movement: movement,
            continuousMovingSeconds: movingSince.map { now.timeIntervalSince($0) } ?? 0,
            justArrived: arrivedAt.map { now.timeIntervalSince($0) < 180 } ?? false,
            isHUDVisible: isHUDVisible,
            cameraActive: camera.isRunning,
            activePresetKey: activePreset.key
        )
        for s in advisor.evaluate(input) { present(s) }
    }

    func present(_ s: Suggestion) {
        suggestion = s
        alerts.post(HUDAlert(category: .assistant, title: s.title, message: s.message, priority: .normal, duration: 8, dedupeKey: "suggest-\(s.key)"))
        deviceTest.record("提案: \(s.title)")
    }

    func acceptSuggestion() {
        guard let s = suggestion else { return }
        suggestion = nil
        if let action = s.action {
            Task {
                let outcome = await perform(action)
                showToast(outcome.message)
            }
        }
    }

    // MARK: - 地図サービスの選択（Google / Apple）

    var googleReady: Bool { GoogleMapsService.isReady(settings.googleMaps) && network.isOnline }

    var usesGoogleSearch: Bool {
        settings.map.engine == .googleMaps && settings.googleMaps.usesForSearch && googleReady
    }

    /// 公共交通は MapKit では経路が取れないので、Google が使えるなら地図エンジンの設定に関係なく Google を使う
    func usesGoogleRoutes(_ transport: TransportMode) -> Bool {
        guard googleReady else { return false }
        if transport == .transit { return settings.googleMaps.usesForTransit }
        return settings.map.engine == .googleMaps && settings.googleMaps.usesForRoutes
    }

    func findRoutes(from origin: GeoCoordinate?, to place: PlaceResult, transport: TransportMode) async throws -> [NavRoute] {
        if usesGoogleRoutes(transport), let start = origin ?? location.lastSample?.coordinate {
            do {
                let routes = try await GoogleMapsService.routes(from: start, to: place, transport: transport, network: network)
                navigation.setRouteSource("Google")
                return routes
            } catch {
                deviceTest.record("Google のルート検索に失敗: \(error.localizedDescription)")
                // 公共交通は MapKit で代わりが効かないのでそのままエラーを返す
                if transport == .transit { throw error }
            }
        }
        navigation.setRouteSource("Apple")
        return try await RoutePlanner.routes(from: origin, to: place, transport: transport)
    }

    func searchPlaces(_ query: String) async throws -> [PlaceResult] {
        let origin = location.lastSample?.coordinate
        if usesGoogleSearch {
            do {
                let results = try await GoogleMapsService.search(query, near: origin, network: network)
                if !results.isEmpty { return results }
            } catch {
                deviceTest.record("Google の検索に失敗: \(error.localizedDescription)")
            }
        }
        return try await MapSearch.search(query, near: origin)
    }

    func nearbyPlaces(_ category: NearbyCategory, near origin: GeoCoordinate) async throws -> [PlaceResult] {
        if usesGoogleSearch {
            do {
                let results = try await GoogleMapsService.nearby(category, near: origin, network: network)
                if !results.isEmpty { return results }
            } catch {
                deviceTest.record("Google の周辺検索に失敗: \(error.localizedDescription)")
            }
        }
        return try await MapSearch.nearby(category, near: origin)
    }

    // MARK: - AI にアプリを操作してもらう

    /// AI の返答を操作に変換して実行する（一覧にある操作のみ・最大4つ）
    func runAIPlan(_ answer: String) async -> CommandOutcome {
        let plan = AICommandCodec.decode(answer)
        var done: [String] = []
        var messages: [String] = []
        for command in plan.commands {
            if case .ask = command { continue }
            let outcome = await perform(command)
            done.append(command.summary)
            messages.append(outcome.message)
        }
        let reply: String
        if !plan.reply.isEmpty { reply = plan.reply }
        else if !messages.isEmpty { reply = messages.joined(separator: " ") }
        else { reply = answer }
        return CommandOutcome(message: reply, speak: true, detail: done.isEmpty ? nil : "AIが実行：" + done.joined(separator: "、"))
    }

    // MARK: - テキストウィジェットのテンプレート

    func templateValues(now: Date = Date()) -> [String: String] {
        var v: [String: String] = [
            "time": HUDFormat.clock(now),
            "date": HUDFormat.date(now),
            "preset": activePreset.name,
            "distance": HUDFormat.distance(history.sessionDistance),
        ]
        if device.batteryLevel >= 0 { v["battery"] = HUDFormat.percent(device.batteryLevel) }
        if let s = location.lastSample, s.hasValidSpeed { v["speed"] = String(Int((s.speed * 3.6).rounded())) }
        if let h = location.heading { v["heading"] = Geo.cardinalName(h) }
        if let p = location.placeName { v["place"] = p }
        if let eta = navigation.eta { v["eta"] = HUDFormat.clock(eta) }
        if let r = navigation.progress?.remainingDistance { v["remaining"] = HUDFormat.distance(r) }
        if let step = navigation.nextStep { v["next"] = step.instruction }
        if let w = weather.snapshot {
            if let t = w.temperature { v["temp"] = "\(Int(t.rounded()))°" }
            v["weather"] = w.conditionText
            if let p = w.precipitationProbability { v["rain"] = "\(Int(p))%" }
        }
        if let bpm = heartRate.bpm, heartRate.isFresh { v["hr"] = String(bpm) }
        if let steps = pedometer.stepsToday { v["steps"] = String(steps) }
        if let p = headTracking.pose { v["yaw"] = String(format: "%+.0f°", p.yaw) }
        return v
    }

    // MARK: - URL（hudnavigator://…）

    func handleDeepLink(_ url: URL) {
        guard let command = DeepLink.command(from: url) else {
            showToast("この URL には対応していません")
            return
        }
        deviceTest.record("URL から操作: \(url.absoluteString)")
        Task {
            let outcome = await perform(command)
            showToast(outcome.message)
        }
    }

    // MARK: - 端末画面の明るさ（グラスに独立表示中は暗くする）

    func updateDeviceScreenDimming() {
        let shouldDim = settings.display.dimsDeviceScreen && display.mode == .independent && !isInBackground
        if shouldDim {
            if savedScreenBrightness == nil { savedScreenBrightness = currentScreen?.brightness }
            currentScreen?.brightness = 0.1
        } else {
            restoreDeviceScreenBrightness()
        }
    }

    func restoreDeviceScreenBrightness() {
        guard let saved = savedScreenBrightness else { return }
        currentScreen?.brightness = saved
        savedScreenBrightness = nil
    }

    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }?
            .screen
    }

    /// HUD の明るさ（夜間は自動で暗く）
    var hudBrightness: Double {
        let hour = Calendar.current.component(.hour, from: Date())
        return settings.display.effectiveBrightness(hour: hour, isDaylight: weather.snapshot?.isDay)
    }

    // MARK: - 同期（iCloud Drive などのフォルダ）

    func makeSyncBundle() -> SettingsBundle {
        SettingsBundle(
            exportedAt: Date(),
            deviceName: UIDevice.current.name,
            settings: settings,
            themes: userThemes,
            presets: presets,
            favorites: favorites,
            trips: settings.sync.includesHistory ? history.trips : nil,
            visits: settings.sync.includesHistory ? history.visits : nil,
            deviceID: settings.sync.deviceID
        )
    }

    /// 同期する内容の指紋（書き出し・読み込みの時刻は含めない）。変わっていなければ書き出さない。
    func syncFingerprint() -> Int {
        var s = settings
        s.sync.lastExportedAt = nil
        s.sync.lastImportedAt = nil
        var h = Hasher()
        h.combine(s)
        h.combine(userThemes)
        h.combine(presets)
        h.combine(favorites)
        if settings.sync.includesHistory {
            h.combine(history.trips.count)
            h.combine(history.visits.count)
        }
        return h.finalize()
    }

    /// 保存のたびに呼ばれる。自動同期が ON で内容が変わっていたら、少し待ってから書き出す。
    func scheduleSyncExport() {
        guard settings.sync.autoSyncEnabled, syncFolder.isConfigured, !isApplyingSyncImport else { return }
        guard syncFingerprint() != lastSyncFingerprint else { return }
        syncExportTask?.cancel()
        syncExportTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.exportToSyncFolder()
        }
    }

    @discardableResult
    func exportToSyncFolder() -> Bool {
        guard syncFolder.isConfigured, let data = try? makeSyncBundle().encoded() else { return false }
        let ok = syncFolder.write(data)
        if ok {
            settings.sync.lastExportedAt = Date()
            lastSyncFingerprint = syncFingerprint()
            try? store.save(settings, as: "settings")
        }
        return ok
    }

    /// 他の端末が新しく書き出していたら読み込む
    func importFromSyncFolderIfNewer() async {
        guard settings.sync.autoSyncEnabled, syncFolder.isConfigured else { return }
        guard let data = await syncFolder.read(), let bundle = try? SettingsBundle.decode(data) else { return }
        let should = SyncDecision.shouldImport(
            remoteExportedAt: bundle.exportedAt,
            remoteDeviceID: bundle.deviceID,
            localDeviceID: settings.sync.deviceID,
            lastImportedAt: settings.sync.lastImportedAt,
            lastExportedAt: settings.sync.lastExportedAt
        )
        guard should else { return }
        let message = applyBundle(bundle, strategy: .merge)
        syncFolder.setMessage(message)
        alerts.post(HUDAlert(category: .system, title: "同期しました", message: message, priority: .normal, duration: 5))
    }

    /// 手動の「今すぐ同期」：まず読み込み（新しければ）→ 書き出し
    func syncNow() async -> String {
        guard syncFolder.isConfigured else { return "同期フォルダが設定されていません（設定 → データ → 同期）。" }
        syncFolder.setWorking(true)
        defer { syncFolder.setWorking(false) }
        var parts: [String] = []
        if let data = await syncFolder.read(), let bundle = try? SettingsBundle.decode(data), bundle.deviceID != settings.sync.deviceID,
           bundle.exportedAt > (settings.sync.lastImportedAt ?? .distantPast) {
            parts.append(applyBundle(bundle, strategy: .merge))
        }
        parts.append(exportToSyncFolder() ? "同期フォルダに書き出しました。" : "書き出せませんでした。")
        let text = parts.joined(separator: " ")
        syncFolder.setMessage(text)
        return text
    }

    /// 設定のまとめを反映する（端末ごとの設定は引き継がない）
    func applyBundle(_ bundle: SettingsBundle, strategy: SettingsBundle.MergeStrategy) -> String {
        isApplyingSyncImport = true
        defer { isApplyingSyncImport = false }
        if let s = bundle.settings {
            var merged = s
            merged.hasCompletedOnboarding = settings.hasCompletedOnboarding
            merged.detection.hasAcceptedDisclaimer = settings.detection.hasAcceptedDisclaimer
            merged.assistant.cloudConsentGiven = settings.assistant.cloudConsentGiven
            merged.googleMaps.consentGiven = settings.googleMaps.consentGiven
            merged.bluetooth = settings.bluetooth
            merged.sync = settings.sync
            merged.sync.lastImportedAt = Date()
            settings = merged
        } else {
            settings.sync.lastImportedAt = Date()
        }
        userThemes = SettingsBundle.merged(userThemes, incoming: bundle.themes, strategy: strategy, isBuiltIn: { $0.isBuiltIn })
        presets = SettingsBundle.merged(presets, incoming: bundle.presets, strategy: strategy, isBuiltIn: { $0.isBuiltIn })
        favorites = SettingsBundle.merged(favorites, incoming: bundle.favorites, strategy: strategy, isBuiltIn: { _ in false })
        if settings.history.enabled {
            if let trips = bundle.trips { history.replace(with: trips) }
            if let visits = bundle.visits { history.replaceVisits(with: visits) }
        }
        if !presets.contains(where: { $0.id == activePresetID }), let first = presets.first { activePresetID = first.id }
        try? store.save(settings, as: "settings")
        try? store.save(userThemes, as: "themes")
        try? store.save(presets, as: "presets")
        try? store.save(favorites, as: "favorites")
        // 読み込んだ内容をすぐ書き戻さない（端末間で読み書きを繰り返さないため）
        lastSyncFingerprint = syncFingerprint()
        return "「\(bundle.deviceName)」の設定を読み込みました（テーマ\(bundle.themes.count)件・プリセット\(bundle.presets.count)件・お気に入り\(bundle.favorites.count)件）。"
    }
}
