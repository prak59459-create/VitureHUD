import XCTest
import CoreML
import Vision
@testable import HUDNavigator

/// アプリに入れた Core ML モデルが見つかり、端末（シミュレータ）でコンパイル・読み込みできるか
final class BundledModelTests: XCTestCase {
    func testModelsAreInsideTheApp() {
        for name in ["YOLOv3Tiny", "YOLOv3Int8LUT", "DepthAnythingV2SmallF16"] {
            XCTAssertTrue(ModelStore.isBundled(name), "\(name) がアプリに入っていません")
        }
    }

    func testObjectModelCompilesAndRunsInVision() async throws {
        let ml = try await ModelStore.load(named: BundledObjectModel.yolov3Tiny.rawValue, computeUnits: .cpuOnly)
        let vn = try VNCoreMLModel(for: ml)
        // 真っ黒な画像で推論が通ること（何も見つからなくてよい）
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 416, 416, kCVPixelFormatType_32BGRA, nil, &buffer)
        let request = VNCoreMLRequest(model: vn)
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(cvPixelBuffer: try XCTUnwrap(buffer), options: [:]).perform([request])
        XCTAssertNotNil(request.results)
        // 2 回目はコンパイル済みを使う
        _ = try await ModelStore.load(named: BundledObjectModel.yolov3Tiny.rawValue, computeUnits: .cpuOnly)
    }

    func testDepthModelCompiles() async throws {
        let ml = try await ModelStore.load(named: "DepthAnythingV2SmallF16", computeUnits: .cpuOnly)
        XCTAssertNotNil(ml.modelDescription.inputDescriptionsByName["image"])
        XCTAssertNotNil(ml.modelDescription.outputDescriptionsByName["depth"])
    }
}
