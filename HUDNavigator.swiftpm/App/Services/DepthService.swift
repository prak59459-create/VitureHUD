import Foundation
import Vision
import CoreML
import CoreVideo
import AVFoundation
import Observation

/// 画像（深さの地図）を小さな Float の配列にする
enum DepthBufferReader {
    /// pixel buffer（1 チャンネル：Float32 / Float16 / 8 ビット）を outW×outH に間引いて読む。
    /// rotation は画面の向きに合わせる回転（0・90・180・270 度、カメラの向き補正と同じ）
    static func sample(_ pb: CVPixelBuffer, outW: Int, outH: Int, rotation: Int = 0) -> [Float]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        let format = CVPixelBufferGetPixelFormatType(pb)
        var out = [Float](repeating: .nan, count: outW * outH)
        for oy in 0..<outH {
            for ox in 0..<outW {
                // 表示の座標 → 元の画像の座標
                let dx = (Double(ox) + 0.5) / Double(outW), dy = (Double(oy) + 0.5) / Double(outH)
                let (sx, sy): (Double, Double)
                switch rotation {
                case 90: (sx, sy) = (dy, 1 - dx)
                case 180: (sx, sy) = (1 - dx, 1 - dy)
                case 270: (sx, sy) = (1 - dy, dx)
                default: (sx, sy) = (dx, dy)
                }
                let x = min(w - 1, max(0, Int(sx * Double(w)))), y = min(h - 1, max(0, Int(sy * Double(h))))
                let row = base.advanced(by: y * rowBytes)
                let v: Float
                switch format {
                case kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32, kCVPixelFormatType_OneComponent32Float:
                    v = row.assumingMemoryBound(to: Float.self)[x]
                case kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_OneComponent16Half:
                    v = DepthMath.halfToFloat(row.assumingMemoryBound(to: UInt16.self)[x])
                case kCVPixelFormatType_OneComponent8:
                    v = Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255
                default:
                    return nil
                }
                out[oy * outW + ox] = v
            }
        }
        return out
    }
}

/// AI（Depth Anything V2）で 1 枚の画像から奥行きを推定する（専用キュー）
final class AIDepthEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hudnavigator.depth", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private var lastRun = Date.distantPast
    private var _model: VNCoreMLModel?
    private var _interval: TimeInterval = 0.25
    private var _runs = 0
    private var _lastError: String?

    /// 相対値（大きいほど近い）の配列 width×height
    var onResult: (@Sendable ([Float], Int, Int, Double) -> Void)?

    var model: VNCoreMLModel? {
        get { lock.lock(); defer { lock.unlock() }; return _model }
        set { lock.lock(); _model = newValue; lock.unlock() }
    }

    var interval: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return _interval }
        set { lock.lock(); _interval = newValue; lock.unlock() }
    }

    var stats: (runs: Int, error: String?) {
        lock.lock(); defer { lock.unlock() }; return (_runs, _lastError)
    }

    static let outW = 48, outH = 64

    func process(_ buffer: CVPixelBuffer) {
        let now = Date()
        lock.lock()
        guard let model = _model, !busy, now.timeIntervalSince(lastRun) >= _interval else { lock.unlock(); return }
        busy = true
        lastRun = now
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let start = Date()
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            var result: [Float]?
            var error: String?
            do {
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
                if let obs = request.results?.first as? VNPixelBufferObservation {
                    result = DepthBufferReader.sample(obs.pixelBuffer, outW: Self.outW, outH: Self.outH)
                    if result == nil { error = "深さの形式に対応していません" }
                } else {
                    error = "AI の結果がありません"
                }
            } catch let e {
                error = e.localizedDescription
            }
            let seconds = Date().timeIntervalSince(start)
            self.lock.lock()
            self.busy = false
            self._runs += 1
            self._lastError = error
            self.lock.unlock()
            if let result { self.onResult?(result, Self.outW, Self.outH, seconds) }
        }
    }
}

/// 距離（奥行き）。LiDAR・2 つのカメラ・AI 推定をまとめて「距離の格子」にする。
@MainActor
@Observable
final class DepthService {
    private(set) var grid: DepthGrid?
    private(set) var activeSource: DepthSourceKind?
    private(set) var obstacle: Obstacle?
    private(set) var status = ""
    private(set) var aiStatus = ""
    private(set) var lastUpdate: Date?
    private(set) var inferenceMs: Double = 0
    private(set) var isRunning = false

    @ObservationIgnored let ai = AIDepthEngine()
    @ObservationIgnored private var detector = ObstacleDetector()
    @ObservationIgnored private var settings = DepthSettings()
    @ObservationIgnored private var aiLoadTask: Task<Void, Never>?
    @ObservationIgnored private var aiLoaded = false
    @ObservationIgnored private var lastFit: (a: Double, b: Double)?
    /// カメラの下向きの角度（度）と縦の画角（AppModel が設定）
    @ObservationIgnored var geometry: (() -> (pitchDown: Double?, verticalFOV: Double))?
    @ObservationIgnored var onObstacle: ((Obstacle) -> Void)?

