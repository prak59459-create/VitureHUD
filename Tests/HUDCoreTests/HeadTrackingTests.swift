import XCTest
@testable import HUDCore

final class HeadPoseTests: XCTestCase {
    func testNormalizeAndRelative() {
        XCTAssertEqual(HeadPose.normalize(190), -170, accuracy: 1e-9)
        XCTAssertEqual(HeadPose.normalize(-190), 170, accuracy: 1e-9)
        XCTAssertEqual(HeadPose.normalize(.nan), 0)
        let ref = HeadPose(yaw: 170, pitch: 5, roll: 0)
        let now = HeadPose(yaw: -170, pitch: 15, roll: -3)
        let rel = now.relative(to: ref)
        XCTAssertEqual(rel.yaw, 20, accuracy: 1e-9, "180度をまたいでも最短の向き")
        XCTAssertEqual(rel.pitch, 10, accuracy: 1e-9)
        XCTAssertEqual(rel.roll, -3, accuracy: 1e-9)
    }

    func testSettingsAdjustments() {
        var s = HeadTrackingSettings()
        s.invertYaw = true
        s.swapPitchRoll = true
        let p = s.adjusted(HeadPose(yaw: 10, pitch: 20, roll: 30))
        XCTAssertEqual(p, HeadPose(yaw: -10, pitch: 30, roll: 20))
    }

    func testFilterRecenterAndSmoothing() {
        var f = HeadPoseFilter()
        let first = f.update(raw: HeadPose(yaw: 50, pitch: 0, roll: 0), smoothing: 0)
        XCTAssertEqual(first, .zero, "最初の向きが正面")
        let moved = f.update(raw: HeadPose(yaw: 60, pitch: -10, roll: 0), smoothing: 0)
        XCTAssertEqual(moved.yaw, 10, accuracy: 1e-9)
        XCTAssertEqual(moved.pitch, -10, accuracy: 1e-9)
        f.recenter()
        let after = f.update(raw: HeadPose(yaw: 60, pitch: -10, roll: 0), smoothing: 0)
        XCTAssertEqual(after.yaw, 0, accuracy: 1e-9)
        // なめらかにすると少しずつ近づく
        let smooth = f.update(raw: HeadPose(yaw: 80, pitch: -10, roll: 0), smoothing: 0.5)
        XCTAssertEqual(smooth.yaw, 10, accuracy: 1e-9)
    }

    func testHeadLockOffset() {
        let o = HeadLock.offset(for: HeadPose(yaw: 10, pitch: 5, roll: 0), pixelsPerDegree: 40, width: 1920, height: 1080)
        XCTAssertEqual(o.x, -400, accuracy: 1e-9, "右を向くと HUD は左へ")
        XCTAssertEqual(o.y, 200, accuracy: 1e-9, "上を向くと HUD は下へ")
        let far = HeadLock.offset(for: HeadPose(yaw: -90, pitch: 0, roll: 0), pixelsPerDegree: 40, width: 1920, height: 1080)
        XCTAssertEqual(far.x, 1152, accuracy: 1e-9, "画面の 0.6 倍まで")
    }
}

final class HeadGestureTests: XCTestCase {
    private func run(_ poses: [(Double, HeadPose)], detector: inout HeadGestureDetector) -> [HeadGesture] {
        poses.compactMap { detector.add($0.1, at: $0.0) }
    }

    func testNod() {
        var d = HeadGestureDetector()
        let pitches: [Double] = [0, -3, -8, -14, -18, -12, -5, 0, 1]
        let poses = pitches.enumerated().map { (Double($0.offset) * 0.08, HeadPose(yaw: 0, pitch: $0.element, roll: 0)) }
        XCTAssertEqual(run(poses, detector: &d), [.nod])
    }

    func testShake() {
        var d = HeadGestureDetector()
        let yaws: [Double] = [0, 10, 18, 8, -5, -16, -6, 6, 17, 5, 0]
        let poses = yaws.enumerated().map { (Double($0.offset) * 0.08, HeadPose(yaw: $0.element, pitch: 0, roll: 0)) }
        XCTAssertEqual(run(poses, detector: &d), [.shake])
    }

    func testLookingAwayAndBackIsNotShake() {
        var d = HeadGestureDetector()
        let yaws: [Double] = [0, 15, 30, 30, 30, 15, 0]
        let poses = yaws.enumerated().map { (Double($0.offset) * 0.15, HeadPose(yaw: $0.element, pitch: 0, roll: 0)) }
        XCTAssertEqual(run(poses, detector: &d), [])
    }

