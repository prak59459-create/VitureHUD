import XCTest
@testable import HUDCore

final class GeoTests: XCTestCase {
    func testDistanceAndBearing() {
        let tokyo = GeoCoordinate(latitude: 35.681236, longitude: 139.767125)
        let osaka = GeoCoordinate(latitude: 34.702485, longitude: 135.495951)
        XCTAssertEqual(Geo.distance(tokyo, osaka), 403_000, accuracy: 3_000)
        let east = Geo.destination(from: tokyo, bearing: 90, distance: 1000)
        XCTAssertEqual(Geo.distance(tokyo, east), 1000, accuracy: 1)
        XCTAssertEqual(Geo.bearing(tokyo, east), 90, accuracy: 0.5)
        XCTAssertEqual(Geo.cardinalName(10), "北")
        XCTAssertEqual(Geo.cardinalName(100), "東")
        XCTAssertEqual(Geo.cardinalName(350), "北")
        XCTAssertEqual(Geo.angleDifference(from: 350, to: 10), 20, accuracy: 1e-9)
    }

    func testProjection() {
        let a = GeoCoordinate(latitude: 35.0, longitude: 139.0)
        let b = Geo.destination(from: a, bearing: 90, distance: 100)
        let mid = Geo.destination(from: Geo.interpolate(a, b, fraction: 0.5), bearing: 0, distance: 10)
        let r = Geo.project(mid, onSegment: a, b)
        XCTAssertEqual(r.fraction, 0.5, accuracy: 0.01)
        XCTAssertEqual(r.distance, 10, accuracy: 0.2)
    }

    func testRounding() {
        let c = GeoCoordinate(latitude: 35.681236, longitude: 139.767125).rounded()
        XCTAssertEqual(c.latitude, 35.681, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, 139.767, accuracy: 1e-9)
    }
}

final class ManeuverTests: XCTestCase {
    func testClassifyJapanese() {
        XCTAssertEqual(ManeuverKind.classify("右折して八重洲通りに入る"), .right)
        XCTAssertEqual(ManeuverKind.classify("左折します"), .left)
        XCTAssertEqual(ManeuverKind.classify("目的地は右側です"), .arrive)
        XCTAssertEqual(ManeuverKind.classify("斜め右方向です"), .slightRight)
        XCTAssertEqual(ManeuverKind.classify("Uターンしてください"), .uTurn)
        XCTAssertEqual(ManeuverKind.classify("Turn left onto Main St"), .left)
        XCTAssertEqual(ManeuverKind.classify("ロータリーに入る"), .roundabout)
    }

    func testRoadName() {
        XCTAssertEqual(NavStep(instruction: "右折して 八重洲通り に入る", distance: 10, endCoordinate: GeoCoordinate(latitude: 1, longitude: 1)).roadName, "八重洲通り")
        XCTAssertNil(NavStep(instruction: "右折します", distance: 10, endCoordinate: GeoCoordinate(latitude: 1, longitude: 1)).roadName)
    }
}

final class RouteProgressTests: XCTestCase {
    let route = DemoRoutes.walkingRoute()

    func testProgressAlongDemoRoute() {
        var engine = RouteProgressEngine(route: route)
        let start = Date(timeIntervalSince1970: 0)
        let track = SimulatedTrack(points: route.polyline, speed: 1.4)
        var last: RouteProgress?
        var t: TimeInterval = 0
        var previousRemaining = Double.infinity
        while let s = track.sample(at: t, startDate: start) {
            let p = engine.update(with: s)
            XCTAssertFalse(p.isOffRoute, "ルート上を歩いているのに逸脱判定（t=\(t)）")
            XCTAssertLessThanOrEqual(p.remainingDistance, previousRemaining + 1, "残り距離が増えた（t=\(t)）")
            XCTAssertLessThan(p.offRouteDistance, 1)
            previousRemaining = p.remainingDistance
            last = p
            t += 3
        }
        // 終点を過ぎたら到着
        let final = engine.update(with: LocationSample(coordinate: route.destination!, timestamp: start.addingTimeInterval(t), speed: 0))
        XCTAssertTrue(final.hasArrived)
        XCTAssertNotNil(last)
    }

