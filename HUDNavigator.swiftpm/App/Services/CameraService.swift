import SwiftUI
import AVFoundation
import Observation

/// AVCaptureSession を専用キューで動かす部分（MainActor から切り離す）。
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "hudnavigator.camera.session")
    private let videoQueue = DispatchQueue(label: "hudnavigator.camera.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let depthQueue = DispatchQueue(label: "hudnavigator.camera.depth", qos: .utility)
    private var _depthHandler: (@Sendable ([Float], Int, Int) -> Void)?
    private var lastDepthDelivery = Date.distantPast
    /// 深さの地図の回転（接続で回転できない場合に読み取り時に回す）
    private var depthRotation = 0
    private var depthSensor: DepthSourceKind?
    private var device: AVCaptureDevice?
    private var configured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private let lock = NSLock()
    private var _frameHandlers: [String: @Sendable (CVPixelBuffer) -> Void] = [:]
    private var _frameCount = 0

    /// 映像の情報（横縦比・縦の画角・回転角）が変わったとき
    var onFormat: (@Sendable (_ aspect: Double, _ verticalFOV: Double, _ rotation: Double) -> Void)?
    var onRunningChange: (@Sendable (Bool, String?) -> Void)?

    /// フレームを受け取る処理（物体認識・距離推定など、複数を同時に登録できる）
    func setFrameHandler(_ handler: (@Sendable (CVPixelBuffer) -> Void)?, for key: String) {
        lock.lock(); _frameHandlers[key] = handler; lock.unlock()
    }

    /// 深さ（m）の受け取り先：値の配列・幅・高さ
    func setDepthHandler(_ handler: (@Sendable ([Float], Int, Int) -> Void)?) {
        lock.lock(); _depthHandler = handler; lock.unlock()
    }

    /// 深さを測れるカメラ（LiDAR・2 つのカメラ）
    static func depthDevice(for kind: DepthSourceKind?) -> AVCaptureDevice? {
        switch kind {
        case .lidar?: return AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
        case .dualCamera?:
            return AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
        default: return nil
        }
    }

    /// これまでに届いたフレーム数（診断用）
    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }; return _frameCount
    }

    /// 接続されている外部カメラ（iPad の USB-C カメラ。iPhone では見つからない）
    static var externalCameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
    }

    private var usingExternal = false

    func configure(prefersUltraWide: Bool, useExternal: Bool = false, maxHeight: Int, fps: Int, depthSensor wantedDepth: DepthSourceKind? = nil) {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            let external = useExternal ? Self.externalCameras.first : nil
            let depthCamera = external == nil ? Self.depthDevice(for: wantedDepth) : nil
            let preset: AVCaptureSession.Preset = maxHeight >= 1080 ? .hd1920x1080 : .hd1280x720
            if depthCamera == nil {
                session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high
            }
            let depthChanged = (depthCamera != nil) != (depthSensor != nil) || (depthCamera != nil && depthSensor != wantedDepth)
            if !configured || depthChanged || (depthCamera == nil && (device?.deviceType == .builtInUltraWideCamera) != prefersUltraWide) || (external != nil) != usingExternal {
                for input in session.inputs { session.removeInput(input) }
                let preferred: AVCaptureDevice.DeviceType = prefersUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
                let camera = external
                    ?? depthCamera
                    ?? AVCaptureDevice.default(preferred, for: .video, position: .back)
                    ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                usingExternal = external != nil
                guard let camera, let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
                    session.commitConfiguration()
                    onRunningChange?(false, "背面カメラを使用できません")
                    return
                }
                session.addInput(input)
                device = camera
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                    output.setSampleBufferDelegate(self, queue: videoQueue)
                    session.addOutput(output)
                }
                configured = true
                setupRotation(camera)
            }
            configureDepth(camera: depthCamera, kind: wantedDepth, maxHeight: maxHeight)
            setFrameRate(fps)
            session.commitConfiguration()
            publishFormat()
        }
    }

    /// LiDAR・2 つのカメラの深さを出す設定（sessionQueue で呼ぶ）
    private func configureDepth(camera: AVCaptureDevice?, kind: DepthSourceKind?, maxHeight: Int) {
        guard let camera, camera === device else {
            if session.outputs.contains(depthOutput) { session.removeOutput(depthOutput) }
            depthSensor = nil
            return
        }
        session.sessionPreset = .inputPriority
        func dims(_ f: AVCaptureDevice.Format) -> CMVideoDimensions { CMVideoFormatDescriptionGetDimensions(f.formatDescription) }
        let candidates = camera.formats.filter {
            !$0.supportedDepthDataFormats.isEmpty
                && CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        let fitting = candidates.filter { Int(dims($0).height) <= maxHeight }
        if let format = (fitting.isEmpty ? candidates : fitting).max(by: { dims($0).width < dims($1).width }) {
            let depthFormats = format.supportedDepthDataFormats.filter {
                let t = CMFormatDescriptionGetMediaSubType($0.formatDescription)
                return t == kCVPixelFormatType_DepthFloat16 || t == kCVPixelFormatType_DepthFloat32
            }
            do {
                try camera.lockForConfiguration()
                camera.activeFormat = format
                if let d = depthFormats.max(by: { dims($0).width < dims($1).width }) { camera.activeDepthDataFormat = d }
                camera.unlockForConfiguration()
            } catch {}
        }
        if !session.outputs.contains(depthOutput), session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            depthOutput.alwaysDiscardsLateDepthData = true
            depthOutput.setDelegate(self, callbackQueue: depthQueue)
        }
        depthSensor = kind
        let angle = output.connection(with: .video)?.videoRotationAngle ?? 90
        if let c = depthOutput.connection(with: .depthData), c.isVideoRotationAngleSupported(angle) {
            c.videoRotationAngle = angle
            depthRotation = 0
        } else {
            depthRotation = Int(angle.rounded())
        }
    }

    private func setupRotation(_ camera: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async {
                self?.applyRotation(angle)
                self?.publishFormat()
            }
        }
    }

    private func applyRotation(_ angle: CGFloat) {
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func setFrameRate(_ fps: Int) {
        guard let device else { return }
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard let range = ranges.first, Double(fps) >= range.minFrameRate, Double(fps) <= range.maxFrameRate else { return }
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
        } catch {}
    }

    private func publishFormat() {
        guard let device else { return }
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let hfov = Double(device.activeFormat.videoFieldOfView)
        let angle = Double(output.connection(with: .video)?.videoRotationAngle ?? 90)
        let rotated = abs(angle - 90) < 1 || abs(angle - 270) < 1
        let w = Double(max(dims.width, 1))
        let h = Double(max(dims.height, 1))
        let landscapeVFOV = 2 * atan(tan(hfov * .pi / 360) * h / w) * 180 / .pi
        let aspect = rotated ? h / w : w / h
        let vfov = rotated ? hfov : landscapeVFOV
        onFormat?(aspect, vfov, angle)
    }

    func start() {
        sessionQueue.async { [self] in
            guard configured, !session.isRunning else { return }
            session.startRunning()
            onRunningChange?(session.isRunning, session.isRunning ? nil : "カメラを開始できませんでした")
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
            onRunningChange?(false, nil)
        }
    }

    func setZoom(_ factor: Double) {
        sessionQueue.async { [self] in
            guard let device else { return }
            let maxZoom = min(Double(device.activeFormat.videoMaxZoomFactor), 6)
            let z = CGFloat(factor.clamped(to: 1...maxZoom))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = z
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func setExposureBias(_ bias: Double) {
        sessionQueue.async { [self] in
            guard let device else { return }
            let b = Float(bias).clamped(to: device.minExposureTargetBias...device.maxExposureTargetBias)
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(b, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// 深さの地図が届いた（10 回/秒まで）
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        let now = Date()
        lock.lock()
        let handler = _depthHandler
        let ready = now.timeIntervalSince(lastDepthDelivery) >= 0.1
        if ready { lastDepthDelivery = now }
        let rotation = depthRotation
        lock.unlock()
        guard let handler, ready else { return }
        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32 ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        guard let values = DepthBufferReader.sample(converted.depthDataMap, outW: 48, outH: 64, rotation: rotation) else { return }
        handler(values, 48, 64)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        _frameCount += 1
        let handlers = Array(_frameHandlers.values)
        lock.unlock()
        guard !handlers.isEmpty, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        for handler in handlers { handler(buffer) }
    }
}

/// カメラの状態（UI 用）。HUD の背景・ビジョン画面から「使いたい場所」を登録すると動く。
@MainActor
@Observable
final class CameraController {
    enum Authorization { case notDetermined, authorized, denied }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var isRunning = false
    private(set) var lastError: String?
    /// カメラ映像を表示する場所（同時に1か所）
    private(set) var activeSurface: HUDSurface?
    /// 映像の横縦比（幅/高さ、回転後）
    private(set) var imageAspect: Double = 9.0 / 16.0
    private(set) var verticalFieldOfView: Double = 60
    private(set) var rotationAngle: Double = 90
    private(set) var frameCounter = 0

    @ObservationIgnored let pipeline = CameraPipeline()
    @ObservationIgnored private var surfaces: [HUDSurface: Int] = [:]
    /// 映像を表示せずにカメラを動かす依頼の数（黒背景での物体認識・距離推定）
    private(set) var headlessCount = 0
    @ObservationIgnored private var wantsRunning = false
    /// 3D スキャン（ARKit）がカメラを使っている間は止める
    @ObservationIgnored private var suspendedForAR = false

    func setSuspendedForAR(_ suspended: Bool) {
        guard suspended != suspendedForAR else { return }
        suspendedForAR = suspended
        wantsRunning = false
        if suspended { pipeline.stop() }
        updateActiveSurface()
    }
    /// 深さを測るカメラ（nil は通常のカメラ）
    @ObservationIgnored private var depthSensor: DepthSourceKind?

    func setDepthSensor(_ kind: DepthSourceKind?) {
        guard kind != depthSensor else { return }
        depthSensor = kind
        if wantsRunning { configureAndStart() }
    }
    @ObservationIgnored private var profile = (fps: 30, maxHeight: 1080)
    @ObservationIgnored var settingsProvider: (() -> CameraSettings)?

    init() {
        pipeline.onFormat = { [weak self] aspect, vfov, rotation in
            Task { @MainActor in
                self?.imageAspect = aspect
                self?.verticalFieldOfView = vfov
                self?.rotationAngle = rotation
            }
        }
        pipeline.onRunningChange = { [weak self] running, error in
            Task { @MainActor in
                self?.isRunning = running
                if let error { self?.lastError = error }
            }
        }
        refreshAuthorization()
    }

    var isInUse: Bool { activeSurface != nil || headlessCount > 0 }

    /// 映像を出さずにカメラを使う（グラスの黒背景のまま認識するとき）
    func acquireHeadless() {
        headlessCount += 1
        updateActiveSurface()
    }

    func releaseHeadless() {
        headlessCount = max(0, headlessCount - 1)
        updateActiveSurface()
    }

    func refreshAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorization = .authorized
        case .notDetermined: authorization = .notDetermined
        default: authorization = .denied
        }
    }

    /// 表示する場所を登録（画面が現れたとき）
    func acquire(_ surface: HUDSurface) {
        surfaces[surface, default: 0] += 1
        updateActiveSurface()
    }

    /// 登録を解除（画面が消えたとき）
    func release(_ surface: HUDSurface) {
        guard let count = surfaces[surface] else { return }
        if count <= 1 { surfaces[surface] = nil } else { surfaces[surface] = count - 1 }
        updateActiveSurface()
    }

    func applyPowerProfile(fps: Int, maxHeight: Int) {
        guard profile.fps != fps || profile.maxHeight != maxHeight else { return }
        profile = (fps, maxHeight)
        if isRunning || wantsRunning { configureAndStart() }
    }

    func applySettings() {
        let s = settingsProvider?() ?? CameraSettings()
        pipeline.setZoom(s.zoom)
        pipeline.setExposureBias(s.exposureBias)
    }

    private func updateActiveSurface() {
        let next = surfaces.keys.filter { $0 != .thumbnail }.max { $0.cameraPriority < $1.cameraPriority }
        if next != activeSurface { activeSurface = next }
        let want = !suspendedForAR && (next != nil || headlessCount > 0)
        guard want != wantsRunning else { return }
        wantsRunning = want
        if want {
            Task { await startIfAllowed() }
        } else {
            pipeline.stop()
        }
    }

    private func startIfAllowed() async {
        refreshAuthorization()
        if authorization == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        }
        guard authorization == .authorized else {
            lastError = "カメラが許可されていません（設定アプリで許可してください）"
            return
        }
        guard wantsRunning else { return }
        configureAndStart()
    }

    private func configureAndStart() {
        let s = settingsProvider?() ?? CameraSettings()
        lastError = nil
        pipeline.configure(prefersUltraWide: s.prefersUltraWide, useExternal: s.useExternalCamera, maxHeight: profile.maxHeight, fps: profile.fps, depthSensor: depthSensor)
        pipeline.start()
        pipeline.setZoom(s.zoom)
        pipeline.setExposureBias(s.exposureBias)
    }

    /// 設定変更（超広角の切り替えなど）を反映
    func reconfigure() {
        guard wantsRunning else { return }
        configureAndStart()
    }
}

/// カメラのプレビュー（AVCaptureVideoPreviewLayer）。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var isActive: Bool
    var rotationAngle: Double

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        let layer = view.previewLayer
        if isActive {
            if layer.session !== session { layer.session = session }
        } else if layer.session != nil {
            layer.session = nil
        }
        let angle = CGFloat(rotationAngle)
        if let connection = layer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    static func dismantleUIView(_ view: PreviewUIView, coordinator: ()) {
        view.previewLayer.session = nil
    }
}