    func testLookingUpThenDownIsNotNod() {
        var d = HeadGestureDetector()
        let pitches: [Double] = [0, 6, 14, 18, 10, 2, 0]
        let poses = pitches.enumerated().map { (Double($0.offset) * 0.1, HeadPose(yaw: 0, pitch: $0.element, roll: 0)) }
        XCTAssertEqual(run(poses, detector: &d), [], "上を向いてから戻るのはうなずきではない")
    }

    func testTiltHold() {
        var d = HeadGestureDetector()
        var poses: [(Double, HeadPose)] = []
        for i in 0..<12 { poses.append((Double(i) * 0.1, HeadPose(yaw: 0, pitch: 0, roll: i < 3 ? Double(i) * 8 : 25))) }
        XCTAssertEqual(run(poses, detector: &d), [.tiltRight])
        var d2 = HeadGestureDetector()
        let left = (0..<12).map { (Double($0) * 0.1, HeadPose(yaw: 0, pitch: 0, roll: -25)) }
        XCTAssertEqual(run(left, detector: &d2), [.tiltLeft])
    }

    func testCooldown() {
        var d = HeadGestureDetector()
        let pitches: [Double] = [0, -15, 0, -15, 0, -15, 0]
        let poses = pitches.enumerated().map { (Double($0.offset) * 0.1, HeadPose(yaw: 0, pitch: $0.element, roll: 0)) }
        XCTAssertEqual(run(poses, detector: &d).count, 1, "続けてのうなずきは 1 回として扱う")
    }

    func testGlanceHysteresis() {
        var g = GlanceDetector(angle: 15)
        XCTAssertFalse(g.update(pitch: -10))
        XCTAssertTrue(g.update(pitch: -16))
        XCTAssertTrue(g.update(pitch: -12), "少し戻っただけでは消さない")
        XCTAssertFalse(g.update(pitch: -5))
    }
}

final class SensorProtocolTests: XCTestCase {
    /// 表を使う CRC（参考元と同じ方式）で検算する
    private func tableCRC(_ data: [UInt8]) -> UInt16 {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt16(i) << 8
            for _ in 0..<8 { c = (c & 0x8000) != 0 ? (c << 1) ^ 0x1021 : c << 1 }
            table[i] = c
        }
        var crc: UInt16 = 0
        for b in data { crc = table[Int((UInt16(b) ^ (crc >> 8)) & 0xFF)] ^ (crc << 8) }
        return crc
    }

    func testCRC16CCITT() {
        // CRC-16/XMODEM（初期値 0）の既知の値
        XCTAssertEqual(VitureHIDProtocol.crc16(Array("123456789".utf8)), 0x31C3)
        let data: [UInt8] = [0x0D, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0x15, 0x00, 0, 0, 0x01]
        XCTAssertEqual(VitureHIDProtocol.crc16(data), tableCRC(data))
    }

    func testSetIMUCommandLayout() {
        let cmd = VitureHIDProtocol.setIMU(true)
        XCTAssertEqual(cmd.count, 64)
        XCTAssertEqual(Array(cmd[0...1]), [0xFF, 0xFE])
        XCTAssertEqual(Array(cmd[4...5]), [0x0D, 0x00], "長さ = 0x0C + データ1バイト")
        XCTAssertEqual(Array(cmd[0x0E...0x0F]), [0x15, 0x00])
        XCTAssertEqual(cmd[0x12], 0x01)
        let crc = UInt16(cmd[2]) | UInt16(cmd[3]) << 8
        XCTAssertEqual(crc, tableCRC(Array(cmd[4..<(6 + 0x0D)])))
        XCTAssertEqual(VitureHIDProtocol.setIMU(false)[0x12], 0x00)
    }

    private func imuReport(roll: Float, pitch: Float, yaw: Float, reportID: UInt8? = nil) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 64)
        r[0] = 0xFF; r[1] = 0xFC
        let payload = 0x0C + 12
        r[4] = UInt8(payload); r[5] = 0
        for (i, v) in [roll, pitch, yaw].enumerated() {
            let bits = v.bitPattern
            r[0x12 + i * 4] = UInt8(bits >> 24)
            r[0x13 + i * 4] = UInt8((bits >> 16) & 0xFF)
            r[0x14 + i * 4] = UInt8((bits >> 8) & 0xFF)
            r[0x15 + i * 4] = UInt8(bits & 0xFF)
        }
        let crc = VitureHIDProtocol.crc16(r[4..<(6 + payload)])
        r[2] = UInt8(crc & 0xFF); r[3] = UInt8(crc >> 8)
        if let id = reportID { return [id] + r }
        return r
    }

    func testParseIMUReport() throws {
        let r = try XCTUnwrap(VitureHIDProtocol.parseIMU(imuReport(roll: 1.5, pitch: -12.25, yaw: 30)))
        XCTAssertEqual(r.roll, 1.5, accuracy: 1e-6)
        XCTAssertEqual(r.pitch, -12.25, accuracy: 1e-6)
        XCTAssertEqual(r.yaw, 30, accuracy: 1e-6)
        XCTAssertTrue(r.checksumValid)
        let withID = try XCTUnwrap(VitureHIDProtocol.parseIMU(imuReport(roll: 0, pitch: 2, yaw: -4, reportID: 0x00)))
        XCTAssertEqual(withID.pitch, 2, accuracy: 1e-6, "先頭にレポートIDが付いていても読める")
        XCTAssertEqual(VitureHIDProtocol.pose(withID).yaw, 4, accuracy: 1e-6)
        XCTAssertNil(VitureHIDProtocol.parseIMU([0xFF, 0xFE] + [UInt8](repeating: 0, count: 62)), "命令の応答は IMU ではない")
        XCTAssertNil(VitureHIDProtocol.parseIMU([0xFF, 0xFC, 0, 0]))
    }

    func testWitMotionParse() throws {
        func le(_ v: Int16) -> [UInt8] { let u = UInt16(bitPattern: v); return [UInt8(u & 0xFF), UInt8(u >> 8)] }
        // 加速度 Z = 1G、ヨー = 90度、ピッチ = -45度
        var packet: [UInt8] = [0x55, 0x61]
        packet += le(0) + le(0) + le(2048)
        packet += le(0) + le(0) + le(0)
        packet += le(0) + le(-8192) + le(16384)
        XCTAssertEqual(packet.count, 20)
        let samples = WitMotionBLE.parse([0x00] + packet + packet)
        XCTAssertEqual(samples.count, 2, "ずれていても見つける・2 パケット続けて読める")
        let s = try XCTUnwrap(samples.first)
        XCTAssertEqual(s.az, 1, accuracy: 1e-9)
        XCTAssertEqual(s.pitch, -45, accuracy: 1e-9)
        XCTAssertEqual(s.yaw, 90, accuracy: 1e-9)
        XCTAssertEqual(WitMotionBLE.pose(s).yaw, -90, accuracy: 1e-9)
        XCTAssertEqual(WitMotionBLE.rateCommands(hz: 50)[1], [0xFF, 0xAA, 0x03, 0x08, 0x00])
    }

    func testDIYProtocolRoundTrip() throws {
        let pose = HeadPose(yaw: 12.5, pitch: -3.25, roll: 7)
        let bytes = HUDIMUBLE.encode(pose)
        XCTAssertEqual(bytes.count, 12)
        let s = try XCTUnwrap(HUDIMUBLE.parse(bytes))
        XCTAssertEqual(s.pose, pose)
        XCTAssertNil(s.acceleration)
        XCTAssertNil(HUDIMUBLE.parse([1, 2, 3]))
    }
}

