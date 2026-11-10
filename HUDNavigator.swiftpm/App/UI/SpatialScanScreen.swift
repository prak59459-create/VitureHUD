import SwiftUI
import ARKit
import SceneKit
import Vision

/// カメラの画像（YCbCr 4:2:0）から色を取る
enum PixelSampler {
    static func rgb(_ pb: CVPixelBuffer, points: [(x: Int, y: Int)]) -> [(UInt8, UInt8, UInt8)] {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pb) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0),
              let cBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else {
            return points.map { _ in (200, 200, 200) }
        }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        return points.map { p in
            let x = min(w - 1, max(0, p.x)), y = min(h - 1, max(0, p.y))
            let Y = Double(yBase.load(fromByteOffset: y * yRow + x, as: UInt8.self))
            let cOff = (y / 2) * cRow + (x / 2) * 2
            let cb = Double(cBase.load(fromByteOffset: cOff, as: UInt8.self)) - 128
            let cr = Double(cBase.load(fromByteOffset: cOff + 1, as: UInt8.self)) - 128
            func c(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v))) }
            return (c(Y + 1.402 * cr), c(Y - 0.344 * cb - 0.714 * cr), c(Y + 1.772 * cb))
        }
    }
}

/// 表示のしかた
enum ScanDisplay: String, CaseIterable, Identifiable {
    /// Meta Quest の部屋スキャンのような三角形の線
    case questWire
    /// 色付きの三角形
    case colored
    /// 点群
    case points

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .questWire: return "Quest 風"
        case .colored: return "色付き"
        case .points: return "点群"
        }
    }
}

/// 三角形メッシュを作る係（スキャン用のキューの中だけで使う）
final class MeshBuilder: @unchecked Sendable {
    private(set) var volume: TSDFVolume
    var lastExtract = Date.distantPast

    init(voxelSize: Float) {
        volume = TSDFVolume(voxelSize: voxelSize)
    }

    func reset(voxelSize: Float) {
        volume = TSDFVolume(voxelSize: voxelSize)
        lastExtract = .distantPast
    }

    func integrate(_ r: SpatialScanner.FrameResult, weight: Float) {
        for p in r.meshable {
            volume.integrate(origin: r.origin, hit: p.position, color: (p.r, p.g, p.b), weight: weight)
        }
    }

    func extract() -> TriangleMesh { volume.extractMesh(minWeight: 2) }
}

/// 3D スキャン（ARKit）。毎フレームの奥行き（LiDAR／AI＋ARKit の特徴点）を重ねて、三角形のメッシュと点群を作る。
@MainActor
@Observable
final class SpatialScanner {
    let session = ARSession()
    private(set) var pointCount = 0
    private(set) var featurePointCount = 0
    private(set) var planeCount = 0
    private(set) var meshCount = 0
    private(set) var triangleCount = 0
    private(set) var tracking = "準備中"
    private(set) var centerDistance: Double?
    private(set) var method = ""
    private(set) var status = ""
    private(set) var measureA: SIMD3<Float>?
    private(set) var measureB: SIMD3<Float>?
    private(set) var isPaused = false
    /// 表示を作り直したい（SceneKit 側が見る）
    private(set) var cloudVersion = 0
    private(set) var meshVersion = 0
    /// メッシュの細かさ（m）
    private(set) var voxelSize: Float = 0.05

    @ObservationIgnored private(set) var cloud = VoxelPointCloud(voxelSize: 0.03, maxPoints: 400_000)
    @ObservationIgnored private(set) var mesh = TriangleMesh()
    @ObservationIgnored private let builder = MeshBuilder(voxelSize: 0.05)
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var lastProcess = Date.distantPast
    @ObservationIgnored private var lastCenter = Date.distantPast
    @ObservationIgnored private var depthModel: VNCoreMLModel?
    @ObservationIgnored private let work = DispatchQueue(label: "hudnavigator.scan", qos: .userInitiated)
    @ObservationIgnored weak var view: ARSCNView?

