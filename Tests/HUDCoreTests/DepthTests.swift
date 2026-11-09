import XCTest
@testable import HUDCore

final class DepthTests: XCTestCase {
    func testGridMedianAndLookup() {
        // 4×2 の細かい値 → 2×1 の格子
        let samples: [Float] = [1, 1, 3, 3,
                                1, 9, 3, .nan]
        let g = DepthMath.grid(from: samples, width: 4, height: 2, columns: 2, rows: 1, isMetric: true)
        XCTAssertEqual(g.value(column: 0, row: 0), 1, "中央値（外れ値 9 に引きずられない）")
        XCTAssertEqual(g.value(column: 1, row: 0), 3, "nan は無視")
        XCTAssertEqual(g.value(atX: 0.9, y: 0.5), 3)
        XCTAssertEqual(g.median(in: NormalizedRect(x: 0, y: 0, width: 1, height: 1)), 3)
    }

    func testFitInverseRecoversScale() throws {
        // 真の関係：1/Z = 0.5 × d + 0.1
        var pairs: [(d: Double, z: Double)] = []
        for d in stride(from: 0.2, through: 2.0, by: 0.2) { pairs.append((d, 1 / (0.5 * d + 0.1))) }
        pairs.append((1.0, 50)) // 外れ値
        let fit = try XCTUnwrap(DepthMath.fitInverse(pairs))
        XCTAssertEqual(fit.a, 0.5, accuracy: 0.02)
        XCTAssertEqual(fit.b, 0.1, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(DepthMath.metric(1.0, fit: fit, maxRange: 20)), 1 / 0.6, accuracy: 0.05)
        XCTAssertNil(DepthMath.metric(-1, fit: fit, maxRange: 20), "遠すぎる・不正な値は nil")
    }

    func testGroundGeometry() throws {
        // 真下 30 度を見ている行：高さ 1.3m → 2.6m
        let r = try XCTUnwrap(GroundGeometry.groundRange(row: 0.5, cameraPitchDown: 30, verticalFOV: 60, height: 1.3))
        XCTAssertEqual(r, 2.6, accuracy: 1e-9)
        // 画面の下端は 30 + 30 = 60 度
        XCTAssertEqual(GroundGeometry.angleBelowHorizon(row: 1, cameraPitchDown: 30, verticalFOV: 60), 60, accuracy: 1e-9)
        XCTAssertNil(GroundGeometry.groundRange(row: 0, cameraPitchDown: 0, verticalFOV: 60, height: 1.3), "地平線より上")
    }

    func testAIScaledByGround() throws {
        // AI の値を「1/Z に比例」として作る（d = 2/Z）。地面の行から係数が求まるか
        let rows = 12, cols = 8, pitch = 20.0, fov = 60.0, h = 1.3
        var values = [Float](repeating: .nan, count: rows * cols)
        for r in 0..<rows {
            let y = (Double(r) + 0.5) / Double(rows)
            let z = GroundGeometry.groundRange(row: y, cameraPitchDown: pitch, verticalFOV: fov, height: h) ?? 30
            for c in 0..<cols { values[r * cols + c] = Float(2 / z) }
        }
        let grid = DepthGrid(columns: cols, rows: rows, values: values, isMetric: false)
        let fit = try XCTUnwrap(GroundGeometry.fitAIToGround(grid, cameraPitchDown: pitch, verticalFOV: fov, height: h))
        XCTAssertEqual(fit.a, 0.5, accuracy: 0.01)
        XCTAssertEqual(fit.b, 0, accuracy: 0.01)
    }

    func testObstacleIgnoresGroundAndNeedsTwoFrames() {
        let rows = 10, cols = 10, pitch = 15.0, fov = 60.0, h = 1.3
        func groundGrid(obstacleAt: (c: Int, r: Int, d: Float)? = nil) -> DepthGrid {
            var v = [Float](repeating: 10, count: rows * cols)
            for r in 0..<rows {
                let y = (Double(r) + 0.5) / Double(rows)
                if let g = GroundGeometry.groundRange(row: y, cameraPitchDown: pitch, verticalFOV: fov, height: h) {
                    for c in 0..<cols { v[r * cols + c] = Float(g) }
                }
            }
            if let o = obstacleAt { v[o.r * cols + o.c] = o.d }
            return DepthGrid(columns: cols, rows: rows, values: v, isMetric: true)
        }
        var det = ObstacleDetector(threshold: 1.5)
        XCTAssertNil(det.update(groundGrid(), cameraPitchDown: pitch, verticalFOV: fov, height: h), "地面だけなら何もない")
        XCTAssertNil(det.update(groundGrid(obstacleAt: (5, 4, 0.8)), cameraPitchDown: pitch, verticalFOV: fov, height: h), "1 回目は待つ")
        let o = det.update(groundGrid(obstacleAt: (5, 4, 0.8)), cameraPitchDown: pitch, verticalFOV: fov, height: h)
        XCTAssertEqual(o?.distance ?? 0, 0.8, accuracy: 1e-6)
        XCTAssertEqual(o?.direction, "正面")
        XCTAssertEqual(o?.level, .high)
    }