    func testNextManeuverIsTheLeftTurn() {
        var engine = RouteProgressEngine(route: route)
        // 和田倉門（2つ目の曲がり角）の少し手前
        let wp = DemoRoutes.waypoints
        let near = Geo.interpolate(wp[1], wp[2], fraction: 0.8)
        let p = engine.update(with: LocationSample(coordinate: near, timestamp: Date(), speed: 1.3))
        XCTAssertEqual(p.nextStepIndex, 1)
        XCTAssertEqual(p.distanceToNextManeuver ?? -1, Geo.distance(near, wp[2]), accuracy: 15)
        // 曲がり角を過ぎたら次は左折
        let after = Geo.interpolate(wp[2], wp[3], fraction: 0.2)
        let p2 = engine.update(with: LocationSample(coordinate: after, timestamp: Date(), speed: 1.3))
        XCTAssertEqual(p2.nextStepIndex, 2)
        XCTAssertEqual(route.steps[2].maneuver, .left)
    }

    func testOffRouteNeedsDistanceAndDuration() {
        var engine = RouteProgressEngine(route: route)
        let wp = DemoRoutes.waypoints
        let onRoute = Geo.interpolate(wp[0], wp[1], fraction: 0.5)
        let away = Geo.destination(from: onRoute, bearing: 180, distance: 60)
        let t0 = Date(timeIntervalSince1970: 1000)
        _ = engine.update(with: LocationSample(coordinate: onRoute, timestamp: t0))
        let p1 = engine.update(with: LocationSample(coordinate: away, timestamp: t0.addingTimeInterval(1)))
        XCTAssertFalse(p1.isOffRoute, "一瞬のずれでは逸脱にしない")
        let p2 = engine.update(with: LocationSample(coordinate: away, timestamp: t0.addingTimeInterval(10)))
        XCTAssertTrue(p2.isOffRoute)
        // 精度の悪いサンプルは逸脱判定に使わない
        var engine2 = RouteProgressEngine(route: route)
        _ = engine2.update(with: LocationSample(coordinate: away, timestamp: t0, horizontalAccuracy: 100))
        let p3 = engine2.update(with: LocationSample(coordinate: away, timestamp: t0.addingTimeInterval(20), horizontalAccuracy: 100))
        XCTAssertFalse(p3.isOffRoute)
    }
}

final class GuidancePlannerTests: XCTestCase {
    func testAnnouncesEachThresholdOnce() {
        let route = DemoRoutes.walkingRoute()
        var planner = GuidancePlanner(transport: .walking, frequency: .normal, announcesETA: false)
        var engine = RouteProgressEngine(route: route)
        let track = SimulatedTrack(points: route.polyline, speed: 1.4)
        let start = Date(timeIntervalSince1970: 0)
        var texts: [String] = []
        var t: TimeInterval = 0
        while let s = track.sample(at: t, startDate: start) {
            let p = engine.update(with: s)
            texts += planner.announcements(for: p, route: route, now: s.timestamp).map(\.text)
            t += 1
        }
        let p = engine.update(with: LocationSample(coordinate: route.destination!, timestamp: start.addingTimeInterval(t)))
        texts += planner.announcements(for: p, route: route, now: start.addingTimeInterval(t)).map(\.text)
        texts += planner.announcements(for: p, route: route, now: start.addingTimeInterval(t + 1)).map(\.text)
        XCTAssertEqual(Set(texts).count, texts.count, "同じ案内を繰り返している: \(texts)")
        XCTAssertTrue(texts.contains { $0.contains("左折") }, "左折の案内がない: \(texts)")
        XCTAssertEqual(texts.filter { $0.contains("到着しました") }.count, 1)
    }

