import SwiftUI
import AVFoundation
import Observation

/// AVCaptureSession を専用キューで動かす部分（MainActor から切り離す）。
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "hudnavigator.camera.session")
    private let videoQueue = DispatchQueue(label: "hudnavigator.camera.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
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

    /// これまでに届いたフレーム数（診断用）
    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }; return _frameCount
    }

    /// 接続されている外部カメラ（iPad の USB-C カメラ。iPhone では見つからない）
    static var externalCameras: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
    }

    private var usingExternal = false

    func configure(prefersUltraWide: Bool, useExternal: Bool = false, maxHeight: Int, fps: Int) {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            let external = useExternal ? Self.externalCameras.first : nil
            let preset: AVCaptureSession.Preset = maxHeight >= 1080 ? .hd1920x1080 : .hd1280x720
            session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .high
            if !configured || (device?.deviceType == .builtInUltraWideCamera) != prefersUltraWide || (external != nil) != usingExternal {
                for input in session.inputs { session.removeInput(input) }
                let preferred: AVCaptureDevice.DeviceType = prefersUltraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
                let camera = external
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
            setFrameRate(fps)
            session.commitConfiguration()
            publishFormat()
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
        let want = next != nil || headlessCount > 0
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
        pipeline.configure(prefersUltraWide: s.prefersUltraWide, useExternal: s.useExternalCamera, maxHeight: profile.maxHeight, fps: profile.fps)
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
