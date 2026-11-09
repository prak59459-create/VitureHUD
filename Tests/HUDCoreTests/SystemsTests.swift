import XCTest
@testable import HUDCore

final class HazardTests: XCTestCase {
    func det(_ label: DetectionLabel, _ box: NormalizedRect, _ t: Date, confidence: Double = 0.9) -> Detection {
        Detection(label: label, confidence: confidence, box: box, timestamp: t)
    }

    func testTrackerKeepsIDs() {
        var tracker = ObjectTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        let a = tracker.update([det(.car, NormalizedRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1), t0)], at: t0)
        let b = tracker.update([det(.car, NormalizedRect(x: 0.41, y: 0.4, width: 0.1, height: 0.1), t0.addingTimeInterval(0.1))], at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(a[0].trackID, b[0].trackID)
        // 種類が違えば別の追跡
        let c = tracker.update([det(.person, NormalizedRect(x: 0.41, y: 0.4, width: 0.1, height: 0.1), t0.addingTimeInterval(0.2))], at: t0.addingTimeInterval(0.2))
        XCTAssertNotEqual(c[0].trackID, a[0].trackID)
        // 古い追跡は消える
        _ = tracker.update([], at: t0.addingTimeInterval(5))
        XCTAssertTrue(tracker.tracks.isEmpty)
    }

    func testApproachingCarIsHighHazard() {
        var tracker = ObjectTracker()
        let evaluator = HazardEvaluator()
        let t0 = Date(timeIntervalSince1970: 0)
        // 中央で急速に大きくなる（接近）
        var size = 0.08
        var now = t0
        for i in 0..<6 {
            now = t0.addingTimeInterval(Double(i) * 0.1)
            _ = tracker.update([det(.car, NormalizedRect(x: 0.5 - size / 2, y: 0.55 - size / 2, width: size, height: size), now)], at: now)
            size *= 1.18
        }
        let result = evaluator.assess(tracker: tracker, now: now)
        XCTAssertEqual(result.first?.level, .high, "\(result)")
        XCTAssertNotNil(result.first?.timeToContact)
    }

    func testStaticOrSideObjectsAreNotHazards() {
        var tracker = ObjectTracker()
        let evaluator = HazardEvaluator()
        let t0 = Date(timeIntervalSince1970: 0)
        var now = t0
        for i in 0..<6 {
            now = t0.addingTimeInterval(Double(i) * 0.1)
            _ = tracker.update([
                det(.car, NormalizedRect(x: 0.45, y: 0.5, width: 0.08, height: 0.08), now), // 静止
                det(.stopSign, NormalizedRect(x: 0.45, y: 0.1, width: 0.1, height: 0.1), now), // 動かない物
            ], at: now)
        }
        XCTAssertTrue(evaluator.assess(tracker: tracker, now: now).isEmpty)
    }

    func testPersonApproachingIsCappedAtMedium() {
        var tracker = ObjectTracker()
        let evaluator = HazardEvaluator()
        let t0 = Date(timeIntervalSince1970: 0)
        var size = 0.08
        var now = t0
        for i in 0..<6 {
            now = t0.addingTimeInterval(Double(i) * 0.1)
            _ = tracker.update([det(.person, NormalizedRect(x: 0.5 - size / 2, y: 0.55 - size / 2, width: size, height: size), now)], at: now)
            size *= 1.2
        }
        XCTAssertEqual(evaluator.assess(tracker: tracker, now: now).first?.level, .medium)
    }