    static var hasLiDAR: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }
    static var supportsMesh: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start(sharedDepthModel: VNCoreMLModel?) {
        guard Self.isSupported else {
            status = "この端末は ARKit（空間の認識）に対応していません"
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if Self.supportsMesh { config.sceneReconstruction = .mesh }
        if Self.hasLiDAR { config.frameSemantics.insert(.sceneDepth) }
        config.environmentTexturing = .none
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isPaused = false
        method = Self.hasLiDAR ? "LiDAR の深さ → 三角形メッシュ" : "AI の奥行き＋ARKit → 三角形メッシュ（LiDAR なし）"
        depthModel = sharedDepthModel
        if !Self.hasLiDAR && depthModel == nil {
            status = "AI の奥行きモデルを準備中…"
            Task {
                if let ml = try? await ModelStore.load(named: "DepthAnythingV2SmallF16"), let vn = try? VNCoreMLModel(for: ml) {
                    self.depthModel = vn
                    self.status = ""
                } else {
                    self.status = "AI の奥行きモデルを読み込めません（特徴点だけで記録します）"
                }
            }
        }
    }

    func pause() {
        session.pause()
        isPaused = true
    }

    func resume() {
        guard let config = session.configuration else { return }
        session.run(config)
        isPaused = false
    }

    func clear() {
        cloud.removeAll()
        pointCount = 0
        cloudVersion += 1
        resetMesh()
        measureA = nil
        measureB = nil
    }

    /// メッシュの細かさを変える（作り直し）
    func setVoxelSize(_ size: Float) {
        guard size != voxelSize else { return }
        voxelSize = size
        resetMesh()
    }

    private func resetMesh() {
        let builder = self.builder
        let size = voxelSize
        work.async { builder.reset(voxelSize: size) }
        mesh = TriangleMesh()
        triangleCount = 0
        meshVersion += 1
    }

    var measuredDistance: Double? {
        guard let a = measureA, let b = measureB else { return nil }
        return Double(simd_distance(a, b))
    }

    func tapMeasure(at point: CGPoint) {
        guard let view, let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .any),
              let hit = session.raycast(query).first else {
            status = "そこまでの距離を測れません（平らな面や特徴のある所をタップ）"
            return
        }
        let p = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
        if measureA == nil || measureB != nil {
            measureA = p
            measureB = nil
            status = "もう 1 点タップすると 2 点間の距離を測ります"
        } else {
            measureB = p
            status = ""
        }
    }

    // MARK: 書き出し

    private func writeExport(_ text: String, kind: String, ext: String) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HUDNavigator-3D-\(kind)-\(formatter.string(from: Date())).\(ext)")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            status = "書き出せませんでした：\(error.localizedDescription)"
            return nil
        }
    }

    /// OBJ（三角形メッシュ・頂点色付き）
    func exportOBJ() -> URL? {
        guard !mesh.isEmpty else {
            status = "まだ三角形がありません。ゆっくり動かして、同じ所を何度か映してください。"
            return nil
        }
        return writeExport(mesh.obj(), kind: "mesh", ext: "obj")
    }

    /// PLY（三角形メッシュ・頂点色付き）
    func exportMeshPLY() -> URL? {
        guard !mesh.isEmpty else {
            status = "まだ三角形がありません。"
            return nil
        }
        return writeExport(mesh.ply(), kind: "mesh", ext: "ply")
    }

    /// PLY（色付きの点群）
    func exportPLY() -> URL? {
        writeExport(cloud.ply(), kind: "points", ext: "ply")
    }

    /// OBJ（LiDAR の端末で ARKit が作ったメッシュ）
    func exportLiDARMeshOBJ() -> URL? {
        var out = TriangleMesh()
        for case let anchor as ARMeshAnchor in session.currentFrame?.anchors ?? [] {
            let g = anchor.geometry
            let base = UInt32(out.vertices.count)
            let v = g.vertices
            let vp = v.buffer.contents()
            for i in 0..<v.count {
                let f = vp.advanced(by: v.offset + v.stride * i).assumingMemoryBound(to: Float.self)
                let w = anchor.transform * SIMD4<Float>(f[0], f[1], f[2], 1)
                out.vertices.append(Point3(w.x, w.y, w.z))
                out.colors += [200, 220, 230]
            }
            let faces = g.faces
            let fp = faces.buffer.contents()
            for i in 0..<(faces.count * faces.indexCountPerPrimitive) {
                let idx: UInt32 = faces.bytesPerIndex == 2
                    ? UInt32(fp.load(fromByteOffset: i * 2, as: UInt16.self))
                    : fp.load(fromByteOffset: i * 4, as: UInt32.self)
                out.indices.append(base + idx)
            }
        }
        guard !out.isEmpty else {
            status = "LiDAR のメッシュがまだありません"
            return nil
        }
        return writeExport(out.obj(name: "LiDARMesh"), kind: "lidar-mesh", ext: "obj")
    }

    // MARK: フレームごと（ARSession のデリゲートから・メインスレッド）

    func handle(_ frame: ARFrame) {
        switch frame.camera.trackingState {
        case .normal: tracking = "良好"
        case .notAvailable: tracking = "使えません"
        case .limited(let r):
            switch r {
            case .initializing: tracking = "準備中（ゆっくり動かしてください）"
            case .excessiveMotion: tracking = "動きが速すぎます"
            case .insufficientFeatures: tracking = "模様が少なく認識しにくい場所です"
            case .relocalizing: tracking = "位置を探しています"
            @unknown default: tracking = "制限あり"
            }
        }
        featurePointCount = frame.rawFeaturePoints?.points.count ?? 0
        let now = Date()
        if now.timeIntervalSince(lastCenter) > 0.2 {
            lastCenter = now
            updateCenterDistance(frame)
        }
        guard case .normal = frame.camera.trackingState, !busy, now.timeIntervalSince(lastProcess) > (Self.hasLiDAR ? 0.4 : 0.8) else { return }
        lastProcess = now
        busy = true
        let snapshot = FrameSnapshot(frame: frame)
        let model = depthModel
        let builder = self.builder
        let weight: Float = Self.hasLiDAR ? 1 : 0.7
        work.async { [weak self] in
            let result = Self.points(from: snapshot, depthModel: model)
            // 奥行きをボクセルに重ね、1.2 秒ごとに三角形を作り直す
            builder.integrate(result, weight: weight)
            var newMesh: TriangleMesh?
            if Date().timeIntervalSince(builder.lastExtract) > 1.2 {
                builder.lastExtract = Date()
                newMesh = builder.extract()
            }
            Task { @MainActor in
                guard let self else { return }
                for p in result.cloud { self.cloud.add(p) }
                self.pointCount = self.cloud.count
                self.cloudVersion += 1
                if let m = newMesh {
                    self.mesh = m
                    self.triangleCount = m.triangleCount
                    self.meshVersion += 1
                }
                self.busy = false
            }
        }
    }

    private func updateCenterDistance(_ frame: ARFrame) {
        if let depth = frame.sceneDepth?.depthMap,
           let v = DepthBufferReader.sample(depth, outW: 1, outH: 1)?.first, v.isFinite, v > 0 {
            centerDistance = Double(v)
            return
        }
        guard let view else { return }
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        if let q = view.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any), let hit = session.raycast(q).first {
            let cam = frame.camera.transform.columns.3
            let p = hit.worldTransform.columns.3
            centerDistance = Double(simd_distance(SIMD3(cam.x, cam.y, cam.z), SIMD3(p.x, p.y, p.z)))
        } else {
            centerDistance = nil
        }
    }

    /// ARFrame から必要な物だけ取り出す（フレームを長く持たないため）
    struct FrameSnapshot: @unchecked Sendable {
        let image: CVPixelBuffer
        let depth: CVPixelBuffer?
        let confidence: CVPixelBuffer?
        let intrinsics: simd_float3x3
        let transform: simd_float4x4
        let imageSize: CGSize
        let features: [SIMD3<Float>]

        init(frame: ARFrame) {
            image = frame.capturedImage
            depth = frame.sceneDepth?.depthMap
            confidence = frame.sceneDepth?.confidenceMap
            intrinsics = frame.camera.intrinsics
            transform = frame.camera.transform
            imageSize = frame.camera.imageResolution
            features = frame.rawFeaturePoints.map { Array($0.points) } ?? []
        }
    }

    /// 1 フレーム分の結果：点群に足す点・メッシュに使う点（端のちらつきを除いたもの）・カメラの位置
    struct FrameResult: Sendable {
        var cloud: [ColoredPoint]
        var meshable: [ColoredPoint]
        var origin: Point3
    }

    nonisolated private static func matrix(_ t: simd_float4x4) -> [Float] {
        [t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
         t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
         t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
         t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w]
    }

    nonisolated private static func points(from s: FrameSnapshot, depthModel: VNCoreMLModel?) -> FrameResult {
        let fx = Double(s.intrinsics.columns.0.x), fy = Double(s.intrinsics.columns.1.y)
        let cx = Double(s.intrinsics.columns.2.x), cy = Double(s.intrinsics.columns.2.y)
        let W = Double(s.imageSize.width), H = Double(s.imageSize.height)
        let m = matrix(s.transform)
        let origin = Point3(s.transform.columns.3.x, s.transform.columns.3.y, s.transform.columns.3.z)
        let fallback = FrameResult(cloud: featureCloud(s), meshable: [], origin: origin)
        let gw = 96, gh = 72
        var depths: [Double?] = Array(repeating: nil, count: gw * gh)
        let meshRange: Double

        if let depth = s.depth, let values = DepthBufferReader.sample(depth, outW: gw, outH: gh) {
            // LiDAR：信頼度が中以上・0〜8m のみ
            meshRange = 5
            let conf = s.confidence.flatMap { c -> [Float]? in
                CVPixelBufferLockBaseAddress(c, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(c, .readOnly) }
                guard let base = CVPixelBufferGetBaseAddress(c) else { return nil }
                let w = CVPixelBufferGetWidth(c), h = CVPixelBufferGetHeight(c), row = CVPixelBufferGetBytesPerRow(c)
                var out = [Float](repeating: 0, count: gw * gh)
                for y in 0..<gh { for x in 0..<gw {
                    let sx = min(w - 1, x * w / gw), sy = min(h - 1, y * h / gh)
                    out[y * gw + x] = Float(base.load(fromByteOffset: sy * row + sx, as: UInt8.self))
                } }
                return out
            }
            for i in 0..<(gw * gh) {
                let v = Double(values[i])
                if v.isFinite, v > 0.1, v < 8, (conf?[i] ?? 2) >= 1 { depths[i] = v }
            }
        } else if let model = depthModel {
            // LiDAR なし：AI の相対値を ARKit の特徴点（m）に合わせて換算
            meshRange = 4
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            guard (try? VNImageRequestHandler(cvPixelBuffer: s.image, orientation: .up, options: [:]).perform([request])) != nil,
                  let obs = request.results?.first as? VNPixelBufferObservation,
                  let raw = DepthBufferReader.sample(obs.pixelBuffer, outW: gw, outH: gh) else { return fallback }
            let finite = raw.filter { $0.isFinite }
            guard let lo = finite.min(), let hi = finite.max(), hi > lo else { return fallback }
            let rel = raw.map { Double(($0 - lo) / (hi - lo)) }
            let inv = simd_inverse(s.transform)
            var pairs: [(d: Double, z: Double)] = []
            for f in s.features {
                let pc = inv * SIMD4<Float>(f, 1)
                let z = Double(-pc.z)
                guard z > 0.2, z < 10 else { continue }
                let u = Double(pc.x) * fx / z + cx, v = cy - Double(pc.y) * fy / z
                guard u >= 0, u < W, v >= 0, v < H else { continue }
                let gx = min(gw - 1, Int(u / W * Double(gw))), gy = min(gh - 1, Int(v / H * Double(gh)))
                pairs.append((rel[gy * gw + gx], z))
            }
            guard let fit = DepthMath.fitInverse(pairs) else { return fallback }
            for i in 0..<(gw * gh) {
                if let z = DepthMath.metric(rel[i], fit: fit, maxRange: 6), z > 0.2 { depths[i] = z }
            }
        } else {
            return fallback
        }

        // 物の境目（隣と奥行きが大きく違う所）は、浮いた点になりやすいのでメッシュに使わない
        func isSmooth(_ gx: Int, _ gy: Int, _ d: Double) -> Bool {
            for (nx, ny) in [(gx + 1, gy), (gx - 1, gy), (gx, gy + 1), (gx, gy - 1)] where nx >= 0 && nx < gw && ny >= 0 && ny < gh {
                if let dn = depths[ny * gw + nx], abs(dn - d) / d > 0.1 { return false }
            }
            return true
        }

        var pixels: [(x: Int, y: Int)] = []
        var positions: [Point3] = []
        var smooth: [Bool] = []
        for gy in 0..<gh {
            for gx in 0..<gw {
                guard let d = depths[gy * gw + gx] else { continue }
                let u = (Double(gx) + 0.5) / Double(gw) * W, v = (Double(gy) + 0.5) / Double(gh) * H
                let pc = Projection.backProject(u: u, v: v, depth: d, fx: fx, fy: fy, cx: cx, cy: cy)
                positions.append(Projection.transform(pc, by: m))
                pixels.append((Int(u), Int(v)))
                smooth.append(d <= meshRange && isSmooth(gx, gy, d))
            }
        }
        let colors = PixelSampler.rgb(s.image, points: pixels)
        let dense = zip(positions, colors).map { ColoredPoint($0.0, r: $0.1.0, g: $0.1.1, b: $0.1.2) }
        let meshable = zip(dense, smooth).filter { $0.1 }.map { $0.0 }
        return FrameResult(cloud: dense + featureCloud(s), meshable: meshable, origin: origin)
    }

    /// ARKit の特徴点（まばら・正確）
    nonisolated private static func featureCloud(_ s: FrameSnapshot) -> [ColoredPoint] {
        s.features.map { ColoredPoint(Point3($0.x, $0.y, $0.z), r: 0, g: 230, b: 255) }
    }
}

