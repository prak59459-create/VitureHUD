import Foundation
import Vision
import CoreML
import CoreVideo
import Observation

/// 標識・看板の文字の検出結果
struct SignDetection: Hashable, Sendable, Identifiable {
    var id = UUID()
    var reading: SignTextClassifier.SignReading
    var box: NormalizedRect
}

/// 路面・標識の解析結果（nil はその回に解析しなかったもの）
struct RoadResult: Sendable {
    var lanes: [LineSegment]?
    var signs: [SignDetection]?
}

/// Vision / Core ML の推論（専用キューで実行）。
final class DetectionEngine: @unchecked Sendable {
    /// 動作の記録（診断用）
    struct Stats: Sendable {
        var framesSeen = 0
        var framesRun = 0
        var lastCount = 0
        var lastError: String?
        var hasObjectModel = false
    }

    struct Config: Sendable {
        var minInterval: TimeInterval = 0.125
        var detectPeople = true
        var detectAnimals = true
        var minimumConfidence = 0.5
        var useCustomModel = true
        var detectsLanes = false
        var readsSigns = false
        /// 路面の線の解析間隔（重いので間引く）
        var laneInterval: TimeInterval = 0.5
        var signInterval: TimeInterval = 1.5
    }

    private let queue = DispatchQueue(label: "hudnavigator.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastRun = Date.distantPast
    private var _config = Config()
    private var customModel: VNCoreMLModel?
    private var lastLaneRun = Date.distantPast
    private var lastSignRun = Date.distantPast
    private var _stats = Stats()

    var stats: Stats {
        lock.lock(); defer { lock.unlock() }
        var s = _stats
        s.hasObjectModel = customModel != nil
        return s
    }

    var onResults: (@Sendable ([Detection], _ inferenceSeconds: Double) -> Void)?
    var onRoadResult: (@Sendable (RoadResult) -> Void)?

    var config: Config {
        get { lock.lock(); defer { lock.unlock() }; return _config }
        set { lock.lock(); _config = newValue; lock.unlock() }
    }

    func setCustomModel(_ model: VNCoreMLModel?) {
        lock.lock(); customModel = model; lock.unlock()
    }

    /// カメラの映像キューから呼ばれる。前の推論が終わっていない・間隔が短い場合は捨てる。
    func process(_ buffer: CVPixelBuffer) {
        let now = Date()
        lock.lock()
        _stats.framesSeen += 1
        let cfg = _config
        let model = customModel
        guard !busy, now.timeIntervalSince(lastRun) >= cfg.minInterval else { lock.unlock(); return }
        busy = true
        lastRun = now
        let doLanes = cfg.detectsLanes && now.timeIntervalSince(lastLaneRun) >= cfg.laneInterval
        let doSigns = cfg.readsSigns && now.timeIntervalSince(lastSignRun) >= cfg.signInterval
        if doLanes { lastLaneRun = now }
        if doSigns { lastSignRun = now }
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let start = Date()
            let (detections, error) = Self.run(buffer: buffer, config: cfg, customModel: model, time: now)
            let elapsed = Date().timeIntervalSince(start)
            var road = RoadResult()
            if doLanes { road.lanes = Self.detectLanes(buffer) }
            if doSigns { road.signs = Self.readSigns(buffer) }
            self.lock.lock()
            self.busy = false
            self._stats.framesRun += 1
            self._stats.lastCount = detections.count
            if let error { self._stats.lastError = error }
            self.lock.unlock()
            self.onResults?(detections, elapsed)
            if doLanes || doSigns { self.onRoadResult?(road) }
        }
    }

    /// 路面の線（白線・車線）の候補（実験）：輪郭検出 → まっすぐで斜めの線だけを残す
    private static func detectLanes(_ buffer: CVPixelBuffer) -> [LineSegment] {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.5
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 256
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let observation = request.results?.first else { return [] }
        var contours: [[HUDPoint]] = []
        let count = min(observation.contourCount, 400)
        for i in 0..<count {
            guard let contour = try? observation.contour(at: i), contour.pointCount >= 2 else { continue }
            let simplified = (try? contour.polygonApproximation(epsilon: 0.008)) ?? contour
            contours.append(simplified.normalizedPoints.map { HUDPoint(x: Double($0.x), y: 1 - Double($0.y)) })
        }
        return LaneLineFilter.lanes(from: contours)
    }