    func testThresholdsByFrequency() {
        XCTAssertLessThan(GuidancePlanner(transport: .walking, frequency: .low).thresholds.count,
                          GuidancePlanner(transport: .walking, frequency: .high).thresholds.count)
        XCTAssertGreaterThan(GuidancePlanner(transport: .automobile).thresholds.max()!, GuidancePlanner(transport: .walking).thresholds.max()!)
    }

    func testETAAnnouncementInterval() {
        let route = DemoRoutes.walkingRoute()
        var planner = GuidancePlanner(transport: .walking, frequency: .high, announcesETA: true)
        let now = Date(timeIntervalSince1970: 0)
        _ = planner.startAnnouncement(route: route, now: now)
        var engine = RouteProgressEngine(route: route)
        let p = engine.update(with: LocationSample(coordinate: route.polyline[0], timestamp: now))
        // 曲がり角から遠い位置を想定して、ETA 判定だけを確認
        var far = p
        far.distanceToNextManeuver = 5000
        XCTAssertTrue(planner.announcements(for: far, route: route, now: now.addingTimeInterval(60)).isEmpty)
        let later = planner.announcements(for: far, route: route, now: now.addingTimeInterval(planner.etaInterval + 1))
        XCTAssertEqual(later.first?.kind, .eta)
    }
}

final class FormattingTests: XCTestCase {
    func testDistances() {
        XCTAssertEqual(HUDFormat.distance(42), "40 m")
        XCTAssertEqual(HUDFormat.distance(347), "350 m")
        XCTAssertEqual(HUDFormat.distance(1234), "1.2 km")
        XCTAssertEqual(HUDFormat.distance(15_400), "15 km")
        XCTAssertEqual(HUDFormat.spokenDistance(120), "100メートル")
        XCTAssertEqual(HUDFormat.spokenDistance(2000), "2キロメートル")
        XCTAssertEqual(HUDFormat.spokenDistance(1500), "1.5キロメートル")
    }

    func testDurationAndClock() {
        XCTAssertEqual(HUDFormat.duration(30), "1分未満")
        XCTAssertEqual(HUDFormat.duration(12 * 60), "12分")
        XCTAssertEqual(HUDFormat.duration(65 * 60), "1時間5分")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let date = Date(timeIntervalSince1970: 1_762_668_300) // 2025-11-09 15:05 JST
        XCTAssertEqual(HUDFormat.clock(date, calendar: cal), "15:05")
        XCTAssertEqual(HUDFormat.clock(date, use24Hour: false, calendar: cal), "午後3:05")
        XCTAssertEqual(HUDFormat.spokenClock(date, calendar: cal), "15時5分")
        XCTAssertEqual(HUDFormat.date(date, calendar: cal), "11月9日(日)")
    }
}

final class GPXTests: XCTestCase {
    func testDemoGPXRoundTrip() {
        let points = GPX.parse(DemoRoutes.gpx)
        XCTAssertGreaterThan(points.count, 20)
        XCTAssertNotNil(points.first?.time)
        XCTAssertEqual(points.first!.coordinate.latitude, DemoRoutes.waypoints[0].latitude, accuracy: 1e-6)
        let length = Geo.pathLength(points.map(\.coordinate))
        XCTAssertEqual(length, Geo.pathLength(DemoRoutes.waypoints), accuracy: 30)
    }

    func testParseRoutePoints() {
        let gpx = """
        <gpx><rte><rtept lat="35.1" lon="139.1"><ele>12.5</ele></rtept><rtept lat="35.2" lon="139.2"/></rte></gpx>
        """
        let points = GPX.parse(gpx)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].elevation, 12.5)
    }

    func testSimulatedTrackEnds() {
        let track = SimulatedTrack(points: DemoRoutes.waypoints, speed: 2)
        XCTAssertNotNil(track.sample(at: 0, startDate: Date()))
        XCTAssertNil(track.sample(at: track.duration + 1, startDate: Date()))
    }
}
