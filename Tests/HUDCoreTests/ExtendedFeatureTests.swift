import XCTest
@testable import HUDCore

final class NewCommandParserTests: XCTestCase {
    let parser = IntentParser()

    func check(_ text: String, _ expected: AppCommand, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(parser.parse(text), expected, "「\(text)」", file: file, line: line)
    }

    func testHUDAdjustments() {
        check("HUDを大きくして", .adjustHUDScale(.up))
        check("HUDを小さく", .adjustHUDScale(.down))
        check("HUDを上に動かして", .moveHUD(.up))
        check("HUDを右に寄せて", .moveHUD(.right))
        check("HUDを暗くして", .adjustBrightness(.down))
        check("まぶしい", .adjustBrightness(.down))
        check("文字を大きくして", .adjustTextSize(.up))
        check("文字を小さく", .adjustTextSize(.down))
        check("HUDを3Dにして", .setStereo3D(true))
        check("立体表示をオフ", .setStereo3D(false))
        check("夜間モードをオフにして", .setNightDim(false))
    }

    func testCyclingAndDevices() {
        check("次のプリセット", .cyclePreset(1))
        check("前のプリセットにして", .cyclePreset(-1))
        check("テーマを変えて", .nextTheme)
        check("心拍計に接続して", .connectHeartRate)
        check("同期して", .syncNow)
        check("記録を開始して", .setRecording(true))
        check("記録を終了", .setRecording(false))
        check("心拍数を表示して", .showWidget(.heartRate))
        check("水平器を表示", .showWidget(.horizon))
    }

    func testMap3DStillGoesToMap() {
        check("地図を3Dにして", .setMap3D(true))
        check("地図を大きくして", .mapZoom(.zoomIn))
    }
}

final class AICommandCodecTests: XCTestCase {
    func testDecodesWhitelistedCommands() {
        let text = """
        はい、わかりました。
        {"commands":[{"name":"setBackground","value":"camera"},{"name":"showWidget","value":"speed"},{"name":"applyPreset","value":"travel"},{"name":"setNightDim","value":true}],"reply":"カメラ背景にして速度を表示します"}
        """
        let plan = AICommandCodec.decode(text)
        XCTAssertEqual(plan.commands, [.setBackground(.camera), .showWidget(.speed), .applyPreset(key: "travel"), .setNightDim(true)])
        XCTAssertEqual(plan.reply, "カメラ背景にして速度を表示します")
    }

    func testRejectsUnknownAndLimitsCount() {
        let text = #"{"commands":[{"name":"deleteAllData"},{"name":"applyPreset","value":"hacker"},{"name":"moveHUD","value":"up"},{"name":"nextTheme"},{"name":"autoArrange"},{"name":"syncNow"},{"name":"startHUD"}],"reply":"ok"}"#
        let plan = AICommandCodec.decode(text)
        XCTAssertFalse(plan.commands.contains(.cancel))
        XCTAssertEqual(plan.commands.first, .moveHUD(.up), "未知・不正な値は捨てる")
        XCTAssertLessThanOrEqual(plan.commands.count, AICommandCodec.maxCommands)
    }

    func testPlainTextBecomesReply() {
        let plan = AICommandCodec.decode("東京駅は東京都千代田区にあります。")
        XCTAssertTrue(plan.commands.isEmpty)
        XCTAssertEqual(plan.reply, "東京駅は東京都千代田区にあります。")
    }

    func testCatalogMentionsEveryCommandName() {
        for name in ["setBackground", "navigate", "moveHUD", "searchNearby", "status", "connectHeartRate"] {
            XCTAssertTrue(AICommandCodec.catalog.contains(name), name)
            XCTAssertNotNil(AICommandCodec.command(name: name, value: name == "setBackground" ? "black" : name == "navigate" ? "東京駅" : name == "moveHUD" ? "up" : name == "searchNearby" ? "cafe" : name == "status" ? "time" : ""), name)
        }
    }
}

final class DeepLinkAndTemplateTests: XCTestCase {
    func testDeepLinks() {
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://hud/start")!), .startHUD)
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://background/toggle")!), .toggleBackground)
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://background/camera")!), .setBackground(.camera))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://preset/walkNav")!), .applyPreset(key: "walkNav"))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://preset/next")!), .cyclePreset(1))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://navigate?to=%E6%9D%B1%E4%BA%AC%E9%A7%85")!), .navigate(to: "東京駅"))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://nearby/cafe")!), .searchNearby(.cafe))
        XCTAssertNil(DeepLink.command(from: URL(string: "https://example.com/hud/start")!))
        XCTAssertNil(DeepLink.command(from: URL(string: "hudnavigator://unknown")!))
    }

