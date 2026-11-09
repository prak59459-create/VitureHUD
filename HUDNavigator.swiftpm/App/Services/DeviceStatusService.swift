import Foundation
import UIKit
import Observation

/// バッテリー・発熱・低電力モード・メモリ。
@MainActor
@Observable
final class DeviceStatusService {
    private(set) var batteryLevel: Double = -1
    private(set) var batteryState: UIDevice.BatteryState = .unknown
    private(set) var thermal: ThermalLevel = .nominal
    private(set) var isLowPowerMode = false
    private(set) var memoryMB: Double?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var memoryTimer: Timer?

    var isCharging: Bool { batteryState == .charging || batteryState == .full }

    var powerState: PowerState {
        PowerState(thermal: thermal, batteryLevel: batteryLevel, isCharging: isCharging, isLowPowerMode: isLowPowerMode)
    }

    var modelName: String { UIDevice.current.model }
    var systemVersion: String { "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)" }

    /// 端末の機種識別子（例: iPhone15,4）
    var hardwareIdentifier: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        return mirror.children.reduce(into: "") { result, element in
            if let value = element.value as? Int8, value != 0 { result.append(Character(UnicodeScalar(UInt8(bitPattern: value)))) }
        }
    }

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.memoryMB = DeviceStatusService.memoryFootprintMB() }
        }
    }

    func refresh() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level < 0 ? -1 : Double(level)
        batteryState = UIDevice.current.batteryState
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .nominal
        }
        memoryMB = Self.memoryFootprintMB()
    }

    nonisolated static func memoryFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }
}
