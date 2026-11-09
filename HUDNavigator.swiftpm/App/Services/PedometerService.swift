import Foundation
import CoreMotion
import Observation

/// 歩数・歩く速さ・上った階数・気圧（端末の加速度センサー・気圧計）
@MainActor
@Observable
final class PedometerService {
    private(set) var stepsToday: Int?
    private(set) var distanceToday: Double?
    /// 1 秒あたりの歩数
    private(set) var cadence: Double?
    private(set) var floorsUp: Int?
    /// 気圧（hPa）
    private(set) var pressure: Double?
    /// 開始してからの高さの変化（m）
    private(set) var relativeAltitude: Double?
    private(set) var status = ""
    private(set) var isRunning = false

    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let altimeter = CMAltimeter()

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if CMPedometer.isStepCountingAvailable() {
            let start = Calendar.current.startOfDay(for: Date())
            pedometer.startUpdates(from: start) { [weak self] data, error in
                let steps = data?.numberOfSteps.intValue
                let distance = data?.distance?.doubleValue
                let cadence = data?.currentCadence?.doubleValue
                let floors = data?.floorsAscended?.intValue
                let message = error?.localizedDescription
                Task { @MainActor in
                    guard let self else { return }
                    if let steps { self.stepsToday = steps }
                    if let distance { self.distanceToday = distance }
                    self.cadence = cadence
                    if let floors { self.floorsUp = floors }
                    if let message { self.status = "歩数を取得できません：\(message)" }
                }
            }
        } else {
            status = "この端末は歩数の計測に対応していません"
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                let p = data.pressure.doubleValue * 10
                let alt = data.relativeAltitude.doubleValue
                MainActor.assumeIsolated {
                    self?.pressure = p
                    self?.relativeAltitude = alt
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
}