    /// 標識・看板の文字（実験）：日本語の文字認識 → 標識の種類を推定
    private static func readSigns(_ buffer: CVPixelBuffer) -> [SignDetection] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.03
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        var result: [SignDetection] = []
        for o in request.results ?? [] {
            guard let candidate = o.topCandidates(1).first, candidate.confidence >= 0.4,
                  let reading = SignTextClassifier.classify(candidate.string) else { continue }
            let bb = o.boundingBox
            result.append(SignDetection(reading: reading, box: NormalizedRect(x: Double(bb.minX), y: Double(1 - bb.maxY), width: Double(bb.width), height: Double(bb.height))))
        }
        return result
    }

    private static func run(buffer: CVPixelBuffer, config: Config, customModel: VNCoreMLModel?, time: Date) -> ([Detection], String?) {
        var requests: [VNRequest] = []
        let human = VNDetectHumanRectanglesRequest()
        human.upperBodyOnly = false
        let animal = VNRecognizeAnimalsRequest()
        var custom: VNCoreMLRequest?
        if config.detectPeople { requests.append(human) }
        if config.detectAnimals { requests.append(animal) }
        if config.useCustomModel, let customModel {
            let r = VNCoreMLRequest(model: customModel)
            r.imageCropAndScaleOption = .scaleFill
            custom = r
            requests.append(r)
        }
        guard !requests.isEmpty else { return ([], "認識する種類がすべてオフです") }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do { try handler.perform(requests) } catch { return ([], error.localizedDescription) }

        var result: [Detection] = []
        func box(_ bb: CGRect) -> NormalizedRect {
            NormalizedRect(x: Double(bb.minX), y: Double(1 - bb.maxY), width: Double(bb.width), height: Double(bb.height))
        }
        if config.detectPeople, let obs = human.results {
            for o in obs where Double(o.confidence) >= config.minimumConfidence {
                result.append(Detection(label: .person, rawLabel: "person", confidence: Double(o.confidence), box: box(o.boundingBox), timestamp: time))
            }
        }
        if config.detectAnimals, let obs = animal.results {
            for o in obs {
                guard let label = o.labels.first, Double(label.confidence) >= config.minimumConfidence else { continue }
                result.append(Detection(label: DetectionLabel.from(identifier: label.identifier), rawLabel: label.identifier, confidence: Double(label.confidence), box: box(o.boundingBox), timestamp: time))
            }
        }
        if let custom, let obs = custom.results as? [VNRecognizedObjectObservation] {
            for o in obs {
                guard let label = o.labels.first, Double(label.confidence) >= config.minimumConfidence else { continue }
                let mapped = DetectionLabel.from(identifier: label.identifier)
                // 内蔵の人物検出と重複する場合は内蔵側を優先
                if mapped == .person && config.detectPeople { continue }
                result.append(Detection(label: mapped, rawLabel: label.identifier, confidence: Double(label.confidence), box: box(o.boundingBox), timestamp: time))
            }
        }
        return (result, nil)
    }
}

/// 物体認識・危険検知（実験機能・安全装置ではない）。
@MainActor
@Observable
final class VisionModel {
    private(set) var detections: [Detection] = []
    private(set) var hazards: [HazardAssessment] = []
    private(set) var inferenceFPS: Double = 0
    private(set) var lastInferenceMs: Double = 0
    private(set) var customModelName: String?
    private(set) var modelStatus: String?
    /// 使っている物体検出モデルの状態（内蔵 YOLO の準備など）
    private(set) var objectModelStatus = ""
    @ObservationIgnored private var loadedObjectModel: String?
    @ObservationIgnored private var objectModelTask: Task<Void, Never>?
    private(set) var totalDetections = 0
    private(set) var isActive = false
    private(set) var lanes: [LineSegment] = []
    private(set) var signs: [SignDetection] = []
    @ObservationIgnored private var lastLaneUpdate = Date.distantPast
    @ObservationIgnored private var lastSignUpdate = Date.distantPast
    @ObservationIgnored var onSign: ((SignDetection) -> Void)?