    func testTemplate() {
        let r = TemplateRenderer.render("{time} 電池{battery} {speed}km/h {hr}", values: ["time": "12:00", "battery": "80%", "speed": "4.2"])
        XCTAssertEqual(r, "12:00 電池80% 4.2km/h --")
        XCTAssertTrue(TemplateRenderer.usesTokens("{weather}"))
        XCTAssertFalse(TemplateRenderer.usesTokens("ただの文字"))
        XCTAssertEqual(TemplateRenderer.render("{unknown}", values: [:]), "{unknown}")
    }
}

final class GoogleMapsTests: XCTestCase {
    func testPolylineDecodeKnownValue() {
        // Google のドキュメントの例
        let points = EncodedPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].latitude, 38.5, accuracy: 1e-5)
        XCTAssertEqual(points[0].longitude, -120.2, accuracy: 1e-5)
        XCTAssertEqual(points[2].latitude, 43.252, accuracy: 1e-5)
        XCTAssertEqual(points[2].longitude, -126.453, accuracy: 1e-5)
    }

    func testPolylineRoundTrip() {
        let pts = DemoRoutes.waypoints
        let decoded = EncodedPolyline.decode(EncodedPolyline.encode(pts))
        XCTAssertEqual(decoded.count, pts.count)
        for (a, b) in zip(pts, decoded) {
            XCTAssertEqual(a.latitude, b.latitude, accuracy: 1e-5)
            XCTAssertEqual(a.longitude, b.longitude, accuracy: 1e-5)
        }
    }

    func testParsePlaces() throws {
        let json = """
        {"places":[{"id":"abc","displayName":{"text":"カフェ東京","languageCode":"ja"},"formattedAddress":"東京都千代田区","location":{"latitude":35.68,"longitude":139.76},
          "rating":4.3,"userRatingCount":120,"currentOpeningHours":{"openNow":true},"regularOpeningHours":{"weekdayDescriptions":["月曜日: 8時00分～20時00分"]},
          "primaryTypeDisplayName":{"text":"カフェ"},"googleMapsUri":"https://maps.google.com/?cid=1"}]}
        """
        let places = try GoogleMapsAPI.parsePlaces(Data(json.utf8))
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].name, "カフェ東京")
        XCTAssertEqual(places[0].rating, 4.3)
        XCTAssertEqual(places[0].ratingCount, 120)
        XCTAssertEqual(places[0].openNow, true)
        XCTAssertEqual(places[0].openingHours.count, 1)
        XCTAssertEqual(places[0].category, "カフェ")
    }

    func testParseRoutesWithTransit() throws {
        let line = EncodedPolyline.encode(DemoRoutes.waypoints)
        let json = """
        {"routes":[{"description":"内堀通り","duration":"420s","distanceMeters":560,"polyline":{"encodedPolyline":"\(line)"},
          "legs":[{"steps":[
            {"distanceMeters":200,"navigationInstruction":{"maneuver":"DEPART","instructions":"西に進む"},"endLocation":{"latLng":{"latitude":35.6818,"longitude":139.7633}}},
            {"distanceMeters":300,"navigationInstruction":{"maneuver":"TURN_LEFT","instructions":"左折して内堀通りに入る"},"endLocation":{"latLng":{"latitude":35.6811,"longitude":139.7594}}},
            {"distanceMeters":900,"travelMode":"TRANSIT","transitDetails":{"headsign":"渋谷","stopCount":3,"transitLine":{"nameShort":"銀座線"},"stopDetails":{"departureStop":{"name":"銀座"},"arrivalStop":{"name":"表参道"}}}}
          ]}]}]}
        """
        let routes = try GoogleMapsAPI.parseRoutes(Data(json.utf8), transport: .transit, destinationName: "表参道")
        XCTAssertEqual(routes.count, 1)
        let r = routes[0]
        XCTAssertEqual(r.expectedTravelTime, 420)
        XCTAssertEqual(r.distance, 560)
        XCTAssertEqual(r.polyline.count, DemoRoutes.waypoints.count)
        XCTAssertEqual(r.steps[1].maneuver, .left)
        XCTAssertTrue(r.steps[2].instruction.contains("銀座線"))
        XCTAssertTrue(r.steps[2].instruction.contains("銀座→表参道"))
        XCTAssertEqual(r.steps.last?.maneuver, .arrive)
    }

    func testRequestBodies() {
        let body = GoogleMapsAPI.routesBody(from: DemoRoutes.waypoints[0], to: DemoRoutes.waypoints[4], transport: .transit, departure: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(body["travelMode"] as? String, "TRANSIT")
        XCTAssertEqual(body["computeAlternativeRoutes"] as? Bool, false)
        XCTAssertNotNil(body["departureTime"])
        let nearby = GoogleMapsAPI.nearbyBody(category: .convenienceStore, near: DemoRoutes.waypoints[0])
        XCTAssertEqual(nearby["includedTypes"] as? [String], ["convenience_store"])
        XCTAssertEqual(GoogleMapsAPI.seconds("123s"), 123)
        XCTAssertEqual(GoogleMapsAPI.maneuver("TURN_SLIGHT_RIGHT"), .slightRight)
    }
}