    func testDistanceEstimateIsRoughAndGuarded() {
        let d = Detection(label: .person, confidence: 0.9, box: NormalizedRect(x: 0.4, y: 0.3, width: 0.1, height: 0.3), timestamp: Date())
        let dist = d.approximateDistance(verticalFieldOfViewDegrees: 60)
        XCTAssertNotNil(dist)
        XCTAssertEqual(dist!, 1.65 / (2 * tan(30 * Double.pi / 180) * 0.3), accuracy: 0.01)
        // 画面端で切れている枠は推定しない
        let cut = Detection(label: .person, confidence: 0.9, box: NormalizedRect(x: 0.4, y: 0.0, width: 0.1, height: 0.5), timestamp: Date())
        XCTAssertNil(cut.approximateDistance(verticalFieldOfViewDegrees: 60))
        XCTAssertNil(Detection(label: .other, confidence: 1, box: NormalizedRect(x: 0.4, y: 0.3, width: 0.1, height: 0.3), timestamp: Date()).approximateDistance(verticalFieldOfViewDegrees: 60))
    }

    func testLabelMapping() {
        XCTAssertEqual(DetectionLabel.from(identifier: "Person"), .person)
        XCTAssertEqual(DetectionLabel.from(identifier: "motorbike"), .motorcycle)
        XCTAssertEqual(DetectionLabel.from(identifier: "Dog"), .dog)
        XCTAssertEqual(DetectionLabel.from(identifier: "traffic light"), .trafficLight)
        XCTAssertEqual(DetectionLabel.from(identifier: "toaster"), .other)
    }
}

final class AlertPolicyTests: XCTestCase {
    func testCooldownAndHazardFastRepeat() {
        var policy = AlertPolicy(settings: NotificationSettings())
        let t0 = Date(timeIntervalSince1970: 0)
        let battery = HUDAlert(category: .battery, title: "残量20%", priority: .important, createdAt: t0)
        XCTAssertTrue(policy.decide(battery, now: t0, isMoving: false).showBanner)
        XCTAssertTrue(policy.decide(battery, now: t0.addingTimeInterval(5), isMoving: false).isSuppressed)
        XCTAssertFalse(policy.decide(battery, now: t0.addingTimeInterval(30), isMoving: false).isSuppressed)

        let hazard = HUDAlert(category: .hazard, title: "接近", priority: .critical, createdAt: t0)
        XCTAssertTrue(policy.decide(hazard, now: t0, isMoving: true).speak)
        XCTAssertFalse(policy.decide(hazard, now: t0.addingTimeInterval(4), isMoving: true).isSuppressed)
    }

    func testInfoBannersHiddenWhileMoving() {
        var settings = NotificationSettings()
        settings.channels[.nearby] = AlertChannelSettings(showsBanner: true, speaks: false, playsSound: true)
        var policy = AlertPolicy(settings: settings)
        let a = HUDAlert(category: .nearby, title: "近くにカフェ", priority: .info)
        let d = policy.decide(a, now: Date(), isMoving: true)
        XCTAssertFalse(d.showBanner)
        XCTAssertFalse(d.playSound)
    }

    func testDisplayQueueOrdering() {
        let t0 = Date(timeIntervalSince1970: 100)
        let alerts = [
            HUDAlert(category: .weather, title: "a", priority: .info, createdAt: t0),
            HUDAlert(category: .hazard, title: "b", priority: .critical, createdAt: t0),
            HUDAlert(category: .battery, title: "c", priority: .important, createdAt: t0.addingTimeInterval(1)),
            HUDAlert(category: .system, title: "old", priority: .critical, createdAt: t0.addingTimeInterval(-100), duration: 5),
        ]
        let q = AlertPolicy.displayQueue(alerts, now: t0.addingTimeInterval(2))
        XCTAssertEqual(q.map(\.title), ["b", "c", "a"])
    }
}

