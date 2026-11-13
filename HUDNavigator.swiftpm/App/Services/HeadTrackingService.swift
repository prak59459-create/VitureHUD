import Foundation
import CoreBluetooth
import AVFoundation
import Vision
import Observation

// MARK: - Bluetooth の動きセンサー（WitMotion・自作 ESP32）

@MainActor
@Observable
final class BLEIMUService {
    struct FoundDevice: Identifiable, Hashable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    private(set) var state = "未接続"
    private(set) var found: [FoundDevice] = []
    private(set) var connectedName: String?
    private(set) var kind: String?
    private(set) var lastAcceleration: (x: Double, y: Double, z: Double)?

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private let delegate = BLEIMUDelegate()
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var connected: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    @ObservationIgnored private var active = false
    @ObservationIgnored var remembered: (() -> UUID?)?
    @ObservationIgnored var onConnected: ((UUID, String) -> Void)?
    @ObservationIgnored var onPose: ((HeadPose) -> Void)?

    static let witService = CBUUID(string: WitMotionBLE.serviceUUID)
    static let witNotify = CBUUID(string: WitMotionBLE.notifyUUID)
    static let witWrite = CBUUID(string: WitMotionBLE.writeUUID)
    static let diyService = CBUUID(string: HUDIMUBLE.serviceUUID)
    static let diyPose = CBUUID(string: HUDIMUBLE.poseUUID)

    func start() {
        guard !active else { return }
        active = true
        delegate.owner = self
        if central == nil {
            central = CBCentralManager(delegate: delegate, queue: .main)
        } else {
            reconnectOrScan()
        }
    }

    func stop() {
        guard active else { return }
        active = false
        central?.stopScan()
        if let p = connected { central?.cancelPeripheralConnection(p) }
        connected = nil
        connectedName = nil
        state = "停止"
    }

    func scan() {
        if !active { start() }
        found = []
        guard let central, central.state == .poweredOn else { return }
        state = "探しています…"
        // WitMotion は広告にサービス UUID を入れないことがあるので、全部探して名前で絞る
        central.scanForPeripherals(withServices: nil, options: nil)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, self.state == "探しています…" else { return }
            self.central?.stopScan()
            self.state = self.found.isEmpty ? "見つかりませんでした" : "選んでください"
        }
    }

    func connect(_ id: UUID) {
        guard let central, let p = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        peripherals[id] = p
        state = "\(p.name ?? "センサー") に接続中…"
        central.connect(p)
    }

    /// WitMotion の出力頻度を上げる（10Hz → 50Hz など）
    func setWitMotionRate(_ hz: Int) {
        guard let p = connected, let c = writeCharacteristic else { return }
        for cmd in WitMotionBLE.rateCommands(hz: hz) {
            p.writeValue(Data(cmd), for: c, type: .withoutResponse)
        }
        state = "出力を \(hz)Hz にしました（電源を切ると元に戻ります）"
    }

    private func reconnectOrScan() {
        guard active, let central, central.state == .poweredOn else { return }
        if let id = remembered?(), let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = p
            state = "\(p.name ?? "センサー") に接続中…"
            central.connect(p)
        } else {
            scan()
        }
    }

    fileprivate func stateChanged(_ s: CBManagerState) {
        switch s {
        case .poweredOn: state = "準備完了"; reconnectOrScan()
        case .poweredOff: state = "Bluetooth がオフです"
        case .unauthorized: state = "Bluetooth が許可されていません"
        case .unsupported: state = "この端末では使えません"
        default: break
        }
    }

    fileprivate func discovered(_ p: CBPeripheral, name: String?, services: [CBUUID], rssi: Int) {
        let n = name ?? p.name ?? ""
        let looksLikeIMU = services.contains(Self.witService) || services.contains(Self.diyService)
            || WitMotionBLE.namePrefixes.contains(where: { n.hasPrefix($0) }) || n.hasPrefix(HUDIMUBLE.namePrefix)
        guard looksLikeIMU else { return }
        peripherals[p.identifier] = p
        if !found.contains(where: { $0.id == p.identifier }) {
            found.append(FoundDevice(id: p.identifier, name: n.isEmpty ? "動きセンサー" : n, rssi: rssi))
        }
        if remembered?() == p.identifier { connect(p.identifier) }
    }

    fileprivate func didConnect(_ p: CBPeripheral) {
        connected = p
        p.delegate = delegate
        p.discoverServices([Self.witService, Self.diyService])
        let name = p.name ?? "動きセンサー"
        connectedName = name
        state = "\(name) に接続しました"
        onConnected?(p.identifier, name)
    }

    fileprivate func didDisconnect(_ p: CBPeripheral) {
        if connected?.identifier == p.identifier { connected = nil }
        connectedName = nil
        state = "切断されました"
        guard active else { return }
        central?.connect(p)
    }

    fileprivate func foundCharacteristic(_ c: CBCharacteristic, on p: CBPeripheral) {
        if c.uuid == Self.witNotify || c.uuid == Self.diyPose {
            p.setNotifyValue(true, for: c)
            kind = c.uuid == Self.witNotify ? "WitMotion" : "自作センサー"
        }
        if c.uuid == Self.witWrite { writeCharacteristic = c }
    }

    fileprivate func received(_ bytes: [UInt8], from uuid: CBUUID) {
        if uuid == Self.witNotify {
            for s in WitMotionBLE.parse(bytes) {
                lastAcceleration = (s.ax, s.ay, s.az)
                onPose?(WitMotionBLE.pose(s))
            }
        } else if uuid == Self.diyPose, let s = HUDIMUBLE.parse(bytes) {
            lastAcceleration = s.acceleration
            onPose?(s.pose)
        }
    }
}

