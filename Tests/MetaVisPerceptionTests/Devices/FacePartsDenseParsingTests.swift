import XCTest
import CoreVideo
import MetaVisCore
@testable import MetaVisPerception

final class FacePartsDenseParsingTests: XCTestCase {

    func test_faceparts_dense_parsing_smoke_if_model_present() async throws {
        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_FACEPARSING_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_FACEPARSING_TESTS=1 to run dense face-parsing tests")
        }

        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 0.2)
        XCTAssertFalse(frames.isEmpty)

        let device = FacePartsDevice()
        try await device.warmUp()

        let res = try await device.facePartsResult(in: frames[0])

        // Dense parsing must be present when models are provided.
        guard let dense = res.denseParsing else {
            XCTFail("Expected dense parsing outputs when METAVIS_RUN_FACEPARSING_TESTS=1. Provide a model via METAVIS_FACEPARTS_MODEL_PATH or assets/models/face_parsing/FaceParsing.{mlmodelc|mlpackage}.")
            return
        }

        XCTAssertEqual(CVPixelBufferGetPixelFormatType(dense.labelMap), kCVPixelFormatType_OneComponent8)
        XCTAssertGreaterThan(CVPixelBufferGetWidth(dense.labelMap), 32)
        XCTAssertGreaterThan(CVPixelBufferGetHeight(dense.labelMap), 32)

        // Reliability-first: we expect at least skin to be non-trivial on a talking-head clip.
        if let skin = dense.skinMask {
            XCTAssertEqual(CVPixelBufferGetPixelFormatType(skin), kCVPixelFormatType_OneComponent8)
            let skinCoverage = meanByteValue(skin) / 255.0
            XCTAssertGreaterThan(skinCoverage, 0.01, "Expected non-trivial skin coverage; got \(skinCoverage)")
        } else {
            XCTFail("Expected skinMask to be present for common face-parsing label sets")
        }

        // On success, we should not be reporting missing/failed parsing reasons.
        XCTAssertFalse(res.evidenceConfidence.reasons.contains(.faceparts_model_missing))
        XCTAssertFalse(res.evidenceConfidence.reasons.contains(.faceparts_infer_failed))
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
