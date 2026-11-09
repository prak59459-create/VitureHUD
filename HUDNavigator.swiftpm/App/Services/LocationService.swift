import Foundation
import CoreLocation
import Observation

extension GeoCoordinate {
    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension LocationSample {
    init(_ location: CLLocation) {
        self.init(
            coordinate: GeoCoordinate(location.coordinate),
            timestamp: location.timestamp,
            speed: location.speed,
            course: location.course,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil
        )
    }
}

enum LocationAuthorization: String {
    case notDetermined, denied, restricted, whenInUse, always

    var displayName: String {
        switch self {
        case .notDetermined: return "未確認"
        case .denied: return "許可されていません"
        case .restricted: return "制限されています"
        case .whenInUse: return "使用中のみ許可"
        case .always: return "常に許可"
        }
    }

    var isAuthorized: Bool { self == .whenInUse || self == .always }
}

/// 位置情報・方位。実際の GPS とシミュレーション再生（GPX / デモルート）を切り替えられる。
@MainActor
@Observable
final class LocationService {
    private(set) var lastSample: LocationSample?
    /// 方位（度）。真北が取れなければ磁北。
    private(set) var heading: Double?
    private(set) var headingAccuracy: Double?
    private(set) var authorization: LocationAuthorization = .notDetermined
    private(set) var isUpdating = false
    private(set) var isUpdatingHeading = false
    private(set) var isSimulating = false
    private(set) var simulationName: String?
    private(set) var placeName: String?
    private(set) var lastError: String?

    /// 新しい位置が来たときの通知（AppModel が受け取ってナビ・履歴・天気に配る）
    @ObservationIgnored var onSample: ((LocationSample) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let delegate = LocationDelegate()
    @ObservationIgnored private var simulationTask: Task<Void, Never>?
    @ObservationIgnored private var lastGeocoded: (coordinate: GeoCoordinate, date: Date)?
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var wantsBackground = false

    init() {
        manager.delegate = delegate
        manager.activityType = .fitness
        manager.distanceFilter = 2
        manager.headingFilter = 2
        delegate.owner = self
        updateAuthorization(manager.authorizationStatus)
    }

    var isAvailable: Bool { CLLocationManager.locationServicesEnabled() }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func setAccuracy(_ level: LocationAccuracyLevel) {
        switch level {
        case .best: manager.desiredAccuracy = kCLLocationAccuracyBest
        case .navigation: manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        case .tenMeters: manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case .hundredMeters: manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
    }

    func start() {
        requestPermission()
        guard !isUpdating else { return }
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stop() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    func startHeading() {
        guard CLLocationManager.headingAvailable(), !isUpdatingHeading else { return }
        manager.startUpdatingHeading()
        isUpdatingHeading = true
    }

    func stopHeading() {
        guard isUpdatingHeading else { return }
        manager.stopUpdatingHeading()
        isUpdatingHeading = false
    }

    /// ナビ中のバックグラウンド位置更新。正式アプリ（Info.plist に location がある場合）のみ有効。
    func setBackgroundUpdates(_ enabled: Bool) {
        wantsBackground = enabled
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        guard modes.contains("location") else { return }
        manager.allowsBackgroundLocationUpdates = enabled && authorization.isAuthorized
        manager.pausesLocationUpdatesAutomatically = !enabled
        manager.showsBackgroundLocationIndicator = enabled
    }

    // MARK: - シミュレーション

    func startSimulation(points: [GeoCoordinate], speed: Double, name: String) {
        stopSimulation()
        let track = SimulatedTrack(points: points, speed: speed)
        isSimulating = true
        simulationName = name
        let start = Date()
        simulationTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            while !Task.isCancelled {
                guard let sample = track.sample(at: elapsed, startDate: start) else { break }
                self?.deliver(sample)
                if sample.hasValidCourse { self?.heading = sample.course }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsed += 1
            }
            self?.isSimulating = false
            self?.simulationName = nil
        }
    }

    func startSimulation(gpx data: Data, name: String, speed: Double = 1.4) -> Bool {
        let points = GPX.parse(data).map(\.coordinate)
        guard points.count >= 2 else { return false }
        startSimulation(points: points, speed: speed, name: name)
        return true
    }

    func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        isSimulating = false
        simulationName = nil
    }

    // MARK: - デリゲートから

    fileprivate func handle(locations: [LocationSample]) {
        guard !isSimulating else { return }
        for s in locations { deliver(s) }
    }

    fileprivate func handle(heading value: Double, accuracy: Double) {
        guard !isSimulating else { return }
        heading = value
        headingAccuracy = accuracy
    }

    fileprivate func updateAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        case .restricted: authorization = .restricted
        case .authorizedWhenInUse: authorization = .whenInUse
        case .authorizedAlways: authorization = .always
        @unknown default: authorization = .notDetermined
        }
        if wantsBackground { setBackgroundUpdates(true) }
    }

    fileprivate func handle(error: String) {
        lastError = error
    }

    private func deliver(_ sample: LocationSample) {
        lastSample = sample
        lastError = nil
        onSample?(sample)
        reverseGeocodeIfNeeded(sample)
    }

    private func reverseGeocodeIfNeeded(_ sample: LocationSample) {
        if let last = lastGeocoded {
            let moved = Geo.distance(last.coordinate, sample.coordinate)
            let age = Date().timeIntervalSince(last.date)
            guard moved > 300 || age > 300 else { return }
        }
        guard !geocoder.isGeocoding else { return }
        lastGeocoded = (sample.coordinate, Date())
        let location = CLLocation(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude)
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja_JP")) { [weak self] placemarks, _ in
            let p = placemarks?.first
            let name = [p?.administrativeArea, p?.locality, p?.subLocality].compactMap { $0 }.joined()
            Task { @MainActor in
                if !name.isEmpty { self?.placeName = name }
            }
        }
    }
}

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    weak var owner: LocationService?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map(LocationSample.init)
        Task { @MainActor [weak self] in self?.owner?.handle(locations: samples) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor [weak self] in self?.owner?.handle(heading: value, accuracy: accuracy) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.owner?.updateAuthorization(status) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.owner?.handle(error: message) }
    }
}