    @ObservationIgnored let engine = DetectionEngine()
    @ObservationIgnored private var tracker = ObjectTracker()
    @ObservationIgnored private var evaluator = HazardEvaluator()
    @ObservationIgnored private var recentTimes: [Date] = []
    @ObservationIgnored var onHazard: ((HazardAssessment) -> Void)?
    /// 枠の中の距離（m）を測る（AppModel が距離の推定につなぐ）
    @ObservationIgnored var distanceProvider: ((NormalizedRect) -> Double?)?
    @ObservationIgnored var onNewDetections: ((Int) -> Void)?

    var highestHazard: HazardLevel { hazards.map(\.level).max() ?? .none }

    init() {
        engine.onResults = { [weak self] detections, seconds in
            Task { @MainActor in self?.handle(detections, seconds: seconds) }
        }
        engine.onRoadResult = { [weak self] road in
            Task { @MainActor in self?.handle(road) }
        }
        loadSavedModel()
    }

    func configure(settings: DetectionSettings, inferenceFPS: Double) {
        var c = DetectionEngine.Config()
        c.minInterval = 1.0 / max(0.5, min(inferenceFPS, settings.inferenceFPS))
        c.detectPeople = settings.detectsPeople
        c.detectAnimals = settings.detectsAnimals
        c.minimumConfidence = settings.minimumConfidence
        c.useCustomModel = settings.usesCustomModel
        selectObjectModel(settings.objectModel, enabled: settings.usesCustomModel && isActive)
        c.detectsLanes = settings.detectsLanes
        c.readsSigns = settings.readsSigns
        // 省電力のときは路面・文字の解析も間引く
        c.laneInterval = inferenceFPS < 4 ? 1.5 : 0.5
        c.signInterval = inferenceFPS < 4 ? 4 : 1.5
        engine.config = c
        if !settings.detectsLanes { lanes = [] }
        if !settings.readsSigns { signs = [] }
    }

    private func handle(_ road: RoadResult) {
        guard isActive else { return }
        let now = Date()
        if let l = road.lanes { lanes = l; lastLaneUpdate = now }
        if let s = road.signs {
            signs = s
            lastSignUpdate = now
            for sign in s where sign.reading.isImportant { onSign?(sign) }
        }
        // 古い結果は消す
        if now.timeIntervalSince(lastLaneUpdate) > 2 { lanes = [] }
        if now.timeIntervalSince(lastSignUpdate) > 5 { signs = [] }
    }

    /// カメラのフレームを推論に回すかどうか
    func attach(to camera: CameraController, enabled: Bool) {
        isActive = enabled
        if enabled {
            let engine = self.engine
            camera.pipeline.setFrameHandler({ buffer in engine.process(buffer) }, for: "vision")
        } else {
            camera.pipeline.setFrameHandler(nil, for: "vision")
            lanes = []
            signs = []
            detections = []
            hazards = []
            tracker.reset()
            inferenceFPS = 0
        }
    }

    private func handle(_ new: [Detection], seconds: Double) {
        guard isActive else { return }
        let now = Date()
        let measured = new.map { d -> Detection in
            var d = d
            d.measuredDistance = distanceProvider?(d.box)
            return d
        }
        detections = tracker.update(measured, at: now)
        hazards = evaluator.assess(tracker: tracker, now: now)
        lastInferenceMs = seconds * 1000
        totalDetections += new.count
        if !new.isEmpty { onNewDetections?(new.count) }
        recentTimes.append(now)
        recentTimes = recentTimes.filter { now.timeIntervalSince($0) <= 2 }
        inferenceFPS = Double(recentTimes.count) / 2
        if let top = hazards.first, top.level >= .medium { onHazard?(top) }
    }

