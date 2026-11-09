import Foundation
import CoreMotion
import Observation

/// 加速度・ジャイロ・姿勢・移動状態・AirPods の頭の向き。
@MainActor
@Observable
final class MotionService {
    struct Attitude: Hashable {
        var pitch: Double
        var roll: Double
        var yaw: Double
    }

    private(set) var attitude: Attitude?
    /// 重力を除いた加速度の大きさ（G）
    private(set) var userAcceleration: Double = 0
    /// 加速度のばらつき（歩行判定用）
    private(set) var accelerationVariance: Double = 0
    private(set) var rotationRate: Double = 0
    private(set) var activity: MovementState = .unknown
    private(set) var isRunning = false
    private(set) var isActivityAvailable = CMMotionActivityManager.isActivityAvailable()
    private(set) var headphoneAttitude: Attitude?
    private(set) var isHeadphoneTracking = false
    private(set) var isShakeDetected = false

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let activityManager = CMMotionActivityManager()
    @ObservationIgnored private let headphoneManager = CMHeadphoneMotionManager()
    @ObservationIgnored private var recentAcceleration: [Double] = []
    @ObservationIgnored private var updateHz: Double = 30
    @ObservationIgnored private var lastShake: Date?

    var isDeviceMotionAvailable: Bool { manager.isDeviceMotionAvailable }
    var isHeadphoneMotionAvailable: Bool { headphoneManager.isDeviceMotionAvailable }

    func start(hz: Double) {
        updateHz = hz
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / max(1, hz)
        guard !isRunning else { return }
        isRunning = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let a = motion.userAcceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let r = motion.rotationRate
            let rotation = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let att = Attitude(
                pitch: motion.attitude.pitch * 180 / .pi,
                roll: motion.attitude.roll * 180 / .pi,
                yaw: motion.attitude.yaw * 180 / .pi
            )
            MainActor.assumeIsolated {
                self?.handle(attitude: att, acceleration: magnitude, rotation: rotation)
            }
        }
    }

    func updateRate(hz: Double) {
        updateHz = hz
        manager.deviceMotionUpdateInterval = 1.0 / max(1, hz)
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    func startActivity() {
        guard isActivityAvailable else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] a in
            guard let a else { return }
            let state: MovementState
            if a.automotive { state = .vehicle }
            else if a.cycling { state = .cycling }
            else if a.running { state = .running }
            else if a.walking { state = .walking }
            else if a.stationary { state = .stationary }
            else { state = .unknown }
            MainActor.assumeIsolated { self?.activity = state }
        }
    }

    func stopActivity() {
        activityManager.stopActivityUpdates()
    }

    func startHeadphoneTracking() {
        guard headphoneManager.isDeviceMotionAvailable, !isHeadphoneTracking else { return }
        isHeadphoneTracking = true
        headphoneManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let att = Attitude(
                pitch: motion.attitude.pitch * 180 / .pi,
                roll: motion.attitude.roll * 180 / .pi,
                yaw: motion.attitude.yaw * 180 / .pi
            )
            MainActor.assumeIsolated { self?.headphoneAttitude = att }
        }
    }

    func stopHeadphoneTracking() {
        guard isHeadphoneTracking else { return }
        headphoneManager.stopDeviceMotionUpdates()
        isHeadphoneTracking = false
        headphoneAttitude = nil
    }

    private func handle(attitude att: Attitude, acceleration: Double, rotation: Double) {
        attitude = att
        userAcceleration = acceleration
        rotationRate = rotation
        recentAcceleration.append(acceleration)
        let window = Int(max(10, updateHz * 2))
        if recentAcceleration.count > window { recentAcceleration.removeFirst(recentAcceleration.count - window) }
        let mean = recentAcceleration.reduce(0, +) / Double(recentAcceleration.count)
        accelerationVariance = recentAcceleration.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(recentAcceleration.count)
        // シェイク検出（HUD 操作の補助）
        if acceleration > 2.2 {
            let now = Date()
            if lastShake.map({ now.timeIntervalSince($0) > 1.5 }) ?? true {
                lastShake = now
                isShakeDetected = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self?.isShakeDetected = false
                }
            }
        }
    }
}