/// ARKit の画面（三角形メッシュ・点群・平面・LiDAR メッシュ・測った線）
struct ARScanView: UIViewRepresentable {
    let scanner: SpatialScanner
    var display: ScanDisplay
    var showsLiDARMesh: Bool

    func makeCoordinator() -> Coordinator { Coordinator(scanner: scanner) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = scanner.session
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.debugOptions = [.showFeaturePoints]
        view.scene.rootNode.addChildNode(context.coordinator.cloudNode)
        view.scene.rootNode.addChildNode(context.coordinator.meshFillNode)
        view.scene.rootNode.addChildNode(context.coordinator.meshWireNode)
        view.scene.rootNode.addChildNode(context.coordinator.measureNode)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        scanner.view = view
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        let c = context.coordinator
        c.showsLiDARMesh = showsLiDARMesh
        c.cloudNode.isHidden = display != .points
        c.meshFillNode.isHidden = display == .points
        c.meshWireNode.isHidden = display == .points
        if display == .points {
            c.refreshCloudIfNeeded(version: scanner.cloudVersion)
        }
        c.refreshMeshIfNeeded(version: scanner.meshVersion, display: display)
        c.updateMeasure(a: scanner.measureA, b: scanner.measureB)
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let scanner: SpatialScanner
        let cloudNode = SCNNode()
        let meshFillNode = SCNNode()
        let meshWireNode = SCNNode()
        let measureNode = SCNNode()
        var showsLiDARMesh = false
        private var shownCloudVersion = -1
        private var lastCloudBuild = Date.distantPast
        private var shownMesh: (version: Int, display: ScanDisplay)?

        init(scanner: SpatialScanner) {
            self.scanner = scanner
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let view = g.view else { return }
            let p = g.location(in: view)
            MainActor.assumeIsolated { scanner.tapMeasure(at: p) }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            MainActor.assumeIsolated { scanner.handle(frame) }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { countAnchors(session) }
        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) { countAnchors(session) }

        private func countAnchors(_ session: ARSession) {
            let anchors = session.currentFrame?.anchors ?? []
            let planes = anchors.filter { $0 is ARPlaneAnchor }.count
            let meshes = anchors.filter { $0 is ARMeshAnchor }.count
            MainActor.assumeIsolated {
                scanner.setAnchorCounts(planes: planes, meshes: meshes)
            }
        }

        /// 点群の表示（1 秒に 1 回まで作り直す）
        @MainActor
        func refreshCloudIfNeeded(version: Int) {
            guard version != shownCloudVersion, Date().timeIntervalSince(lastCloudBuild) > 1 || shownCloudVersion < 0 else { return }
            shownCloudVersion = version
            lastCloudBuild = Date()
            cloudNode.geometry = Self.pointGeometry(scanner.cloud.points)
        }

        /// 三角形メッシュの表示（新しいメッシュができたとき・表示を変えたとき）
        @MainActor
        func refreshMeshIfNeeded(version: Int, display: ScanDisplay) {
            if let shown = shownMesh, shown.version == version, shown.display == display { return }
            shownMesh = (version, display)
            let mesh = scanner.mesh
            guard !mesh.isEmpty, display != .points else {
                meshFillNode.geometry = nil
                meshWireNode.geometry = nil
                return
            }
            let vertices = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
            let vSource = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)

            // 面
            var sources = [vSource]
            if display == .colored {
                var colors: [Float] = []
                colors.reserveCapacity(mesh.colors.count)
                for c in mesh.colors { colors.append(Float(c) / 255) }
                let cData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
                sources.append(SCNGeometrySource(data: cData, semantic: .color, vectorCount: mesh.vertices.count, usesFloatComponents: true,
                                                 componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                                 dataStride: MemoryLayout<Float>.size * 3))
            }
            let fill = SCNGeometry(sources: sources, elements: [element])
            let fm = SCNMaterial()
            fm.lightingModel = .constant
            fm.isDoubleSided = true
            if display == .colored {
                fm.diffuse.contents = UIColor.white
            } else {
                // Quest 風：面はうっすら暗く、線を目立たせる
                fm.diffuse.contents = UIColor(red: 0.05, green: 0.12, blue: 0.18, alpha: 1)
                fm.transparency = 0.35
                fm.writesToDepthBuffer = false
            }
            fill.materials = [fm]
            meshFillNode.geometry = fill

            // 三角形の線
            let wire = SCNGeometry(sources: [vSource], elements: [element])
            let wm = SCNMaterial()
            wm.lightingModel = .constant
            wm.fillMode = .lines
            wm.isDoubleSided = true
            wm.diffuse.contents = display == .questWire
                ? UIColor(red: 0.78, green: 0.95, blue: 1.0, alpha: 1)
                : UIColor(white: 1, alpha: 1)
            wm.transparency = display == .questWire ? 0.85 : 0.25
            wire.materials = [wm]
            meshWireNode.geometry = wire
        }