    func testHalfFloat() {
        XCTAssertEqual(DepthMath.halfToFloat(0x3C00), 1)
        XCTAssertEqual(DepthMath.halfToFloat(0xC000), -2)
        XCTAssertEqual(DepthMath.halfToFloat(0x3800), 0.5)
        XCTAssertEqual(DepthMath.halfToFloat(0x0000), 0)
        XCTAssertTrue(DepthMath.halfToFloat(0x7E00).isNaN)
    }

    func testBackProjectionAndVoxelCloud() {
        let p = Projection.backProject(u: 150, v: 50, depth: 2, fx: 100, fy: 100, cx: 100, cy: 100)
        XCTAssertEqual(p, Point3(1, 1, -2))
        let moved = Projection.transform(p, by: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 0, 0, 1])
        XCTAssertEqual(moved, Point3(11, 1, -2))
        var cloud = VoxelPointCloud(voxelSize: 0.1, maxPoints: 2)
        XCTAssertTrue(cloud.add(ColoredPoint(Point3(0.01, 0, 0), r: 1, g: 2, b: 3)))
        XCTAssertTrue(cloud.add(ColoredPoint(Point3(0.02, 0, 0), r: 1, g: 2, b: 3)), "同じボクセルは置き換え")
        XCTAssertEqual(cloud.count, 1)
        XCTAssertTrue(cloud.add(ColoredPoint(Point3(1, 0, 0), r: 0, g: 0, b: 0)))
        XCTAssertFalse(cloud.add(ColoredPoint(Point3(2, 0, 0), r: 0, g: 0, b: 0)), "上限")
        let ply = cloud.ply()
        XCTAssertTrue(ply.hasPrefix("ply\nformat ascii 1.0"))
        XCTAssertTrue(ply.contains("element vertex 2"))
    }

    func testDepthCommands() {
        let parser = IntentParser()
        XCTAssertEqual(parser.parse("前の物まで何メートル？"), .measureDistance)
        XCTAssertEqual(parser.parse("距離を測って"), .measureDistance)
        XCTAssertEqual(parser.parse("3Dスキャンを開いて"), .open(.scan3D))
        XCTAssertEqual(parser.parse("障害物警告をオンにして"), .setDepth(true))
        XCTAssertEqual(parser.parse("距離計を表示して"), .showWidget(.distance))
        XCTAssertEqual(DeepLink.command(from: URL(string: "hudnavigator://depth/measure")!), .measureDistance)
        XCTAssertEqual(AICommandCodec.command(name: "setDepth", value: "true"), .setDepth(true))
    }
}

final class MeasuredHazardTests: XCTestCase {
    func testClosingSpeedFromMeasuredDistance() throws {
        var tracker = ObjectTracker()
        let t0 = Date(timeIntervalSince1970: 1000)
        let box = NormalizedRect(x: 0.42, y: 0.4, width: 0.16, height: 0.2)
        // 同じ大きさの枠のまま（枠からは接近が分からない）、測った距離だけ 3m → 2m に近づく
        for (i, d) in [3.0, 2.6, 2.3, 2.0].enumerated() {
            let t = t0.addingTimeInterval(Double(i) * 0.25)
            _ = tracker.update([Detection(label: .car, confidence: 0.9, box: box, timestamp: t, measuredDistance: d)], at: t)
        }
        let now = t0.addingTimeInterval(0.75)
        let a = try XCTUnwrap(HazardEvaluator().assess(tracker: tracker, now: now).first)
        XCTAssertEqual(a.distance ?? 0, 2.0, accuracy: 1e-9)
        XCTAssertEqual(a.closingSpeed ?? 0, 4.0 / 3.0, accuracy: 1e-6, "1m を 0.75 秒")
        XCTAssertEqual(a.timeToContact ?? 0, 1.5, accuracy: 1e-6)
        XCTAssertEqual(a.level, .medium, "1.5 秒ちょうどは警戒")
        XCTAssertTrue(a.reason.contains("約2.0m"))
    }

    func testVeryCloseMeasuredObjectIsHigh() throws {
        var tracker = ObjectTracker()
        let t = Date()
        let box = NormalizedRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
        _ = tracker.update([Detection(label: .bicycle, confidence: 0.9, box: box, timestamp: t, measuredDistance: 0.6)], at: t)
        let a = try XCTUnwrap(HazardEvaluator().assess(tracker: tracker, now: t).first)
        XCTAssertEqual(a.level, .high)
    }
}