private final class BLEIMUDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var owner: BLEIMUService?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        MainActor.assumeIsolated { owner?.stateChanged(s) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let rssi = RSSI.intValue
        MainActor.assumeIsolated { owner?.discovered(peripheral, name: name, services: services, rssi: rssi) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { owner?.didConnect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { owner?.didDisconnect(peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            MainActor.assumeIsolated { owner?.foundCharacteristic(c, on: peripheral) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        let uuid = characteristic.uuid
        MainActor.assumeIsolated { owner?.received(bytes, from: uuid) }
    }
}

// MARK: - VITURE 本体の USB センサー（実験）

/// IOKit の HID 機能を動的に読み込んで、VITURE のセンサーを直接読もうとする。
/// iOS は一般のアプリに USB 機器の直接操作を許可していないため、ほぼ確実に「許可されていない」で止まる。
/// 何が起きたかを記録し、診断として表示する。
final class GlassesUSBBridge {
    private(set) var log: [String] = []
    private(set) var packets = 0
    private(set) var lastHex: String?
    var onPose: ((HeadPose) -> Void)?
    var onLog: (() -> Void)?

    private typealias CreateFn = @convention(c) (UnsafeRawPointer?, UInt32) -> UnsafeMutableRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer?) -> Void
    private typealias OpenFn = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias CopyDevicesFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias GetPropertyFn = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> UnsafeMutableRawPointer?
    private typealias ReportCallback = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?, UInt32, UInt32, UnsafeMutablePointer<UInt8>, Int) -> Void
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>, Int, ReportCallback?, UnsafeMutableRawPointer?) -> Void
    private typealias ScheduleFn = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer, UnsafeRawPointer) -> Void
    private typealias SetReportFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Int, UnsafePointer<UInt8>, Int) -> Int32

    private var manager: UnsafeMutableRawPointer?
    private var buffers: [UnsafeMutablePointer<UInt8>] = []
    private var devices: [UnsafeMutableRawPointer] = []
    private var running = false

    private func note(_ s: String) {
        log.append("\(HUDFormat.clock(Date(), seconds: true)) \(s)")
        if log.count > 80 { log.removeFirst(log.count - 80) }
        onLog?()
    }

    func start() {
        guard !running else { return }
        running = true
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            note("IOKit を読み込めません")
            return
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(handle, name) else { note("\(name) が見つかりません"); return nil }
            return unsafeBitCast(p, to: type)
        }
        guard let create = sym("IOHIDManagerCreate", CreateFn.self),
              let setMatching = sym("IOHIDManagerSetDeviceMatching", SetMatchingFn.self),
              let open = sym("IOHIDManagerOpen", OpenFn.self),
              let copyDevices = sym("IOHIDManagerCopyDevices", CopyDevicesFn.self),
              let getProperty = sym("IOHIDDeviceGetProperty", GetPropertyFn.self),
              let deviceOpen = sym("IOHIDDeviceOpen", OpenFn.self),
              let register = sym("IOHIDDeviceRegisterInputReportCallback", RegisterFn.self),
              let schedule = sym("IOHIDDeviceScheduleWithRunLoop", ScheduleFn.self),
              let setReport = sym("IOHIDDeviceSetReport", SetReportFn.self)
        else { return }
        note("IOKit の HID 機能を読み込みました")
        guard let m = create(nil, 0) else { note("HID マネージャーを作れません"); return }
        manager = m
        let matching = ["VendorID": VitureHIDProtocol.vendorID] as NSDictionary
        setMatching(m, Unmanaged.passUnretained(matching).toOpaque())
        let r = open(m, 0)
        note("HID マネージャーを開く：\(Self.describe(r))")
        guard let setRaw = copyDevices(m) else {
            note("VITURE（ベンダー ID 0x35CA）の HID 機器が見えません。iOS がアプリに USB 機器を見せていない可能性が高いです。")
            return
        }
        let set = Unmanaged<CFSet>.fromOpaque(setRaw).takeRetainedValue() as NSSet
        note("見えた HID 機器：\(set.count) 台")
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: ReportCallback = { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            let bridge = Unmanaged<GlassesUSBBridge>.fromOpaque(ctx).takeUnretainedValue()
            bridge.received(Array(UnsafeBufferPointer(start: report, count: length)))
        }
        for case let obj as AnyObject in set {
            let dev = Unmanaged.passUnretained(obj).toOpaque()
            func prop(_ key: String) -> Any? {
                let k = key as NSString
                guard let v = getProperty(dev, Unmanaged.passUnretained(k).toOpaque()) else { return nil }
                return Unmanaged<AnyObject>.fromOpaque(v).takeUnretainedValue()
            }
            let product = prop("Product") as? String ?? "?"
            let pid = (prop("ProductID") as? NSNumber)?.intValue ?? 0
            let page = (prop("PrimaryUsagePage") as? NSNumber)?.intValue ?? 0
            let o = deviceOpen(dev, 0)
            note("\(product)（PID 0x\(String(pid, radix: 16))・用途 0x\(String(page, radix: 16))）を開く：\(Self.describe(o))")
            guard o == 0 else { continue }
            devices.append(dev)
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
            buffers.append(buf)
            register(dev, buf, 256, callback, context)
            let runLoop = Unmanaged.passUnretained(CFRunLoopGetMain()).toOpaque()
            let mode = Unmanaged.passUnretained(CFRunLoopMode.defaultMode.rawValue).toOpaque()
            schedule(dev, runLoop, mode)
            // IMU の送信開始（報告 ID 0xFF と 0 の両方を試す）
            let cmd = VitureHIDProtocol.setIMU(true)
            let s1 = cmd.withUnsafeBufferPointer { setReport(dev, 1, 0xFF, $0.baseAddress!, $0.count) }
            let s2 = cmd.withUnsafeBufferPointer { setReport(dev, 1, 0, $0.baseAddress!, $0.count) }
            note("IMU 開始の命令：\(Self.describe(s1)) / \(Self.describe(s2))")
        }
        if devices.isEmpty { note("開ける機器がありませんでした") }
    }

    func stop() {
        running = false
        // 機器の解放は行わない（iOS ではここまで来ない想定。アプリ終了時に解放される）
    }

    private func received(_ bytes: [UInt8]) {
        packets += 1
        lastHex = VitureHIDProtocol.hex(bytes)
        if let r = VitureHIDProtocol.parseIMU(bytes) {
            onPose?(VitureHIDProtocol.pose(r))
        } else if packets <= 5 {
            note("受信：\(lastHex ?? "")")
        }
    }

    static func describe(_ code: Int32) -> String {
        switch UInt32(bitPattern: code) {
        case 0: return "成功"
        case 0xE00002E2: return "許可されていません（kIOReturnNotPermitted）"
        case 0xE00002C1: return "権限がありません（kIOReturnNotPrivileged）"
        case 0xE00002C5: return "使用中（kIOReturnExclusiveAccess）"
        case 0xE00002C0: return "機器がありません（kIOReturnNoDevice）"
        default: return String(format: "エラー 0x%08X", UInt32(bitPattern: code))
        }
    }
}