final class AdvisorTests: XCTestCase {
    func weather(rainAt hoursAhead: Double, prob: Double, now: Date) -> WeatherSnapshot {
        var w = WeatherSnapshot(fetchedAt: now)
        w.temperature = 20
        w.hourly = (0..<12).map { i in
            HourlyForecast(time: now.addingTimeInterval(Double(i) * 3600), temperature: 20, precipitationProbability: Double(i) == hoursAhead ? prob : 10, weatherCode: 3)
        }
        return w
    }

    func testRainSuggestionAndCooldown() {
        var advisor = ProactiveAdvisor(settings: ProactiveSettings())
        let now = Date(timeIntervalSince1970: 1_000_000)
        let input = AdvisorInput(now: now, weather: weather(rainAt: 1, prob: 80, now: now))
        let first = advisor.evaluate(input)
        XCTAssertEqual(first.map(\.key), ["rain"])
        XCTAssertTrue(advisor.evaluate(AdvisorInput(now: now.addingTimeInterval(600), weather: input.weather)).isEmpty, "クールダウン中は出さない")
        XCTAssertFalse(advisor.evaluate(AdvisorInput(now: now.addingTimeInterval(4 * 3600), weather: weather(rainAt: 1, prob: 80, now: now.addingTimeInterval(4 * 3600)))).isEmpty)
        var noRain = ProactiveAdvisor(settings: ProactiveSettings())
        XCTAssertTrue(noRain.evaluate(AdvisorInput(now: now, weather: weather(rainAt: 5, prob: 90, now: now))).isEmpty, "2時間より先の雨は出さない")
    }

    func testBatteryBreakAndArrival() {
        var advisor = ProactiveAdvisor(settings: ProactiveSettings())
        let now = Date(timeIntervalSince1970: 2_000_000)
        let s = advisor.evaluate(AdvisorInput(now: now, batteryLevel: 0.2, movement: .walking, continuousMovingSeconds: 70 * 60, justArrived: true, isHUDVisible: true, cameraActive: true))
        let keys = Set(s.map(\.key))
        XCTAssertTrue(keys.contains("battery-camera"))
        XCTAssertTrue(keys.contains("break"))
        XCTAssertTrue(keys.contains("arrived-nearby"))
        XCTAssertEqual(s.first { $0.key == "battery-camera" }?.action, .setBackground(.black))
        var off = ProactiveAdvisor(settings: { var p = ProactiveSettings(); p.enabled = false; return p }())
        XCTAssertTrue(off.evaluate(AdvisorInput(now: now, batteryLevel: 0.1, cameraActive: true)).isEmpty)
    }
}

