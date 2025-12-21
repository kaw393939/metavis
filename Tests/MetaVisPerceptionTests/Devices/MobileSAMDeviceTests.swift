import XCTest
import CoreVideo
import MetaVisCore
@testable import MetaVisPerception

final class MobileSAMDeviceTests: XCTestCase {

    func test_mobilesam_returns_governed_missing_when_models_absent() async throws {
        // This test should be deterministic and should NOT require model artifacts.
        // When models are missing, the device must report that explicitly.
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 0.2)
        XCTAssertFalse(frames.isEmpty)

        // Force a missing model directory to ensure stable behavior.
        let device = MobileSAMDevice(options: .init(modelDirectory: "__does_not_exist__"))
        let res = await device.segment(pixelBuffer: frames[0], prompt: .init(pointTopLeft: CGPoint(x: 0.5, y: 0.5)))

        XCTAssertNil(res.mask)
        XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())
        XCTAssertTrue(res.evidenceConfidence.reasons.contains(.mobilesam_model_missing))
        XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 0.01)
    }

    func test_mobilesam_smoke_segment_center_point_if_models_present() async throws {
        // This is env-gated because models are not bundled in the repo by default.
        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_MOBILESAM_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_MOBILESAM_TESTS=1 and provide models to run this test")
        }

        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 0.2)
        XCTAssertFalse(frames.isEmpty)

        let device = MobileSAMDevice()
        let res = await device.segment(pixelBuffer: frames[0], prompt: .init(pointTopLeft: CGPoint(x: 0.5, y: 0.5)))

        // If the model is correctly wired, we should get a non-empty mask.
        if res.mask == nil {
            XCTFail("Expected a mask when models are present; got nil. Set METAVIS_MOBILESAM_MODEL_DIR to the directory containing ImageEncoder/PromptEncoder/MaskDecoder")
            return
        }

        guard let mask = res.mask else { return }
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(mask), kCVPixelFormatType_OneComponent8)
        XCTAssertTrue(res.evidenceConfidence.reasons.isEmpty, "Expected no governed failure reasons on successful inference")

        // Be conservative: just require non-trivial coverage.
        let mean = meanByteValue(mask)
        XCTAssertGreaterThan(mean, 1.0, "Expected non-empty mask coverage; got mean=\(mean)")
    }

    private func meanByteValue(_ pixelBuffer: CVPixelBuffer) -> Double {
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pixelBuffer), kCVPixelFormatType_OneComponent8)
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var sum: UInt64 = 0
        for y in 0..<height {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                sum += UInt64(row[x])
            }
        }

        let denom = max(1, width * height)
        return Double(sum) / Double(denom)
    }
}
