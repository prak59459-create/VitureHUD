import Foundation
import Vision
import CoreML
import CoreVideo
import Observation

/// Vision / Core ML の推論（専用キューで実行）。
final class DetectionEngine: @unchecked Sendable {
    struct Config: Sendable {
        var minInterval: TimeInterval = 0.125
        var detectPeople = true
        var detectAnimals = true
        var minimumConfidence = 0.5
        var useCustomModel = true
    }

    private let queue = DispatchQueue(label: "hudnavigator.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var lastRun = Date.distantPast
    private var _config = Config()
    private var customModel: VNCoreMLModel?

    var onResults: (@Sendable ([Detection], _ inferenceSeconds: Double) -> Void)?

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
        let cfg = _config
        let model = customModel
        guard !busy, now.timeIntervalSince(lastRun) >= cfg.minInterval else { lock.unlock(); return }
        busy = true
        lastRun = now
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let start = Date()
            let detections = Self.run(buffer: buffer, config: cfg, customModel: model, time: now)
            let elapsed = Date().timeIntervalSince(start)
            self.lock.lock(); self.busy = false; self.lock.unlock()
            self.onResults?(detections, elapsed)
        }
    }

    private static func run(buffer: CVPixelBuffer, config: Config, customModel: VNCoreMLModel?, time: Date) -> [Detection] {
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
        guard !requests.isEmpty else { return [] }
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do { try handler.perform(requests) } catch { return [] }

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
        return result
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
    private(set) var totalDetections = 0
    private(set) var isActive = false

    @ObservationIgnored let engine = DetectionEngine()
    @ObservationIgnored private var tracker = ObjectTracker()
    @ObservationIgnored private var evaluator = HazardEvaluator()
    @ObservationIgnored private var recentTimes: [Date] = []
    @ObservationIgnored var onHazard: ((HazardAssessment) -> Void)?
    @ObservationIgnored var onNewDetections: ((Int) -> Void)?

    var highestHazard: HazardLevel { hazards.map(\.level).max() ?? .none }

    init() {
        engine.onResults = { [weak self] detections, seconds in
            Task { @MainActor in self?.handle(detections, seconds: seconds) }
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
        engine.config = c
    }

    /// カメラのフレームを推論に回すかどうか
    func attach(to camera: CameraController, enabled: Bool) {
        isActive = enabled
        if enabled {
            let engine = self.engine
            camera.pipeline.frameHandler = { buffer in engine.process(buffer) }
        } else {
            camera.pipeline.frameHandler = nil
            detections = []
            hazards = []
            tracker.reset()
            inferenceFPS = 0
        }
    }

    private func handle(_ new: [Detection], seconds: Double) {
        guard isActive else { return }
        let now = Date()
        detections = tracker.update(new, at: now)
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
        do {
            let ml = try MLModel(contentsOf: compiledModelURL)
            engine.setCustomModel(try VNCoreMLModel(for: ml))
            customModelName = (try? String(contentsOf: modelNameURL, encoding: .utf8)) ?? "カスタムモデル"
        } catch {
            modelStatus = "保存済みモデルを読み込めません: \(error.localizedDescription)"
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
            let name = url.deletingPathExtension().lastPathComponent
            try? name.write(to: modelNameURL, atomically: true, encoding: .utf8)
            customModelName = name
            modelStatus = "「\(name)」を読み込みました。物体検出モデル（VNRecognizedObjectObservation を出力するもの）のみ使えます。"
        } catch {
            modelStatus = "モデルを読み込めません: \(error.localizedDescription)"
        }
    }

    func removeCustomModel() {
        engine.setCustomModel(nil)
        try? FileManager.default.removeItem(at: compiledModelURL)
        try? FileManager.default.removeItem(at: modelNameURL)
        customModelName = nil
        modelStatus = "カスタムモデルを削除しました"
    }
}