final class PowerPolicyTests: XCTestCase {
    func testQualityLevels() {
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(), automatic: true), .normal)
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(thermal: .fair), automatic: true), .saver)
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(thermal: .serious), automatic: true), .critical)
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(batteryLevel: 0.2), automatic: true), .saver)
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(batteryLevel: 0.05), automatic: true), .critical)
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(batteryLevel: 0.05, isCharging: true), automatic: true), .normal)
        XCTAssertEqual(PowerPolicy.quality(for: PowerState(thermal: .critical), automatic: false), .normal)
    }

    func testProfilesReduceLoad() {
        let n = PowerPolicy.profile(for: PowerState())
        let s = PowerPolicy.profile(for: PowerState(thermal: .fair))
        let c = PowerPolicy.profile(for: PowerState(thermal: .serious))
        XCTAssertGreaterThan(n.inferenceFPS, s.inferenceFPS)
        XCTAssertGreaterThan(s.inferenceFPS, c.inferenceFPS)
        XCTAssertGreaterThan(n.motionHz, c.motionHz)
        XCTAssertNotNil(c.suggestion)
        XCTAssertNil(n.suggestion)
    }

    func testMovementAndVehicleGuard() {
        XCTAssertEqual(MovementState.estimate(speed: 0.1, accelerationVariance: 0.001), .stationary)
        XCTAssertEqual(MovementState.estimate(speed: 1.3, accelerationVariance: nil), .walking)
        XCTAssertEqual(MovementState.estimate(speed: 12, accelerationVariance: nil), .vehicle)
        var guardian = VehicleSpeedGuard()
        let t0 = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(guardian.update(speed: 10, at: t0))
        XCTAssertFalse(guardian.update(speed: 10, at: t0.addingTimeInterval(5)))
        XCTAssertTrue(guardian.update(speed: 10, at: t0.addingTimeInterval(16)))
        XCTAssertFalse(guardian.update(speed: 1, at: t0.addingTimeInterval(17)))
    }
}

final class HistoryTests: XCTestCase {
    func testTripRecorderFiltersJumpsAndJitter() {
        var recorder = TripRecorder(keepsPoints: true)
        let t0 = Date(timeIntervalSince1970: 0)
        recorder.start(at: t0)
        let a = GeoCoordinate(latitude: 35, longitude: 139)
        recorder.add(LocationSample(coordinate: a, timestamp: t0, speed: 1.3, horizontalAccuracy: 5))
        // 正常に 100m 移動
        let b = Geo.destination(from: a, bearing: 0, distance: 100)
        recorder.add(LocationSample(coordinate: b, timestamp: t0.addingTimeInterval(75), speed: 1.3, horizontalAccuracy: 5))
        // GPS の飛び（1秒で 1km）
        let jump = Geo.destination(from: b, bearing: 90, distance: 1000)
        recorder.add(LocationSample(coordinate: jump, timestamp: t0.addingTimeInterval(76), speed: 1.3, horizontalAccuracy: 5))
        // 精度の悪いサンプル
        recorder.add(LocationSample(coordinate: jump, timestamp: t0.addingTimeInterval(80), horizontalAccuracy: 200))
        let trip = recorder.finish(at: t0.addingTimeInterval(80), destinationName: "x", transport: .walking)
        XCTAssertNotNil(trip)
        XCTAssertEqual(trip!.distance, 100, accuracy: 1)
        XCTAssertEqual(trip!.averageSpeed, 100 / 75, accuracy: 0.05)
        XCTAssertEqual(trip!.points.count, 2)
    }

    func testBucketsAndPrune() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_762_614_000) // 2025-11-09 00:00 JST
        let trips = [
            TripRecord(startedAt: base.addingTimeInterval(3600), endedAt: base.addingTimeInterval(4200), distance: 800, averageSpeed: 1.3, maxSpeed: 2),
            TripRecord(startedAt: base.addingTimeInterval(7200), endedAt: base.addingTimeInterval(7800), distance: 700, averageSpeed: 1.2, maxSpeed: 1.8),
            TripRecord(startedAt: base.addingTimeInterval(day + 3600), endedAt: base.addingTimeInterval(day + 4200), distance: 500, averageSpeed: 1.0, maxSpeed: 1.5),
        ]
        let daily = HistoryStats.buckets(trips, period: .day, calendar: cal)
        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily[0].distance, 1500, accuracy: 1e-9)
        XCTAssertEqual(daily[0].tripCount, 2)
        let monthly = HistoryStats.buckets(trips, period: .month, calendar: cal)
        XCTAssertEqual(monthly.count, 1)
        let pruned = HistoryStats.pruned(trips, retentionDays: 1, now: base.addingTimeInterval(day * 1.5))
        XCTAssertEqual(pruned.count, 1)
        XCTAssertFalse(HistoryStats.summaryText(trips, calendar: cal).contains("35."), "要約に座標を含めない")
    }
}