// MARK: - 前面カメラで顔の向き

final class FaceHeadTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "hudnavigator.face.session")
    private let videoQueue = DispatchQueue(label: "hudnavigator.face.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let lock = NSLock()
    private var configured = false
    private var lastRun = Date.distantPast
    var onPose: (@Sendable (HeadPose?) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    func start() {
        sessionQueue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                      let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
                    session.commitConfiguration()
                    onError?("前面カメラを使えません")
                    return
                }
                session.addInput(input)
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: videoQueue)
                if session.canAddOutput(output) { session.addOutput(output) }
                if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        lock.lock()
        guard now.timeIntervalSince(lastRun) >= 1.0 / 15 else { lock.unlock(); return }
        lastRun = now
        lock.unlock()
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
        } catch {
            return
        }
        let face = (request.results ?? []).max { $0.boundingBox.width < $1.boundingBox.width }
        guard let face else { onPose?(nil); return }
        let yaw = (face.yaw?.doubleValue ?? 0) * 180 / .pi
        let pitch = (face.pitch?.doubleValue ?? 0) * 180 / .pi
        let roll = (face.roll?.doubleValue ?? 0) * 180 / .pi
        // 前面カメラは向かい合っているので左右を反転
        onPose?(HeadPose(yaw: -yaw, pitch: -pitch, roll: roll))
    }
}