final class VisitsUsageTests: XCTestCase {
    func testVisitDetection() {
        var detector = VisitDetector(radius: 60, minimumStay: 300)
        let t0 = Date(timeIntervalSince1970: 0)
        let home = GeoCoordinate(latitude: 35.0, longitude: 139.0)
        var visits: [VisitRecord] = []
        // 10分間ほぼ同じ場所
        for i in 0..<20 {
            let jitter = Geo.destination(from: home, bearing: Double(i * 37 % 360), distance: 10)
            if let v = detector.add(LocationSample(coordinate: jitter, timestamp: t0.addingTimeInterval(Double(i) * 30), horizontalAccuracy: 8)) { visits.append(v) }
        }
        XCTAssertTrue(detector.isVisiting)
        // 離れる
        let away = Geo.destination(from: home, bearing: 90, distance: 500)
        if let v = detector.add(LocationSample(coordinate: away, timestamp: t0.addingTimeInterval(700), horizontalAccuracy: 8)) { visits.append(v) }
        XCTAssertEqual(visits.count, 1)
        XCTAssertGreaterThanOrEqual(visits[0].duration, 300)
        XCTAssertLessThan(Geo.distance(visits[0].coordinate, home), 20)
        // 短い立ち寄りは訪問にしない
        var short = VisitDetector(radius: 60, minimumStay: 300)
        _ = short.add(LocationSample(coordinate: home, timestamp: t0, horizontalAccuracy: 8))
        _ = short.add(LocationSample(coordinate: home, timestamp: t0.addingTimeInterval(60), horizontalAccuracy: 8))
        XCTAssertNil(short.add(LocationSample(coordinate: away, timestamp: t0.addingTimeInterval(90), horizontalAccuracy: 8)))
    }

    func testUsageStats() throws {
        var u = UsageStats()
        u.since = Date(timeIntervalSince1970: 1_000_000) // ISO8601 は秒単位で保存される
        u.launches = 3
        u.recordHUD(seconds: 600, preset: "徒歩ナビ")
        u.recordHUD(seconds: 120, preset: "ミニマル")
        u.recordHUD(seconds: 99_999, preset: "異常値")
        u.recordCommand("背景を黒背景に変更", viaVoice: true)
        u.recordCommand("背景を黒背景に変更", viaVoice: false)
        u.recordNavigation(distance: 1200)
        XCTAssertEqual(u.hudSeconds, 720)
        XCTAssertEqual(u.topPresets().first?.name, "徒歩ナビ")
        XCTAssertEqual(u.topCommands().first?.count, 2)
        XCTAssertEqual(u.voiceCommands, 1)
        XCTAssertTrue(u.summaryText.contains("ナビ: 1回"))
        let back = try HUDJSON.decode(UsageStats.self, from: HUDJSON.encode(u))
        XCTAssertEqual(back, u)
        XCTAssertEqual(try HUDJSON.decode(UsageStats.self, from: Data("{}".utf8)).launches, 0)
    }
}

final class RoadFeatureTests: XCTestCase {
    func testLaneFilter() {
        // 左の白線（/）・右の白線（\）・水平な線・上の方の線・曲がった線
        let left = [HUDPoint(x: 0.15, y: 0.95), HUDPoint(x: 0.3, y: 0.75), HUDPoint(x: 0.42, y: 0.58)]
        let right = [HUDPoint(x: 0.85, y: 0.95), HUDPoint(x: 0.7, y: 0.75), HUDPoint(x: 0.58, y: 0.58)]
        let horizontal = [HUDPoint(x: 0.1, y: 0.8), HUDPoint(x: 0.9, y: 0.8)]
        let sky = [HUDPoint(x: 0.2, y: 0.1), HUDPoint(x: 0.4, y: 0.35)]
        let curly = [HUDPoint(x: 0.3, y: 0.9), HUDPoint(x: 0.5, y: 0.6), HUDPoint(x: 0.3, y: 0.62)]
        let wrongSide = [HUDPoint(x: 0.15, y: 0.6), HUDPoint(x: 0.3, y: 0.95)]
        let lanes = LaneLineFilter.lanes(from: [left, right, horizontal, sky, curly, wrongSide])
        XCTAssertEqual(lanes.count, 2)
        XCTAssertEqual(Set(lanes.map(\.side)), [-1, 1])
    }

    func testSignText() {
        XCTAssertEqual(SignTextClassifier.classify("止まれ")?.kind, "一時停止")
        XCTAssertEqual(SignTextClassifier.classify("STOP")?.isImportant, true)
        XCTAssertEqual(SignTextClassifier.classify("通学路")?.kind, "通学路")
        XCTAssertEqual(SignTextClassifier.classify("40")?.kind, "最高速度 40km/h（推定）")
        XCTAssertNil(SignTextClassifier.classify("37"))
        XCTAssertNil(SignTextClassifier.classify("ラーメン"))
    }
}