final class WeatherTests: XCTestCase {
    func testParseForecastAndAir() throws {
        let forecast = """
        {"utc_offset_seconds":32400,"current":{"time":"2026-11-09T14:00","temperature_2m":17.4,"apparent_temperature":16.0,"relative_humidity_2m":55,"precipitation":0.0,"weather_code":2,"wind_speed_10m":3.2,"wind_direction_10m":200,"is_day":1,"uv_index":2.5},
         "hourly":{"time":["2026-11-09T14:00"],"precipitation_probability":[20]}}
        """
        let s = try OpenMeteo.parseForecast(Data(forecast.utf8), fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(s.temperature, 17.4)
        XCTAssertEqual(s.precipitationProbability, 20)
        XCTAssertEqual(s.conditionText, "一部くもり")
        XCTAssertEqual(s.windDirectionName, "南")
        XCTAssertNotNil(s.observationTime)
        XCTAssertTrue(s.spokenSummary.contains("Open-Meteo"))
        let air = #"{"current":{"pm2_5":8.1,"pm10":12,"european_aqi":25}}"#
        let merged = try OpenMeteo.mergeAirQuality(Data(air.utf8), into: s)
        XCTAssertEqual(merged.pm25, 8.1)
        XCTAssertEqual(merged.airQualityText, "普通")
    }

    func testMissingValuesStayNil() throws {
        let s = try OpenMeteo.parseForecast(Data(#"{"current":{}}"#.utf8), fetchedAt: Date())
        XCTAssertNil(s.temperature)
        XCTAssertEqual(s.conditionText, "不明")
    }

    func testURLsRoundCoordinates() {
        let url = OpenMeteo.forecastURL(for: GeoCoordinate(latitude: 35.681236, longitude: 139.767125))!.absoluteString
        XCTAssertTrue(url.contains("latitude=35.681"))
        XCTAssertFalse(url.contains("35.681236"), "送信する座標は丸める")
    }
}

final class StorageTests: XCTestCase {
    func testJSONFileStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = JSONFileStore(directory: dir)
        let themes = BuiltInContent.themes
        try store.save(themes, as: "themes")
        XCTAssertEqual(store.load([Theme].self, from: "themes"), themes)
        store.delete("themes")
        XCTAssertNil(store.load([Theme].self, from: "themes"))
        try store.save(["a": 1], as: "x")
        store.deleteAll()
        XCTAssertNil(store.loadData("x"))
    }

    func testDeviceReportRoundsCoordinates() throws {
        XCTAssertEqual(DeviceTestReport.roundCoordinates("loc 35.681236, 139.767125 acc 5.0"), "loc 35.681, 139.767 acc 5.0")
        let report = DeviceTestReport(appVersion: "1", buildNumber: "1", environment: .playgrounds, deviceModel: "iPad", systemVersion: "26", externalDisplay: nil, createdAt: Date(), entries: [ChecklistEntry(itemID: "S0-1", result: .pass)], metrics: [], log: ["at 35.681236,139.767125"])
        let data = try report.exportData(roundLocations: true)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("35.681236"))
        XCTAssertEqual(report.summary.pass, 1)
    }

    func testChecklistCoversAllPhases() {
        let phases = Set(DeviceChecklist.items.map(\.phase))
        XCTAssertEqual(phases, Set(0...7))
        XCTAssertEqual(Set(DeviceChecklist.items.map(\.id)).count, DeviceChecklist.items.count)
        XCTAssertFalse(DeviceChecklist.items(for: .playgrounds).contains { $0.id == "S0-7" }, "ショートカットは正式アプリのみ")
    }
}