        static func pointGeometry(_ points: [ColoredPoint]) -> SCNGeometry? {
            guard !points.isEmpty else { return nil }
            let shown = points.count > 150_000 ? Array(points.prefix(150_000)) : points
            let vertices = shown.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
            var colors: [Float] = []
            colors.reserveCapacity(shown.count * 3)
            for p in shown { colors += [Float(p.r) / 255, Float(p.g) / 255, Float(p.b) / 255] }
            let vSource = SCNGeometrySource(vertices: vertices)
            let cData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
            let cSource = SCNGeometrySource(data: cData, semantic: .color, vectorCount: shown.count, usesFloatComponents: true,
                                            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 3)
            let indices = (0..<UInt32(shown.count)).map { $0 }
            let iData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
            let element = SCNGeometryElement(data: iData, primitiveType: .point, primitiveCount: shown.count, bytesPerIndex: MemoryLayout<UInt32>.size)
            element.pointSize = 4
            element.minimumPointScreenSpaceRadius = 1.5
            element.maximumPointScreenSpaceRadius = 5
            let g = SCNGeometry(sources: [vSource, cSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            g.materials = [material]
            return g
        }

        @MainActor
        func updateMeasure(a: SIMD3<Float>?, b: SIMD3<Float>?) {
            measureNode.childNodes.forEach { $0.removeFromParentNode() }
            for p in [a, b].compactMap({ $0 }) {
                let s = SCNNode(geometry: SCNSphere(radius: 0.012))
                s.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
                s.simdPosition = p
                measureNode.addChildNode(s)
            }
            if let a, let b {
                let length = simd_distance(a, b)
                let line = SCNNode(geometry: SCNCylinder(radius: 0.004, height: CGFloat(length)))
                line.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
                line.simdPosition = (a + b) / 2
                line.simdLook(at: b, up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 1, 0))
                measureNode.addChildNode(line)
            }
        }

        // 平面・LiDAR メッシュの表示（SceneKit の描画スレッド）
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            if let plane = anchor as? ARPlaneAnchor {
                return SCNNode(geometry: Self.planeGeometry(plane))
            }
            if let mesh = anchor as? ARMeshAnchor {
                return SCNNode(geometry: showsLiDARMesh ? Self.lidarMeshGeometry(mesh.geometry) : nil)
            }
            return nil
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            if let plane = anchor as? ARPlaneAnchor {
                node.geometry = Self.planeGeometry(plane)
            } else if let mesh = anchor as? ARMeshAnchor {
                node.geometry = showsLiDARMesh ? Self.lidarMeshGeometry(mesh.geometry) : nil
            }
        }

