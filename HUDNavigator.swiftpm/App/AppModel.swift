import SwiftUI
import UIKit
import Observation

/// アプリ全体の状態。端末画面とグラス（外部画面）は同じ AppModel を参照する。
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: - 保存される状態

    var settings: AppSettings {
        didSet { settingsDidChange(from: oldValue) }
    }
    /// ユーザーテーマ（組み込みテーマはコードにある）
    var userThemes: [Theme] {
        didSet { scheduleSave() }
    }
    var presets: [Preset] {
        didSet { scheduleSave() }
    }
    var favorites: [FavoritePlace] {
        didSet { scheduleSave() }
    }
    var activePresetID: UUID {
        didSet {
            if settings.selectedPresetID != activePresetID { settings.selectedPresetID = activePresetID }
        }
    }

    // MARK: - 画面の状態

    var selectedTab: AppScreen = .home
    var settingsPath: [SettingsRoute] = []
    /// 端末画面に HUD を全画面表示中（ミラー表示・単体利用時）
    var isHUDPresented = false {
        didSet {
            updateIdleTimer()
            if oldValue != isHUDPresented { refreshServices() }
        }
    }
    var selectedPanelIDs: Set<UUID> = []
    var toast: String?
    var showsOnboarding: Bool
    /// 乗り物の速度が続いたため HUD を最小化している
    private(set) var hudMinimizedForSpeed = false
    private(set) var isInBackground = false
    private(set) var movement: MovementState = .unknown
    private(set) var powerProfile: PowerProfile
    /// 音声コマンドから渡された検索語（ナビ画面が受け取る）
    var pendingSearch: String?
    var nearbyResults: [PlaceResult] = []
    var nearbyCategory: NearbyCategory?
    /// ナビ画面の地図の拡大率（音声コマンド「地図を大きく」用）
    var navigationMapZoom: Double = 1
    var showsVisionDisclaimer = false
    /// 端末画面を真っ暗にする（独立表示中の省電力）
    var isDeviceScreenBlanked = false
    /// 視認性テスト（文字見本）を表示中
    var showsTestPattern = false
    /// AI からの提案（ホーム画面にボタン付きで表示）
    var suggestion: Suggestion?
    /// 最後に読み取った標識
    private(set) var lastSign: SignTextClassifier.SignReading?

    // MARK: - サービス

    let display = DisplayManager()
    let device = DeviceStatusService()
    let location = LocationService()
    let motion = MotionService()
    let camera = CameraController()
    let vision = VisionModel()
    let navigation = NavigationModel()
    let speech = SpeechOutput()
    let speechInput = SpeechInputService()
    let network = NetworkLog()
    let weather = WeatherModel()
    let assistant = AssistantModel()
    let alerts = AlertCenter()
    let history = HistoryModel()
    let metrics = MetricsMonitor()
    let deviceTest = DeviceTestModel()
    let heartRate = HeartRateService()
    let syncFolder = SyncFolderService()

    @ObservationIgnored let store: JSONFileStore
    @ObservationIgnored private var demand: [WidgetRequirement: Int] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var vehicleGuard = VehicleSpeedGuard()
    var undoStack: [HUDLayout] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var powerTimer: Timer?
    @ObservationIgnored private var lastBatteryWarning: Double = 1
    @ObservationIgnored var advisor = ProactiveAdvisor(settings: ProactiveSettings())
    @ObservationIgnored var featureTimer: Timer?
    @ObservationIgnored var featureTick = 0
    @ObservationIgnored var movingSince: Date?
    @ObservationIgnored var lastMovingAt: Date?
    @ObservationIgnored var lastSyncFingerprint: Int?
    @ObservationIgnored var arrivedAt: Date?
    @ObservationIgnored var savedScreenBrightness: CGFloat?
    @ObservationIgnored var syncExportTask: Task<Void, Never>?
    @ObservationIgnored var isApplyingSyncImport = false
    /// 直前のコマンドが音声入力からか（利用統計用）
    @ObservationIgnored var commandFromVoice = false

    // MARK: - 初期化

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let store = JSONFileStore(directory: base.appendingPathComponent("HUDNavigator", isDirectory: true))
        self.store = store

        let loadedSettings = store.loadData("settings").flatMap { try? AppSettings.decodeMergingDefaults(from: $0) } ?? AppSettings()
        settings = loadedSettings
        userThemes = store.load([Theme].self, from: "themes") ?? []
        favorites = store.load([FavoritePlace].self, from: "favorites") ?? []

        var loadedPresets = store.load([Preset].self, from: "presets") ?? []
        // 組み込みプリセットが欠けていたら追加（アプリ更新時）
        for builtIn in BuiltInContent.makePresets() where !loadedPresets.contains(where: { $0.id == builtIn.id }) {
            loadedPresets.append(builtIn)
        }
        presets = loadedPresets
        let preferred = loadedSettings.selectedPresetID.flatMap { id in loadedPresets.first { $0.id == id }?.id }
        activePresetID = preferred ?? loadedPresets.first { $0.key == BuiltInContent.defaultPresetKey }?.id ?? loadedPresets[0].id
        showsOnboarding = !loadedSettings.hasCompletedOnboarding
        powerProfile = PowerPolicy.profile(for: PowerState())
    }

    /// 起動時に一度だけ呼ぶ
    func startIfNeeded() {
        guard !started else { return }
        started = true

        device.start()
        speech.settingsProvider = { [unowned self] in self.settings.voice }
        camera.settingsProvider = { [unowned self] in self.settings.camera }
        alerts.update(settings: settings.notifications)
        alerts.speak = { [unowned self] text, priority in self.speech.speak(text, priority: priority, force: true) }
        alerts.isMoving = { [unowned self] in self.movement.isMoving }
        alerts.isInBackground = { [unowned self] in self.isInBackground }
        weather.network = network
        history.load(from: store)
        history.applyRetention(settings.history)
        deviceTest.load(from: store)
        deviceTest.sampleProvider = { [unowned self] in self.currentMetricSample() }
        speechInput.requireOnDevice = settings.assistant.requiresOnDeviceSpeech
        speechInput.onFinalText = { [unowned self] text in
            Task { await self.handleUtterance(text, viaVoice: true) }
        }

        location.onSample = { [unowned self] sample in self.handleLocation(sample) }
        motion.onShake = { [unowned self] in
            guard self.isHUDVisible else { return }
            Task { await self.perform(.repeatGuidance) }
        }
        configureNavigationCallbacks()
        configureVisionCallbacks()
        configureFeatures()

        display.makeHUDView = {
            AnyView(HUDRootView(surface: .external).environment(AppModel.shared))
        }
        display.onModeChange = { [unowned self] mode in self.displayModeChanged(mode) }
        display.start()

        if settings.showsMetricsOverlay { metrics.start() }
        vision.attach(to: camera, enabled: detectionActive)
        applyPowerProfile()
        powerTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyPowerProfile() }
        }
        refreshServices()
        updateIdleTimer()
        deviceTest.record("起動（\(DeviceTestModel.environment.displayName)）")
    }

    // MARK: - プリセット・レイアウト・テーマ（現在の状態）

    var activePreset: Preset {
        presets.first { $0.id == activePresetID } ?? presets[0]
    }

    var layout: HUDLayout {
        get { activePreset.layout }
        set { updateActivePreset { $0.layout = newValue } }
    }

    var background: BackgroundMode {
        get { activePreset.background }
        set { updateActivePreset { $0.background = newValue } }
    }

    var features: FeatureToggles {
        get { activePreset.features }
        set { updateActivePreset { $0.features = newValue } }
    }

    var allThemes: [Theme] { BuiltInContent.themes + userThemes }

    var activeTheme: Theme { theme(forRef: activePreset.themeRef) }

    func theme(forRef ref: String) -> Theme {
        allThemes.first { $0.key == ref || $0.id.uuidString == ref } ?? BuiltInContent.themes[0]
    }

    func themeRef(_ theme: Theme) -> String { theme.key ?? theme.id.uuidString }

    func updateActivePreset(_ change: (inout Preset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == activePresetID }) else { return }
        change(&presets[index])
    }

    /// HUD に実際に表示するパネル（移動中・高速移動時は情報を減らす）
    var effectivePanels: [HUDPanel] {
        let panels = layout.visiblePanels
        if hudMinimizedForSpeed {
            return panels.filter { $0.widget == .clock || $0.widget == .notifications }
        }
        if features.reduceWhileMoving && movement.isMoving {
            let essential: Set<WidgetKind> = [.nextTurn, .eta, .speed, .clock, .notifications, .miniMap, .compass, .battery, .gpsStatus, .tripDistance]
            return panels.filter { essential.contains($0.widget) }
        }
        return panels
    }

    var detectionActive: Bool {
        settings.detection.enabled && settings.detection.hasAcceptedDisclaimer
    }

    /// HUD がどこかに表示されているか
    var isHUDVisible: Bool { isHUDPresented || display.mode == .independent }

    // MARK: - 保存

    private func settingsDidChange(from old: AppSettings) {
        scheduleSave()
        if old.notifications != settings.notifications { alerts.update(settings: settings.notifications) }
        if old.detection != settings.detection {
            vision.attach(to: camera, enabled: detectionActive)
            vision.configure(settings: settings.detection, inferenceFPS: powerProfile.inferenceFPS)
        }
        if old.camera.zoom != settings.camera.zoom || old.camera.exposureBias != settings.camera.exposureBias {
            camera.applySettings()
        }
        if old.camera.prefersUltraWide != settings.camera.prefersUltraWide || old.camera.useExternalCamera != settings.camera.useExternalCamera { camera.reconfigure() }
        if old.proactive != settings.proactive { advisor.settings = settings.proactive }
        if old.bluetooth.heartRateEnabled != settings.bluetooth.heartRateEnabled || old.display != settings.display { refreshServices() }
        if old.display.dimsDeviceScreen != settings.display.dimsDeviceScreen { updateDeviceScreenDimming() }
        if old.showsMetricsOverlay != settings.showsMetricsOverlay {
            if settings.showsMetricsOverlay { metrics.start() } else if !deviceTest.isRecordingMetrics { metrics.stop() }
        }
        if old.power != settings.power { applyPowerProfile(); updateIdleTimer() }
        speechInput.requireOnDevice = settings.assistant.requiresOnDeviceSpeech
        if old.history.retentionDays != settings.history.retentionDays { history.applyRetention(settings.history) }
        if old.history.enabled && !settings.history.enabled { history.stop(settings: settings.history) }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        try? store.save(settings, as: "settings")
        try? store.save(userThemes, as: "themes")
        try? store.save(presets, as: "presets")
        try? store.save(favorites, as: "favorites")
        scheduleSyncExport()
    }

    // MARK: - サービスの起動・停止（必要なときだけ動かす）

    /// ウィジェットや画面が表示されたときに必要なサービスを登録する
    func acquire(_ requirements: Set<WidgetRequirement>) {
        guard !requirements.isEmpty else { return }
        for r in requirements { demand[r, default: 0] += 1 }
        refreshServices()
    }

    func release(_ requirements: Set<WidgetRequirement>) {
        guard !requirements.isEmpty else { return }
        for r in requirements {
            let n = (demand[r] ?? 0) - 1
            demand[r] = n > 0 ? n : nil
        }
        refreshServices()
    }

    func needs(_ r: WidgetRequirement) -> Bool { (demand[r] ?? 0) > 0 }

    func refreshServices() {
        let needsLocation = needs(.location) || needs(.weather) || needs(.navigation) || navigation.isGuiding || history.isRecording
            || (features.reduceWhileMoving && isHUDVisible)
        if needsLocation || location.isSimulating { location.start() } else { location.stop() }

        let needsHeading = needs(.heading) || navigation.isGuiding
        if needsHeading { location.startHeading() } else { location.stopHeading() }

        let needsMotion = needs(.motion) || (features.reduceWhileMoving && isHUDVisible)
        if needsMotion { motion.start(hz: powerProfile.motionHz) } else { motion.stop() }

        if needs(.weather), let c = location.lastSample?.coordinate {
            weather.refreshIfNeeded(at: c, enabled: settings.privacy.weatherEnabled)
        }

        // 心拍計（設定で ON にして、心拍ウィジェットか設定画面が表示されているとき）
        if settings.bluetooth.heartRateEnabled && needs(.bluetooth) { heartRate.start() } else { heartRate.stop() }

        // AirPods の頭の向き（HUD を空間に固定する設定のとき）
        let wantsHead = settings.display.headLockWithAirPods && isHUDVisible
        if wantsHead { motion.startHeadphoneTracking() } else { motion.stopHeadphoneTracking() }
    }

    private func applyPowerProfile() {
        let previous = powerProfile.quality
        let profile = PowerPolicy.profile(for: device.powerState, automatic: settings.power.automaticPowerSaving, requestedInferenceFPS: settings.detection.inferenceFPS)
        powerProfile = profile
        camera.applyPowerProfile(fps: profile.cameraFPS, maxHeight: profile.cameraMaxHeight)
        vision.configure(settings: settings.detection, inferenceFPS: profile.inferenceFPS)
        location.setAccuracy(navigation.isGuiding ? .best : profile.locationAccuracy)
        if motion.isRunning { motion.updateRate(hz: profile.motionHz) }
        if profile.quality != previous, let suggestion = profile.suggestion {
            alerts.post(HUDAlert(category: .battery, title: "省電力：\(profile.quality.displayName)", message: suggestion, priority: .important, duration: 8))
            deviceTest.record("省電力レベル: \(profile.quality.displayName)（温度 \(device.thermal.displayName)）")
        }
        // バッテリー残量の警告（20% と 10%）
        let level = device.batteryLevel
        if level >= 0, !device.isCharging {
            for threshold in [0.2, 0.1] where level <= threshold && lastBatteryWarning > threshold {
                alerts.post(HUDAlert(category: .battery, title: "バッテリー残量 \(HUDFormat.percent(level))", message: "充電をおすすめします。", priority: .important, duration: 8))
            }
            lastBatteryWarning = level
        } else if device.isCharging {
            lastBatteryWarning = 1
        }
    }

    private func updateIdleTimer() {
        let keepAwake = settings.power.keepsScreenAwake && (isHUDPresented || display.isExternalConnected || navigation.isGuiding)
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }

    // MARK: - イベント

    private func handleLocation(_ sample: LocationSample) {
        navigation.handle(sample)
        history.handle(sample, settings: settings.history)
        if needs(.weather) { weather.refreshIfNeeded(at: sample.coordinate, enabled: settings.privacy.weatherEnabled) }
        let speed: Double? = sample.hasValidSpeed ? sample.speed : nil
        movement = MovementState.estimate(speed: speed, accelerationVariance: motion.isRunning ? motion.accelerationVariance : nil)
        let minimize = vehicleGuard.update(speed: location.isSimulating ? nil : speed, at: sample.timestamp)
        if minimize != hudMinimizedForSpeed {
            hudMinimizedForSpeed = minimize
            if minimize {
                alerts.post(HUDAlert(category: .system, title: "HUDを最小化しました", message: "速い速度での移動が続いています。運転中の使用は想定していません。", priority: .important, duration: 8))
                deviceTest.record("高速移動のため HUD を最小化")
            }
        }
    }

    private func configureNavigationCallbacks() {
        navigation.voiceSettings = { [unowned self] in self.settings.voice }
        navigation.currentLocation = { [unowned self] in self.location.lastSample?.coordinate }
        navigation.announce = { [unowned self] a in
            let category: AlertCategory
            switch a.kind {
            case .arrival: category = .arrival
            case .reroute, .offRoute: category = .reroute
            default: category = .navigation
            }
            let channel = self.settings.notifications.channel(for: category)
            if self.settings.voice.guidanceEnabled && channel.speaks {
                self.speech.speak(a.text, priority: a.kind == .offRoute ? .high : .normal)
            }
            if category != .navigation {
                self.alerts.post(HUDAlert(category: category, title: category.displayName, message: a.text, priority: .important, duration: 6), allowSpeech: false)
            }
        }
        navigation.onStart = { [unowned self] route in
            self.history.start(settings: self.settings.history, destination: route.destinationName, transport: route.transport)
            self.location.setBackgroundUpdates(true)
            if route.transport == .walking && !self.layout.contains(widget: .nextTurn) {
                self.showWidget(.nextTurn)
            }
            self.refreshServices()
            self.updateIdleTimer()
            self.deviceTest.record("ナビ開始: \(route.destinationName) \(HUDFormat.distance(route.distance))")
        }
        navigation.onArrive = { [unowned self] route in
            self.arrivedAt = Date()
            if !self.navigation.isDemo { self.history.recordNavigation(distance: route.distance, settings: self.settings.history) }
            self.history.stop(settings: self.settings.history)
            self.location.setBackgroundUpdates(false)
            if self.navigation.isDemo { self.location.stopSimulation() }
            self.deviceTest.record("到着: \(route.destinationName)")
        }
        navigation.onStop = { [unowned self] in
            self.history.stop(settings: self.settings.history)
            self.location.setBackgroundUpdates(false)
            self.location.stopSimulation()
            self.refreshServices()
            self.updateIdleTimer()
        }
    }

    private func configureVisionCallbacks() {
        vision.onHazard = { [unowned self] h in
            self.history.logDetection(label: h.label, hazard: h.level, settings: self.settings.history)
            guard self.settings.detection.hazardAlertsEnabled, self.settings.detection.hasAcceptedDisclaimer else { return }
            self.alerts.post(HUDAlert(
                category: .hazard,
                title: "\(h.label.displayName)に注意（実験）",
                message: h.reason,
                priority: h.level == .high ? .critical : .important,
                duration: 3,
                dedupeKey: "hazard-\(h.trackID)",
                spokenText: "注意、\(h.label.displayName)"
            ))
        }
        vision.onNewDetections = { [unowned self] count in
            self.history.addDetections(count, settings: self.settings.history)
        }
        vision.onSign = { [unowned self] detection in
            let sign = detection.reading
            self.lastSign = sign
            guard sign.isImportant, self.settings.detection.readsSigns, self.settings.detection.hasAcceptedDisclaimer else { return }
            self.alerts.post(HUDAlert(
                category: .hazard,
                title: "標識：\(sign.kind)（実験）",
                message: sign.text,
                priority: .important,
                duration: 4,
                dedupeKey: "sign-\(sign.kind)",
                spokenText: "標識、\(sign.kind)"
            ))
        }
    }

    private func displayModeChanged(_ mode: DisplayOutputMode) {
        switch mode {
        case .independent:
            alerts.post(HUDAlert(category: .connection, title: "グラスに接続しました", message: "グラスに HUD、端末に操作画面を表示します。", priority: .normal, duration: 5))
            isHUDPresented = false
        case .mirror:
            alerts.post(HUDAlert(category: .connection, title: "グラスに接続しました（ミラー表示）", message: "端末の画面がそのまま映ります。", priority: .normal, duration: 5))
            if settings.autoStartHUDOnConnect || settings.displayOutput == .mirrorOnly { isHUDPresented = true }
        case .local:
            alerts.post(HUDAlert(category: .connection, title: "グラスとの接続が切れました", priority: .important, duration: 5))
            isDeviceScreenBlanked = false
        }
        updateDeviceScreenDimming()
        deviceTest.record("出力モード: \(mode.displayName)")
        refreshServices()
        updateIdleTimer()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        isInBackground = phase == .background
        if phase != .active { saveNow(); restoreDeviceScreenBrightness() }
        if phase == .active {
            device.refresh()
            camera.refreshAuthorization()
            Task { await importFromSyncFolderIfNewer() }
            updateDeviceScreenDimming()
        }
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        showsOnboarding = false
        location.requestPermission()
        alerts.requestNotificationPermission()
    }

    func showToast(_ text: String) {
        toast = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.toast == text { self?.toast = nil }
        }
    }

    func currentMetricSample() -> MetricSample {
        MetricSample(
            time: Date(),
            hudFPS: metrics.fps > 0 ? metrics.fps : nil,
            inferenceFPS: vision.isActive ? vision.inferenceFPS : nil,
            thermal: device.thermal.rawValue,
            batteryLevel: device.batteryLevel >= 0 ? device.batteryLevel : nil,
            horizontalAccuracy: location.lastSample?.horizontalAccuracy,
            memoryMB: device.memoryMB,
            externalDisplayConnected: display.isExternalConnected
        )
    }

    // MARK: - 元に戻す

    func pushUndo() {
        undoStack.append(layout)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        layout = previous
    }
}
