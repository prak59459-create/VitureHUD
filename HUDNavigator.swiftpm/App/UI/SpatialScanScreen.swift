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

/// 3D スキャン（ARKit）。LiDAR があれば深さ＋メッシュ、なければ ARKit の特徴点と AI の奥行きで点群を作る。
@MainActor
@Observable
final class SpatialScanner {
    let session = ARSession()
    private(set) var pointCount = 0
    private(set) var featurePointCount = 0
    private(set) var planeCount = 0
    private(set) var meshCount = 0
    private(set) var tracking = "準備中"
    private(set) var centerDistance: Double?
    private(set) var method = ""
    private(set) var status = ""
    private(set) var measureA: SIMD3<Float>?
    private(set) var measureB: SIMD3<Float>?
    private(set) var isPaused = false
    /// 点群の表示を作り直したい（SceneKit 側が見る）
    private(set) var cloudVersion = 0

    @ObservationIgnored private(set) var cloud = VoxelPointCloud(voxelSize: 0.03, maxPoints: 400_000)
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
        method = Self.hasLiDAR ? "LiDAR の深さ＋メッシュ" : "ARKit の特徴点＋AI の奥行き（LiDAR なし）"
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
        measureA = nil
        measureB = nil
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

    /// 書き出し（PLY・色付きの点群）
    func exportPLY() -> URL? {
        let text = cloud.ply()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HUDNavigator-3D-\(formatter.string(from: Date())).ply")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            status = "書き出せませんでした：\(error.localizedDescription)"
            return nil
        }
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
        work.async { [weak self] in
            let points = Self.points(from: snapshot, depthModel: model)
            Task { @MainActor in
                guard let self else { return }
                for p in points { self.cloud.add(p) }
                self.pointCount = self.cloud.count
                self.cloudVersion += 1
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

    nonisolated private static func matrix(_ t: simd_float4x4) -> [Float] {
        [t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
         t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
         t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
         t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w]
    }

    /// 1 フレーム分の色付きの点（世界座標・m）
    nonisolated private static func points(from s: FrameSnapshot, depthModel: VNCoreMLModel?) -> [ColoredPoint] {
        let fx = Double(s.intrinsics.columns.0.x), fy = Double(s.intrinsics.columns.1.y)
        let cx = Double(s.intrinsics.columns.2.x), cy = Double(s.intrinsics.columns.2.y)
        let W = Double(s.imageSize.width), H = Double(s.imageSize.height)
        let m = matrix(s.transform)
        let gw = 96, gh = 72
        var depths: [Double?] = Array(repeating: nil, count: gw * gh)

        if let depth = s.depth, let values = DepthBufferReader.sample(depth, outW: gw, outH: gh) {
            // LiDAR：信頼度が中以上・0〜8m のみ
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
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            guard (try? VNImageRequestHandler(cvPixelBuffer: s.image, orientation: .up, options: [:]).perform([request])) != nil,
                  let obs = request.results?.first as? VNPixelBufferObservation,
                  let raw = DepthBufferReader.sample(obs.pixelBuffer, outW: gw, outH: gh) else { return featureCloud(s) }
            let finite = raw.filter { $0.isFinite }
            guard let lo = finite.min(), let hi = finite.max(), hi > lo else { return featureCloud(s) }
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
            guard let fit = DepthMath.fitInverse(pairs) else { return featureCloud(s) }
            for i in 0..<(gw * gh) {
                if let z = DepthMath.metric(rel[i], fit: fit, maxRange: 6), z > 0.2 { depths[i] = z }
            }
        } else {
            return featureCloud(s)
        }

        var pixels: [(x: Int, y: Int)] = []
        var positions: [Point3] = []
        for gy in 0..<gh {
            for gx in 0..<gw {
                guard let d = depths[gy * gw + gx] else { continue }
                let u = (Double(gx) + 0.5) / Double(gw) * W, v = (Double(gy) + 0.5) / Double(gh) * H
                let pc = Projection.backProject(u: u, v: v, depth: d, fx: fx, fy: fy, cx: cx, cy: cy)
                positions.append(Projection.transform(pc, by: m))
                pixels.append((Int(u), Int(v)))
            }
        }
        let colors = PixelSampler.rgb(s.image, points: pixels)
        var out = zip(positions, colors).map { ColoredPoint($0.0, r: $0.1.0, g: $0.1.1, b: $0.1.2) }
        out += featureCloud(s)
        return out
    }

    /// ARKit の特徴点（まばら・正確）
    nonisolated private static func featureCloud(_ s: FrameSnapshot) -> [ColoredPoint] {
        s.features.map { ColoredPoint(Point3($0.x, $0.y, $0.z), r: 0, g: 230, b: 255) }
    }
}

/// ARKit の画面（点群・平面・LiDAR メッシュ・測った線）
struct ARScanView: UIViewRepresentable {
    let scanner: SpatialScanner
    var showsMesh: Bool
    var showsPoints: Bool

    func makeCoordinator() -> Coordinator { Coordinator(scanner: scanner) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = scanner.session
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.debugOptions = [.showFeaturePoints]
        view.scene.rootNode.addChildNode(context.coordinator.cloudNode)
        view.scene.rootNode.addChildNode(context.coordinator.measureNode)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        scanner.view = view
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.showsMesh = showsMesh
        context.coordinator.cloudNode.isHidden = !showsPoints
        context.coordinator.refreshCloudIfNeeded(version: scanner.cloudVersion)
        context.coordinator.updateMeasure(a: scanner.measureA, b: scanner.measureB)
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let scanner: SpatialScanner
        let cloudNode = SCNNode()
        let measureNode = SCNNode()
        var showsMesh = true
        private var shownVersion = -1
        private var lastCloudBuild = Date.distantPast

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
            guard version != shownVersion, Date().timeIntervalSince(lastCloudBuild) > 1 || version == 0 else { return }
            shownVersion = version
            lastCloudBuild = Date()
            let points = scanner.cloud.points
            cloudNode.geometry = Self.pointGeometry(points)
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

        // 平面・メッシュの表示（SceneKit の描画スレッド）
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            if let plane = anchor as? ARPlaneAnchor {
                let node = SCNNode(geometry: Self.planeGeometry(plane))
                return node
            }
            if let mesh = anchor as? ARMeshAnchor, showsMesh {
                return SCNNode(geometry: Self.meshGeometry(mesh.geometry))
            }
            return nil
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            if let plane = anchor as? ARPlaneAnchor {
                node.geometry = Self.planeGeometry(plane)
            } else if let mesh = anchor as? ARMeshAnchor {
                node.geometry = showsMesh ? Self.meshGeometry(mesh.geometry) : nil
            }
        }

        static func planeGeometry(_ plane: ARPlaneAnchor) -> SCNGeometry {
            let g = ARSCNPlaneGeometry(device: MTLCreateSystemDefaultDevice()!)!
            g.update(from: plane.geometry)
            let m = SCNMaterial()
            m.diffuse.contents = (plane.alignment == .horizontal ? UIColor.systemGreen : UIColor.systemOrange).withAlphaComponent(0.25)
            m.isDoubleSided = true
            g.materials = [m]
            return g
        }

        static func meshGeometry(_ mesh: ARMeshGeometry) -> SCNGeometry {
            let v = mesh.vertices
            let vSource = SCNGeometrySource(buffer: v.buffer, vertexFormat: v.format, semantic: .vertex, vertexCount: v.count, dataOffset: v.offset, dataStride: v.stride)
            let f = mesh.faces
            let data = Data(bytes: f.buffer.contents(), count: f.count * f.indexCountPerPrimitive * f.bytesPerIndex)
            let element = SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: f.count, bytesPerIndex: f.bytesPerIndex)
            let g = SCNGeometry(sources: [vSource], elements: [element])
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.cyan.withAlphaComponent(0.6)
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
    @State private var showsMesh = true
    @State private var showsPoints = true
    @State private var share: ShareItem?

    var body: some View {
        ZStack {
            ARScanView(scanner: scanner, showsMesh: showsMesh, showsPoints: showsPoints)
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
                        Text("点：\(scanner.pointCount)・特徴点：\(scanner.featurePointCount)・平面：\(scanner.planeCount)\(SpatialScanner.supportsMesh ? "・メッシュ：\(scanner.meshCount)" : "")")
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
                        Text("画面をタップすると、その場所の距離・2 点間の距離を測れます").font(.caption)
                    }
                }
                .padding(10)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Toggle("点群", isOn: $showsPoints).fixedSize()
                    if SpatialScanner.supportsMesh { Toggle("メッシュ", isOn: $showsMesh).fixedSize() }
                    Spacer()
                    Button(scanner.isPaused ? "再開" : "一時停止") { scanner.isPaused ? scanner.resume() : scanner.pause() }
                    Button("消去") { scanner.clear() }
                    Button {
                        if let url = scanner.exportPLY() { share = ShareItem(url: url) }
                    } label: {
                        Label("PLY", systemImage: "square.and.arrow.up")
                    }
                    .disabled(scanner.pointCount == 0)
                }
                .buttonStyle(.borderedProminent)
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