// MARK: - まとめ役

@MainActor
@Observable
final class HeadTrackingService {
    /// 正面からのずれ（なめらかにしたもの）
    private(set) var pose: HeadPose?
    private(set) var rawPose: HeadPose?
    private(set) var isGlancing = false
    private(set) var lastGesture: HeadGesture?
    private(set) var lastGestureAt: Date?
    private(set) var status = "使っていません"
    private(set) var sampleRate: Double = 0
    private(set) var activeSource: HeadTrackingSource = .off
    private(set) var usbLog: [String] = []
    private(set) var usbPackets = 0

    let ble = BLEIMUService()
    @ObservationIgnored let usb = GlassesUSBBridge()
    let accessory = GlassesAccessoryProbe()
    @ObservationIgnored let face = FaceHeadTracker()
    @ObservationIgnored private var filter = HeadPoseFilter()
    @ObservationIgnored private var gestures = HeadGestureDetector()
    @ObservationIgnored private var glance = GlanceDetector()
    @ObservationIgnored private var settings = HeadTrackingSettings()
    @ObservationIgnored private var sampleTimes: [Date] = []
    @ObservationIgnored private weak var motion: MotionService?
    @ObservationIgnored private var lastSampleAt = Date.distantPast
    @ObservationIgnored var onGesture: ((HeadGesture) -> Void)?
    /// 背面カメラを使っているか（前面カメラと同時には使えない）
    @ObservationIgnored var isBackCameraBusy: (() -> Bool)?

