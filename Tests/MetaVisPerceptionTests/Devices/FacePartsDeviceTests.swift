import XCTest
import CoreVideo
import AVFoundation
import MetaVisCore
@testable import MetaVisPerception

final class FacePartsDeviceTests: XCTestCase {

    func test_faceparts_emits_governed_confidence_and_roi_masks() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 20, maxSeconds: 1.0)
        XCTAssertFalse(frames.isEmpty)

        let device = FacePartsDevice()
        try await device.warmUp()

        var foundAnyPartMask = false
        var lastRes: FacePartsDevice.FacePartsResult?

        for pb in frames {
            let res = try await device.facePartsResult(in: pb)
            lastRes = res

            // Always validate governed confidence shape.
            XCTAssertGreaterThanOrEqual(res.evidenceConfidence.score, 0.0)
            XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 1.0)
            XCTAssertFalse(res.evidenceConfidence.sources.isEmpty)
            XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())

            if let m = res.mouthMask {
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(m), kCVPixelFormatType_OneComponent8)
                foundAnyPartMask = true
            }
            if let l = res.leftEyeMask {
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(l), kCVPixelFormatType_OneComponent8)
                foundAnyPartMask = true
            }
            if let r = res.rightEyeMask {
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(r), kCVPixelFormatType_OneComponent8)
                foundAnyPartMask = true
            }

            if foundAnyPartMask {
                break
            }
        }

        XCTAssertNotNil(lastRes)
        XCTAssertTrue(foundAnyPartMask, "Expected at least one landmark-derived part mask (mouth/eyes) on keith_talk.mov")

        // Deterministic semantics: model-missing should be surfaced only when no parsing model is available.
        let envModelPath = ProcessInfo.processInfo.environment["METAVIS_FACEPARTS_MODEL_PATH"]
        let hasEnv = (envModelPath != nil && envModelPath?.isEmpty == false)
        let hasDefault = FileManager.default.fileExists(atPath: "assets/models/face_parsing/FaceParsing.mlmodelc")
            || FileManager.default.fileExists(atPath: "assets/models/face_parsing/FaceParsing.mlpackage")
        if !hasEnv && !hasDefault {
            XCTAssertTrue(lastRes!.evidenceConfidence.reasons.contains(.faceparts_model_missing))
        }

        // If a mouth mask exists, coverage should be non-trivial.
        if let mouth = lastRes!.mouthMask {
            let coverage = meanByteValue(mouth) / 255.0
            XCTAssertGreaterThan(coverage, 0.0005, "Expected non-trivial mouth ROI coverage")

            let rect = lastRes!.mouthRectTopLeft
            XCTAssertNotNil(rect, "Expected mouthRectTopLeft when mouthMask is available")
            if let r = rect {
                XCTAssertGreaterThan(r.width, 0.0)
                XCTAssertGreaterThan(r.height, 0.0)
                XCTAssertGreaterThanOrEqual(r.minX, 0.0)
                XCTAssertGreaterThanOrEqual(r.minY, 0.0)
                XCTAssertLessThanOrEqual(r.maxX, 1.0)
                XCTAssertLessThanOrEqual(r.maxY, 1.0)
            }
        }
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
