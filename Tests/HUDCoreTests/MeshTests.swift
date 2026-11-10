import XCTest
@testable import HUDCore

final class MeshTests: XCTestCase {
    func testKeyPackingRoundTripWithNegatives() {
        for (x, y, z) in [(0, 0, 0), (-1, 2, -3), (1_000_000, -1_000_000, 5), (-40, -40, -40)] {
            let (a, b, c) = TSDFVolume.unpack(TSDFVolume.key(x, y, z))
            XCTAssertEqual([a, b, c], [x, y, z])
        }
    }

    /// 正面 1m の壁を何度か見る → 壁の位置に、カメラ側を向いた三角形ができる
    private func wallVolume(distance: Float = 1.0, passes: Int = 3) -> TSDFVolume {
        var volume = TSDFVolume(voxelSize: 0.05)
        let origin = Point3(0, 0, 0)
        for _ in 0..<passes {
            var x: Float = -0.6
            while x <= 0.6 {
                var y: Float = -0.6
                while y <= 0.6 {
                    volume.integrate(origin: origin, hit: Point3(x, y, -distance), color: (200, 100, 50))
                    y += 0.02
                }
                x += 0.02
            }
        }
        return volume
    }

    func testWallBecomesTriangleMesh() throws {
        let mesh = wallVolume().extractMesh(minWeight: 2)
        XCTAssertGreaterThan(mesh.triangleCount, 50, "壁が三角形になる")
        XCTAssertEqual(mesh.colors.count, mesh.vertices.count * 3)
        for v in mesh.vertices {
            XCTAssertEqual(v.z, -1.0, accuracy: 0.05, "表面の位置")
        }
        // 三角形の向き：カメラ（+z）の方を向く
        var facing = 0
        var i = 0
        while i + 2 < mesh.indices.count {
            let p0 = mesh.vertices[Int(mesh.indices[i])], p1 = mesh.vertices[Int(mesh.indices[i + 1])], p2 = mesh.vertices[Int(mesh.indices[i + 2])]
            let nz = (p1.x - p0.x) * (p2.y - p0.y) - (p1.y - p0.y) * (p2.x - p0.x)
            if nz > 0 { facing += 1 }
            i += 3
        }
        XCTAssertEqual(facing, mesh.triangleCount, "すべてカメラ側を向く")
        // 色も残る
        XCTAssertTrue(mesh.colors.contains(200))
    }

    func testWeakObservationsAreIgnored() {
        XCTAssertEqual(wallVolume().extractMesh(minWeight: 100).triangleCount, 0, "見えた回数が少ない所は使わない（ノイズ除け）")
        var volume = TSDFVolume(voxelSize: 0.05)
        volume.integrate(origin: Point3(0, 0, 0), hit: Point3(0, 0, -1), color: (0, 0, 0))
        XCTAssertEqual(volume.extractMesh().triangleCount, 0, "光線 1 本では面にならない")
    }

    func testObjAndPlyFormat() throws {
        let mesh = wallVolume().extractMesh()
        let obj = mesh.obj()
        let lines = obj.split(separator: "\n")
        XCTAssertEqual(lines.filter { $0.hasPrefix("v ") }.count, mesh.vertices.count)
        let faces = lines.filter { $0.hasPrefix("f ") }
        XCTAssertEqual(faces.count, mesh.triangleCount)
        let firstFace = try XCTUnwrap(faces.first).split(separator: " ").dropFirst().compactMap { Int($0) }
        XCTAssertEqual(firstFace.count, 3)
        XCTAssertTrue(firstFace.allSatisfy { $0 >= 1 && $0 <= mesh.vertices.count }, "OBJ は 1 始まり")
        let ply = mesh.ply()
        XCTAssertTrue(ply.contains("element face \(mesh.triangleCount)"))
        XCTAssertTrue(ply.contains("element vertex \(mesh.vertices.count)"))
    }

    func testVoxelLimit() {
        var volume = TSDFVolume(voxelSize: 0.05, maxVoxels: 10)
        volume.integrate(origin: Point3(0, 0, 0), hit: Point3(0, 0, -2), color: (0, 0, 0))
        XCTAssertLessThanOrEqual(volume.count, 10)
    }
}
