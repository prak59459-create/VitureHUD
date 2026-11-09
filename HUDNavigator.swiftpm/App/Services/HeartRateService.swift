import Foundation
import CoreBluetooth
import Observation

/// Bluetooth 心拍計（標準規格 Heart Rate Service）の接続と心拍数の受信。
@MainActor
@Observable
final class HeartRateService {
    enum State: Equatable {
        case off, unauthorized, unsupported, idle, scanning, connecting(String), connected(String)

        var displayName: String {
            switch self {
            case .off: return "Bluetooth がオフです"
            case .unauthorized: return "Bluetooth が許可されていません"
            case .unsupported: return "この端末では使えません"
            case .idle: return "未接続"
            case .scanning: return "心拍計を探しています…"
            case .connecting(let n): return "\(n) に接続中…"
            case .connected(let n): return "\(n) に接続中"
            }
        }
    }

    struct FoundDevice: Identifiable, Hashable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    private(set) var state: State = .idle
    private(set) var bpm: Int?
    private(set) var lastUpdate: Date?
    private(set) var found: [FoundDevice] = []

    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private let delegate = HeartRateDelegate()
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var connected: CBPeripheral?
    @ObservationIgnored private var wantsScan = false
    @ObservationIgnored private var active = false
    @ObservationIgnored var remembered: (() -> UUID?)?
    @ObservationIgnored var onConnected: ((UUID, String) -> Void)?

    static let service = CBUUID(string: HeartRateParser.serviceUUID)
    static let measurement = CBUUID(string: HeartRateParser.measurementUUID)

    var isFresh: Bool { lastUpdate.map { Date().timeIntervalSince($0) < 10 } ?? false }

    /// 有効にする（Bluetooth の許可ダイアログが出る）
    func start() {
        guard !active else { return }
        active = true
        delegate.owner = self
        if central == nil {
            central = CBCentralManager(delegate: delegate, queue: .main)
        } else {
            scanOrReconnect()
        }
    }

    func stop() {
        guard active else { return }
        active = false
        central?.stopScan()
        if let p = connected { central?.cancelPeripheralConnection(p) }
        connected = nil
        bpm = nil
        switch state {
        case .scanning, .connecting, .connected: state = .idle
        default: break
        }
        wantsScan = false
    }

    var isActive: Bool { active }

    func scan() {
        if !active { start() }
        wantsScan = true
        found = []
        guard let central, central.state == .poweredOn else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, self.state == .scanning else { return }
            self.central?.stopScan()
            self.state = .idle
        }
    }

    func connect(_ id: UUID) {
        guard let central, let p = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        central.stopScan()
        peripherals[id] = p
        state = .connecting(p.name ?? "心拍計")
        central.connect(p)
    }

    private func scanOrReconnect() {
        guard let central, central.state == .poweredOn else { return }
        if let id = remembered?(), let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = p
            state = .connecting(p.name ?? "心拍計")
            central.connect(p)
        } else if let p = central.retrieveConnectedPeripherals(withServices: [Self.service]).first {
            peripherals[p.identifier] = p
            state = .connecting(p.name ?? "心拍計")
            central.connect(p)
        } else {
            scan()
        }
    }

    // MARK: デリゲートから

    fileprivate func centralStateChanged(_ s: CBManagerState) {
        switch s {
        case .poweredOn:
            state = .idle
            if active { scanOrReconnect() }
        case .poweredOff: state = .off
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        default: break
        }
    }

    fileprivate func discovered(_ p: CBPeripheral, rssi: Int) {
        peripherals[p.identifier] = p
        let device = FoundDevice(id: p.identifier, name: p.name ?? "心拍計", rssi: rssi)
        if !found.contains(where: { $0.id == device.id }) { found.append(device) }
        // 前回の機器なら自動で接続
        if remembered?() == p.identifier { connect(p.identifier) }
    }

    fileprivate func didConnect(_ p: CBPeripheral) {
        connected = p
        p.delegate = delegate
        p.discoverServices([Self.service])
        let name = p.name ?? "心拍計"
        state = .connected(name)
        onConnected?(p.identifier, name)
    }

    fileprivate func didDisconnect(_ p: CBPeripheral) {
        if connected?.identifier == p.identifier { connected = nil }
        bpm = nil
        state = .idle
        guard active else { return }
        // 自動で再接続を試みる
        central?.connect(p)
        state = .connecting(p.name ?? "心拍計")
    }

    fileprivate func received(_ value: Int) {
        bpm = value
        lastUpdate = Date()
    }
}

private final class HeartRateDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var owner: HeartRateService?
    // デリゲートは MainActor の外から呼ばれるので、UUID はここで持つ
    private static let service = CBUUID(string: HeartRateParser.serviceUUID)
    private static let measurement = CBUUID(string: HeartRateParser.measurementUUID)

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        MainActor.assumeIsolated { owner?.centralStateChanged(s) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        MainActor.assumeIsolated { owner?.discovered(peripheral, rssi: rssi) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { owner?.didConnect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { owner?.didDisconnect(peripheral) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] where s.uuid == Self.service {
            peripheral.discoverCharacteristics([Self.measurement], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] where c.uuid == Self.measurement {
            peripheral.setNotifyValue(true, for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let bpm = HeartRateParser.bpm(from: [UInt8](data)) else { return }
        MainActor.assumeIsolated { owner?.received(bpm) }
    }
}