final class HeadCommandParserTests: XCTestCase {
    let parser = IntentParser()

    func testHeadCommands() {
        XCTAssertEqual(parser.parse("正面をリセットして"), .recenterHead)
        XCTAssertEqual(parser.parse("正面にして"), .recenterHead)
        XCTAssertEqual(parser.parse("HUDを空間に固定して"), .setHeadLock(true))
        XCTAssertEqual(parser.parse("HUDの固定を解除して"), .setHeadLock(false))
        XCTAssertEqual(parser.parse("下を見たときだけ表示して"), .setGlanceMode(true))
        XCTAssertEqual(parser.parse("チラ見モードをオフ"), .setGlanceMode(false))
        XCTAssertEqual(parser.parse("歩数を表示して"), .showWidget(.steps))
        XCTAssertEqual(parser.parse("頭の向きを表示して"), .showWidget(.headPose))
    }

    func testCodecAndDeepLink() {
        XCTAssertEqual(AICommandCodec.command(name: "recenterHead", value: ""), .recenterHead)
        XCTAssertEqual(AICommandCodec.command(name: "setHeadLock", value: "true"), .setHeadLock(true))
        XCTAssertEqual(AICommandCodec.command(name: "setGlanceMode", value: "false"), .setGlanceMode(false))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://head/recenter")!), .recenterHead)
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://head/lock")!), .setHeadLock(true))
        XCTAssertTrue(AICommandCodec.catalog.contains("recenterHead"))
    }

    func testSettingsDecodeAddsHeadTrackingDefaults() throws {
        let old = #"{"display":{"brightness":0.8}}"#.data(using: .utf8)!
        let s = try AppSettings.decodeMergingDefaults(from: old)
        XCTAssertEqual(s.headTracking.source, .off)
        XCTAssertEqual(s.headTracking.glanceAngle, 15)
        XCTAssertEqual(s.display.brightness, 0.8, accuracy: 1e-9)
    }
}