    static var hasLiDAR: Bool { AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil }
    static var hasDualCamera: Bool {
        AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) != nil
    }

    /// 実際に使う方法
    static func resolve(_ preferred: DepthSourceKind) -> DepthSourceKind {
        switch preferred {
        case .auto:
            if hasLiDAR { return .lidar }
            if hasDualCamera { return .dualCamera }
            return .aiMonocular
        case .lidar: return hasLiDAR ? .lidar : resolve(.auto)
        case .dualCamera: return hasDualCamera ? .dualCamera : .aiMonocular
        case .aiMonocular: return .aiMonocular
        }
    }

    init() {
        ai.onResult = { [weak self] values, w, h, seconds in
            Task { @MainActor in self?.handleAI(values, width: w, height: h, seconds: seconds) }
        }
    }

    /// 設定を反映し、カメラにつなぐ（つなぐ・外すは何度呼んでもよい）
    func attach(to camera: CameraController, settings: DepthSettings, enabled: Bool) {
        self.settings = settings
        detector.threshold = settings.obstacleDistance
        ai.interval = 1 / max(0.5, settings.aiFPS)
        guard enabled else {
            isRunning = false
            camera.pipeline.setFrameHandler(nil, for: "depth")
            camera.pipeline.setDepthHandler(nil)
            camera.setDepthSensor(nil)
            grid = nil
            obstacle = nil
            activeSource = nil
            status = "オフ"
            return
        }
        isRunning = true
        let source = Self.resolve(settings.source)
        activeSource = source
        switch source {
        case .lidar, .dualCamera:
            camera.pipeline.setFrameHandler(nil, for: "depth")
            camera.setDepthSensor(source)
            camera.pipeline.setDepthHandler { [weak self] values, w, h in
                Task { @MainActor in self?.handleSensor(values, width: w, height: h) }
            }
            status = source == .lidar ? "LiDAR で測定中" : "2 つのカメラの視差で測定中"
        default:
            camera.setDepthSensor(nil)
            camera.pipeline.setDepthHandler(nil)
            loadAIModelIfNeeded()
            let engine = ai
            camera.pipeline.setFrameHandler({ buffer in engine.process(buffer) }, for: "depth")
            status = "AI で推定中（地面の見え方で m に換算）"
        }
    }

    private func loadAIModelIfNeeded() {
        guard !aiLoaded, aiLoadTask == nil else { return }
        aiStatus = "AI の奥行きモデルを準備中…（初回は数十秒）"
        aiLoadTask = Task { [weak self] in
            do {
                let ml = try await ModelStore.load(named: "DepthAnythingV2SmallF16")
                let vn = try VNCoreMLModel(for: ml)
                vn.inputImageFeatureName = "image"
                self?.ai.model = vn
                self?.aiLoaded = true
                self?.aiStatus = "AI の奥行きモデル：準備完了"
            } catch {
                self?.aiStatus = "AI の奥行きモデルを読み込めません：\(error.localizedDescription)"
            }
            self?.aiLoadTask = nil
        }
    }

    private func handleAI(_ values: [Float], width: Int, height: Int, seconds: Double) {
        guard isRunning else { return }
        inferenceMs = seconds * 1000
        // 0〜1 にそろえる（AI の値の大きさは画像ごとに違うため）
        let finite = values.filter { $0.isFinite }
        guard let lo = finite.min(), let hi = finite.max(), hi > lo else { return }
        let normalized = values.map { ($0 - lo) / (hi - lo) }
        let relative = DepthMath.grid(from: normalized, width: width, height: height, columns: 16, rows: 20, isMetric: false)
        let geo = geometry?() ?? (pitchDown: nil, verticalFOV: 60)
        // 地面から m への換算を求める（前回の値となめらかにつなぐ）
        if let pitch = geo.pitchDown,
           let fit = GroundGeometry.fitAIToGround(relative, cameraPitchDown: pitch, verticalFOV: geo.verticalFOV, height: settings.cameraHeight) {
            if let last = lastFit {
                lastFit = (last.a * 0.6 + fit.a * 0.4, last.b * 0.6 + fit.b * 0.4)
            } else {
                lastFit = fit
            }
        }
        if let fit = lastFit {
            let metric = relative.values.map { v -> Float in
                guard v.isFinite, let m = DepthMath.metric(Double(v), fit: fit, maxRange: settings.maxRange) else { return .nan }
                return Float(m)
            }
            publish(DepthGrid(columns: relative.columns, rows: relative.rows, values: metric, isMetric: true), pitch: geo.pitchDown, fov: geo.verticalFOV)
        } else {
            // 傾きが分からない・地面が見えない：相対値のまま（近い・遠いだけ）
            publish(relative, pitch: geo.pitchDown, fov: geo.verticalFOV)
        }
    }

    private func handleSensor(_ values: [Float], width: Int, height: Int) {
        guard isRunning else { return }
        let clipped = values.map { $0 > 0 && $0 < Float(settings.maxRange) ? $0 : .nan }
        let g = DepthMath.grid(from: clipped, width: width, height: height, columns: 16, rows: 20, isMetric: true)
        let geo = geometry?() ?? (pitchDown: nil, verticalFOV: 60)
        publish(g, pitch: geo.pitchDown, fov: geo.verticalFOV)
    }

    private func publish(_ g: DepthGrid, pitch: Double?, fov: Double) {
        grid = g
        lastUpdate = Date()
        let o = detector.update(g, cameraPitchDown: pitch, verticalFOV: fov, height: settings.cameraHeight)
        obstacle = o
        if let o, settings.obstacleAlerts { onObstacle?(o) }
    }

    /// 枠（正規化座標）の中の距離（m）。測れていなければ nil
    func distance(for box: NormalizedRect) -> Double? {
        guard let g = grid, g.isMetric, isFresh, let v = g.median(in: box) else { return nil }
        return Double(v)
    }

    /// 画面中央の距離
    var centerDistance: Double? {
        distance(for: NormalizedRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1))
    }

    var isFresh: Bool { lastUpdate.map { Date().timeIntervalSince($0) < 2 } ?? false }

    var sourceLabel: String {
        guard let s = activeSource else { return "" }
        if s == .aiMonocular && !(grid?.isMetric ?? false) { return "AI（相対）" }
        return s.shortName
    }
}