        static func planeGeometry(_ plane: ARPlaneAnchor) -> SCNGeometry {
            let g = ARSCNPlaneGeometry(device: MTLCreateSystemDefaultDevice()!)!
            g.update(from: plane.geometry)
            let m = SCNMaterial()
            m.diffuse.contents = (plane.alignment == .horizontal ? UIColor.systemGreen : UIColor.systemOrange).withAlphaComponent(0.12)
            m.isDoubleSided = true
            g.materials = [m]
            return g
        }

        static func lidarMeshGeometry(_ mesh: ARMeshGeometry) -> SCNGeometry {
            let v = mesh.vertices
            let vSource = SCNGeometrySource(buffer: v.buffer, vertexFormat: v.format, semantic: .vertex, vertexCount: v.count, dataOffset: v.offset, dataStride: v.stride)
            let f = mesh.faces
            let data = Data(bytes: f.buffer.contents(), count: f.count * f.indexCountPerPrimitive * f.bytesPerIndex)
            let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: f.count, bytesPerIndex: f.bytesPerIndex)
            let g = SCNGeometry(sources: [vSource], elements: [element])
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.orange.withAlphaComponent(0.6)
            m.fillMode = .lines
            m.isDoubleSided = true
            g.materials = [m]
            return g
        }
    }
}