    init() {
        usb.onPose = { [weak self] p in self?.ingest(p) }
        usb.onLog = { [weak self] in
            guard let self else { return }
            self.usbLog = self.usb.log
            self.usbPackets = self.usb.packets
        }
        ble.onPose = { [weak self] p in self?.ingest(p) }
        accessory.onPose = { [weak self] p in self?.ingest(p) }
        face.onPose = { [weak self] p in
            Task { @MainActor in
                guard let self, self.activeSource == .frontCamera else { return }
                if let p { self.ingest(p) } else { self.status = "顔が見つかりません（端末を顔の前に）" }
            }
        }
        face.onError = { [weak self] e in Task { @MainActor in self?.status = e } }
    }

    var isFresh: Bool { Date().timeIntervalSince(lastSampleAt) < 1.5 }

    /// 設定・使う・使わないを反映
    func configure(settings: HeadTrackingSettings, active: Bool, motion: MotionService) {
        self.settings = settings
        self.motion = motion
        glance.angle = settings.glanceAngle
        let next: HeadTrackingSource = active ? settings.source : .off
        guard next != activeSource else { return }
        stopSource(activeSource)
        activeSource = next
        filter.reset()
        gestures.reset()
        pose = nil
        rawPose = nil
        isGlancing = false
        startSource(next)
    }

    private func startSource(_ s: HeadTrackingSource) {
        switch s {
        case .off:
            status = "使っていません"
        case .airPods:
            guard let motion else { return }
            if !motion.isHeadphoneMotionAvailable { status = "AirPods（Pro・第3世代以降・Max）を接続してください" }
            else { status = "AirPods を待っています…" }
            motion.onHeadphoneAttitude = { [weak self] a in
                self?.ingest(HeadPose(yaw: -a.yaw, pitch: a.pitch, roll: a.roll))
            }
            motion.startHeadphoneTracking()
        case .device:
            status = "端末の向きを使っています"
            motion?.onDeviceAttitude = { [weak self] a in
                self?.ingest(HeadPose(yaw: -a.yaw, pitch: a.pitch, roll: a.roll))
            }
        case .bleSensor:
            status = "Bluetooth センサーを待っています…"
            ble.start()
        case .glassesUSB:
            status = "VITURE 本体に USB でつなごうとしています（実験）"
            usb.start()
            usbLog = usb.log
        case .glassesAccessory:
            status = "VITURE のアクセサリーからのデータを待っています…"
            accessory.start()
        case .frontCamera:
            if isBackCameraBusy?() == true {
                status = "背面カメラを使っている間は前面カメラを使えません（黒背景・物体認識オフで使えます）"
            } else {
                status = "前面カメラで顔を探しています…"
                face.start()
            }
        }
    }

    private func stopSource(_ s: HeadTrackingSource) {
        switch s {
        case .airPods:
            motion?.onHeadphoneAttitude = nil
            motion?.stopHeadphoneTracking()
        case .device:
            motion?.onDeviceAttitude = nil
        case .bleSensor:
            ble.stop()
        case .glassesUSB:
            usb.stop()
        case .glassesAccessory:
            accessory.stop()
        case .frontCamera:
            face.stop()
        case .off:
            break
        }
    }

    /// センサーから届いた向き
    func ingest(_ raw: HeadPose) {
        guard activeSource != .off else { return }
        let now = Date()
        lastSampleAt = now
        rawPose = raw
        let p = filter.update(raw: settings.adjusted(raw), smoothing: settings.smoothing)
        pose = p
        sampleTimes.append(now)
        sampleTimes.removeAll { now.timeIntervalSince($0) > 2 }
        sampleRate = Double(sampleTimes.count) / 2
        if status.hasSuffix("…") || status.hasPrefix("顔が") { status = "\(activeSource.displayName)：動作中" }
        if settings.gesturesEnabled, let g = gestures.add(p, at: now.timeIntervalSinceReferenceDate) {
            lastGesture = g
            lastGestureAt = now
            onGesture?(g)
        }
        if settings.glanceMode {
            let g = glance.update(pitch: p.pitch)
            if g != isGlancing { isGlancing = g }
        }
    }

    func recenter() {
        filter.recenter()
        gestures.reset()
        pose = rawPose == nil ? nil : .zero
    }
}
