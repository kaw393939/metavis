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

    func test_mobilesam_reuses_encoder_embedding_on_same_frame() async throws {
        // Env-gated: requires MobileSAM models locally.
        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_MOBILESAM_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_MOBILESAM_TESTS=1 and provide models to run this test")
        }

        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 0.2)
        XCTAssertFalse(frames.isEmpty)
        let frame = frames[0]

        let device = MobileSAMDevice()

        let res1 = await device.segment(pixelBuffer: frame, prompt: .init(pointTopLeft: CGPoint(x: 0.5, y: 0.5)))
        guard res1.mask != nil else {
            XCTFail("Expected a mask when models are present; got nil. Set METAVIS_MOBILESAM_MODEL_DIR to the directory containing ImageEncoder/PromptEncoder/MaskDecoder")
            return
        }

        let res2 = await device.segment(pixelBuffer: frame, prompt: .init(pointTopLeft: CGPoint(x: 0.55, y: 0.55)))
        XCTAssertEqual(res2.metrics.encoderReused, true, "Expected encoder embedding cache reuse on same-frame second prompt")
    }

    func test_mobilesam_prompt_changes_mask_on_same_frame() async throws {
        // Env-gated: requires MobileSAM models locally.
        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_MOBILESAM_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_MOBILESAM_TESTS=1 and provide models to run this test")
        }

        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 0.2)
        XCTAssertFalse(frames.isEmpty)
        let frame = frames[0]

        let device = MobileSAMDevice()

        let resA = await device.segment(pixelBuffer: frame, prompt: .init(pointTopLeft: CGPoint(x: 0.35, y: 0.55)))
        guard let maskA = resA.mask else {
            XCTFail("Expected a mask when models are present; got nil. Set METAVIS_MOBILESAM_MODEL_DIR to the directory containing ImageEncoder/PromptEncoder/MaskDecoder")
            return
        }

        let resB = await device.segment(pixelBuffer: frame, prompt: .init(pointTopLeft: CGPoint(x: 0.70, y: 0.55)))
        guard let maskB = resB.mask else {
            XCTFail("Expected a mask when models are present; got nil on second prompt")
            return
        }

        // The two prompts should select different regions most of the time.
        // We avoid strict IoU thresholds (model-variant sensitive) and instead assert the masks aren't identical.
        let diffRatio = differingPixelRatio(maskA, maskB)
        XCTAssertGreaterThan(diffRatio, 0.001, "Expected prompt to affect output (diffRatio=\(diffRatio))")
    }

    func test_mobilesam_cachekey_reuses_encoder_across_frame_copies() async throws {
        // Env-gated: requires MobileSAM models locally.
        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_MOBILESAM_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_MOBILESAM_TESTS=1 and provide models to run this test")
        }

        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 0.2)
        XCTAssertFalse(frames.isEmpty)
        let frameA = frames[0]
        let frameB = try clonePixelBuffer(frameA)

        let device = MobileSAMDevice()

        let key = MobileSAMSegmentationService.CacheKey.make(
            sourceKey: url.standardizedFileURL.absoluteString,
            timeSeconds: 0.0,
            width: CVPixelBufferGetWidth(frameA),
            height: CVPixelBufferGetHeight(frameA)
        )

        let res1 = await device.segment(pixelBuffer: frameA, prompt: .init(pointTopLeft: CGPoint(x: 0.5, y: 0.55)), cacheKey: key)
        guard res1.mask != nil else {
            XCTFail("Expected a mask when models are present; got nil")
            return
        }

        let res2 = await device.segment(pixelBuffer: frameB, prompt: .init(pointTopLeft: CGPoint(x: 0.52, y: 0.55)), cacheKey: key)
        XCTAssertEqual(res2.metrics.encoderReused, true, "Expected cacheKey-based encoder reuse across frame copies")
    }

    private func clonePixelBuffer(_ src: CVPixelBuffer) throws -> CVPixelBuffer {
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)
        let fmt = CVPixelBufferGetPixelFormatType(src)

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferPixelFormatTypeKey as String: Int(fmt),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, fmt, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let dst = out else {
            throw NSError(domain: "MobileSAMDeviceTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer clone"])
        }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }

        guard let baseS = CVPixelBufferGetBaseAddress(src), let baseD = CVPixelBufferGetBaseAddress(dst) else {
            throw NSError(domain: "MobileSAMDeviceTests", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing base address"])
        }

        let bprS = CVPixelBufferGetBytesPerRow(src)
        let bprD = CVPixelBufferGetBytesPerRow(dst)
        let rowBytes = min(bprS, bprD)
        for y in 0..<h {
            memcpy(baseD.advanced(by: y * bprD), baseS.advanced(by: y * bprS), rowBytes)
        }

        return dst
    }

    private func differingPixelRatio(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Double {
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(a), kCVPixelFormatType_OneComponent8)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(b), kCVPixelFormatType_OneComponent8)
        XCTAssertEqual(CVPixelBufferGetWidth(a), CVPixelBufferGetWidth(b))
        XCTAssertEqual(CVPixelBufferGetHeight(a), CVPixelBufferGetHeight(b))

        CVPixelBufferLockBaseAddress(a, .readOnly)
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(b, .readOnly)
            CVPixelBufferUnlockBaseAddress(a, .readOnly)
        }

        guard let baseA = CVPixelBufferGetBaseAddress(a), let baseB = CVPixelBufferGetBaseAddress(b) else { return 0.0 }
        let w = CVPixelBufferGetWidth(a)
        let h = CVPixelBufferGetHeight(a)
        let bprA = CVPixelBufferGetBytesPerRow(a)
        let bprB = CVPixelBufferGetBytesPerRow(b)

        var diff: UInt64 = 0
        for y in 0..<h {
            let rowA = baseA.advanced(by: y * bprA).assumingMemoryBound(to: UInt8.self)
            let rowB = baseB.advanced(by: y * bprB).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w {
                if rowA[x] != rowB[x] { diff += 1 }
            }
        }
        let denom = max(1, w * h)
        return Double(diff) / Double(denom)
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