final class HeartRateAndSyncTests: XCTestCase {
    func testHeartRateParsing() {
        XCTAssertEqual(HeartRateParser.bpm(from: [0x00, 72]), 72)
        XCTAssertEqual(HeartRateParser.bpm(from: [0x01, 0x2C, 0x01]), 300)
        XCTAssertNil(HeartRateParser.bpm(from: [0x01, 0x2C]))
        XCTAssertNil(HeartRateParser.bpm(from: []))
        XCTAssertEqual(HeartRateParser.zone(bpm: 80, age: 35).name, "安静")
        XCTAssertEqual(HeartRateParser.zone(bpm: 140, age: 35).index, 3)
    }

    func testSyncDecision() {
        let t = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(SyncDecision.shouldImport(remoteExportedAt: t, remoteDeviceID: "me", localDeviceID: "me", lastImportedAt: nil, lastExportedAt: nil))
        XCTAssertTrue(SyncDecision.shouldImport(remoteExportedAt: t, remoteDeviceID: "ipad", localDeviceID: "iphone", lastImportedAt: nil, lastExportedAt: nil))
        XCTAssertFalse(SyncDecision.shouldImport(remoteExportedAt: t, remoteDeviceID: "ipad", localDeviceID: "iphone", lastImportedAt: t, lastExportedAt: nil))
        XCTAssertFalse(SyncDecision.shouldImport(remoteExportedAt: t, remoteDeviceID: "ipad", localDeviceID: "iphone", lastImportedAt: nil, lastExportedAt: t.addingTimeInterval(10)))
    }

    func testBundleDecodesOldSettingsWithMissingKeys() throws {
        let json = #"{"version":1,"exportedAt":"2026-01-01T00:00:00Z","deviceName":"iPad","settings":{"voice":{"guidanceEnabled":false}},"themes":[],"presets":[],"favorites":[]}"#
        let bundle = try SettingsBundle.decode(Data(json.utf8))
        XCTAssertEqual(bundle.settings?.voice.guidanceEnabled, false)
        XCTAssertEqual(bundle.settings?.display, HUDDisplaySettings())
        XCTAssertNil(bundle.deviceID)
    }
}

final class DisplaySettingsTests: XCTestCase {
    func testNightDimming() {
        var d = HUDDisplaySettings()
        d.brightness = 1
        d.nightBrightness = 0.5
        XCTAssertEqual(d.effectiveBrightness(hour: 12, isDaylight: nil), 1)
        XCTAssertEqual(d.effectiveBrightness(hour: 22, isDaylight: nil), 0.5)
        XCTAssertEqual(d.effectiveBrightness(hour: 3, isDaylight: nil), 0.5)
        XCTAssertEqual(d.effectiveBrightness(hour: 22, isDaylight: true), 1, "天気の昼夜情報を優先")
        d.nightDimEnabled = false
        XCTAssertEqual(d.effectiveBrightness(hour: 22, isDaylight: false), 1)
    }

    func testHourlyWeatherParsing() throws {
        let json = """
        {"utc_offset_seconds":32400,"current":{"time":"2026-11-09T14:00","temperature_2m":17.4,"weather_code":2},
         "hourly":{"time":["2026-11-09T14:00","2026-11-09T15:00","2026-11-09T16:00"],"precipitation_probability":[10,70,90],"temperature_2m":[17,16,15],"weather_code":[2,61,63]}}
        """
        let s = try OpenMeteo.parseForecast(Data(json.utf8), fetchedAt: Date())
        XCTAssertEqual(s.hourly.count, 3)
        XCTAssertEqual(s.hourly[1].precipitationProbability, 70)
        let now = s.hourly[0].time
        XCTAssertEqual(s.rainExpected(withinHours: 2, threshold: 60, after: now)?.precipitationProbability, 70)
        XCTAssertNil(s.rainExpected(withinHours: 0.5, threshold: 60, after: now))
    }
}

final class ObjectLabelTests: XCTestCase {
    func testJapaneseLabels() {
        XCTAssertEqual(ObjectLabels.displayName(label: .other, raw: "chair"), "椅子")
        XCTAssertEqual(ObjectLabels.displayName(label: .car, raw: "car"), DetectionLabel.car.displayName)
        XCTAssertEqual(ObjectLabels.displayName(label: .other, raw: "unknown-thing"), "unknown-thing")
        XCTAssertEqual(DetectionLabel.from(identifier: "motorbike"), .motorcycle)
        XCTAssertEqual(DetectionLabel.from(identifier: "traffic light"), .trafficLight)
        XCTAssertEqual(BundledObjectModel(rawValue: "YOLOv3Tiny"), .yolov3Tiny)
    }
}