    // MARK: - ユーザーが用意した Core ML モデル

    private var modelDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("HUDNavigator/Models", isDirectory: true)
    }

    private var compiledModelURL: URL { modelDirectory.appendingPathComponent("Custom.mlmodelc", isDirectory: true) }
    private var modelNameURL: URL { modelDirectory.appendingPathComponent("name.txt") }

    private func loadSavedModel() {
        guard FileManager.default.fileExists(atPath: compiledModelURL.path) else { return }
        customModelName = (try? String(contentsOf: modelNameURL, encoding: .utf8)) ?? "カスタムモデル"
    }

    /// 物体検出モデルを選ぶ（内蔵の YOLOv3 / 読み込んだモデル）。初回は端末でコンパイルする。
    func selectObjectModel(_ name: String, enabled: Bool) {
        guard enabled else {
            if loadedObjectModel != nil {
                objectModelTask?.cancel()
                engine.setCustomModel(nil)
                loadedObjectModel = nil
            }
            objectModelStatus = "物体検出モデルは使っていません（人・動物の内蔵検出のみ）"
            return
        }
        guard name != loadedObjectModel else { return }
        loadedObjectModel = name
        objectModelTask?.cancel()
        engine.setCustomModel(nil)
        if name == "custom" {
            do {
                let ml = try MLModel(contentsOf: compiledModelURL)
                engine.setCustomModel(try VNCoreMLModel(for: ml))
                objectModelStatus = "読み込んだモデル「\(customModelName ?? "")」を使用中"
            } catch {
                objectModelStatus = "読み込んだモデルを使えません：\(error.localizedDescription)"
                loadedObjectModel = nil
            }
            return
        }
        let display = BundledObjectModel(rawValue: name)?.displayName ?? name
        objectModelStatus = "「\(display)」を準備中…（初回は数十秒かかることがあります）"
        objectModelTask = Task { [weak self] in
            do {
                let ml = try await ModelStore.load(named: name)
                let vn = try VNCoreMLModel(for: ml)
                guard let self, !Task.isCancelled, self.loadedObjectModel == name else { return }
                self.engine.setCustomModel(vn)
                self.objectModelStatus = "「\(display)」で 80 種類を検出中"
            } catch {
                guard let self, self.loadedObjectModel == name else { return }
                self.objectModelStatus = "「\(display)」を読み込めません：\(error.localizedDescription)"
                self.loadedObjectModel = nil
            }
        }
    }

    /// .mlmodel ファイルを取り込み、端末上でコンパイルして使う（ライセンスはユーザーが確認する）。
    func importModel(from url: URL) async {
        modelStatus = "モデルをコンパイル中…"
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: url, to: temp)
            let compiled = try await MLModel.compileModel(at: temp)
            try? FileManager.default.removeItem(at: compiledModelURL)
            try FileManager.default.moveItem(at: compiled, to: compiledModelURL)
            let ml = try MLModel(contentsOf: compiledModelURL)
            let vn = try VNCoreMLModel(for: ml)
            engine.setCustomModel(vn)
            loadedObjectModel = "custom"
            let name = url.deletingPathExtension().lastPathComponent
            try? name.write(to: modelNameURL, atomically: true, encoding: .utf8)
            customModelName = name
            objectModelStatus = "読み込んだモデル「\(name)」を使用中"
            modelStatus = "「\(name)」を読み込みました。物体検出モデル（VNRecognizedObjectObservation を出力するもの）のみ使えます。"
        } catch {
            modelStatus = "モデルを読み込めません: \(error.localizedDescription)"
        }
    }

    func removeCustomModel() {
        if loadedObjectModel == "custom" {
            engine.setCustomModel(nil)
            loadedObjectModel = nil
        }
        try? FileManager.default.removeItem(at: compiledModelURL)
        try? FileManager.default.removeItem(at: modelNameURL)
        customModelName = nil
        modelStatus = "カスタムモデルを削除しました"
    }
}