extension SpatialScanner {
    func setAnchorCounts(planes: Int, meshes: Int) {
        planeCount = planes
        meshCount = meshes
    }
}

struct SpatialScanScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scanner = SpatialScanner()
    @State private var display: ScanDisplay = .questWire
    @State private var showsLiDARMesh = false
    @State private var share: ShareItem?

    var body: some View {
        ZStack {
            ARScanView(scanner: scanner, display: display, showsLiDARMesh: showsLiDARMesh)
                .ignoresSafeArea()
            // 中心の照準
            ZStack {
                Circle().stroke(Color.yellow, lineWidth: 2).frame(width: 28, height: 28)
                Rectangle().fill(Color.yellow).frame(width: 2, height: 10)
                Rectangle().fill(Color.yellow).frame(width: 10, height: 2)
            }
            .allowsHitTesting(false)
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scanner.method).font(.caption.bold())
                        Text("認識：\(scanner.tracking)").font(.caption)
                        Text("三角形：\(scanner.triangleCount)・点：\(scanner.pointCount)・平面：\(scanner.planeCount)\(SpatialScanner.supportsMesh ? "・LiDAR メッシュ：\(scanner.meshCount)" : "")")
                            .font(.caption.monospacedDigit())
                        if !scanner.status.isEmpty { Text(scanner.status).font(.caption).foregroundStyle(.yellow) }
                    }
                    .padding(10)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title)
                    }
                    .accessibilityLabel("閉じる")
                }
                Spacer()
                VStack(spacing: 6) {
                    Text(scanner.centerDistance.map { "中心まで \(String(format: "%.2f", $0)) m" } ?? "中心：測定中…")
                        .font(.title2.bold().monospacedDigit())
                    if let d = scanner.measuredDistance {
                        Text("2 点間 \(String(format: "%.2f", d)) m").font(.headline.monospacedDigit()).foregroundStyle(.yellow)
                    } else {
                        Text("ゆっくり部屋を見回すと三角形のメッシュになります。タップで距離を測れます").font(.caption)
                    }
                }
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                VStack(spacing: 8) {
                    Picker("表示", selection: $display) {
                        ForEach(ScanDisplay.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Menu {
                            Picker("細かさ", selection: Binding(get: { scanner.voxelSize }, set: { scanner.setVoxelSize($0) })) {
                                Text("細かい（3cm・重い）").tag(Float(0.03))
                                Text("ふつう（5cm）").tag(Float(0.05))
                                Text("粗い（8cm・軽い）").tag(Float(0.08))
                            }
                            if SpatialScanner.supportsMesh {
                                Toggle("LiDAR のメッシュも表示", isOn: $showsLiDARMesh)
                            }
                        } label: {
                            Label("設定", systemImage: "slider.horizontal.3")
                        }
                        Spacer()
                        Button(scanner.isPaused ? "再開" : "一時停止") { scanner.isPaused ? scanner.resume() : scanner.pause() }
                        Button("消去") { scanner.clear() }
                        Menu {
                            Button("OBJ（三角形メッシュ・色付き）") { if let url = scanner.exportOBJ() { share = ShareItem(url: url) } }
                            Button("PLY（三角形メッシュ・色付き）") { if let url = scanner.exportMeshPLY() { share = ShareItem(url: url) } }
                            Button("PLY（点群）") { if let url = scanner.exportPLY() { share = ShareItem(url: url) } }
                            if SpatialScanner.supportsMesh {
                                Button("OBJ（LiDAR のメッシュ）") { if let url = scanner.exportLiDARMeshOBJ() { share = ShareItem(url: url) } }
                            }
                        } label: {
                            Label("書き出し", systemImage: "square.and.arrow.up")
                        }
                        .disabled(scanner.pointCount == 0 && scanner.triangleCount == 0)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            }
            .foregroundStyle(.white)
            .padding()
        }
        .onAppear {
            model.camera.setSuspendedForAR(true)
            scanner.start(sharedDepthModel: model.depth.ai.model)
        }
        .onDisappear {
            scanner.pause()
            model.camera.setSuspendedForAR(false)
        }
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        // グラスの HUD（距離ウィジェット・照準）にも中央の距離を出す
        .onChange(of: scanner.centerDistance) { _, d in model.depth.ingestExternalCenter(d) }
    }
}
