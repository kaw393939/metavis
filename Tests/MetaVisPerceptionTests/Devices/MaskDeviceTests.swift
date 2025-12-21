import XCTest
import CoreVideo
@testable import MetaVisPerception

final class MaskDeviceTests: XCTestCase {

    func test_foreground_lift_generates_mask() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 3, maxSeconds: 1.0)

        let device = MaskDevice()
        try await device.warmUp(kind: .foreground)

        let mask = try await device.generateMask(in: frames[0], kind: .foreground)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(mask), kCVPixelFormatType_OneComponent8)

        let mean = meanByteValue(mask)
        XCTAssertGreaterThan(mean, 10.0, "Expected non-trivial foreground/person mask (mean>10). Got \(mean)")
    }

    func test_foreground_lift_emits_evidence_confidence() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 3, maxSeconds: 1.0)

        let device = MaskDevice()
        try await device.warmUp(kind: .foreground)

        let res = try await device.generateMaskResult(in: frames[0], kind: .foreground)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(res.mask), kCVPixelFormatType_OneComponent8)

        // EvidenceConfidence should be governed and deterministic.
        XCTAssertGreaterThanOrEqual(res.evidenceConfidence.score, 0.0)
        XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 1.0)
        XCTAssertFalse(res.evidenceConfidence.sources.isEmpty)
        XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())
        XCTAssertGreaterThan(res.metrics.coverage, 0.0)
    }

    func test_mask_stability_is_reasonable_without_warp() async throws {
        // Sprint 24a calls for warp-based stability (flow). Until FlowDevice exists,
        // validate a simpler invariance: mask coverage shouldn't fluctuate wildly frame-to-frame.
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        // ~1s worth of frames; should be enough to evaluate stability without becoming slow.
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 20, maxSeconds: 1.0)

        let device = MaskDevice()
        try await device.warmUp(kind: .foreground)

        var means: [Double] = []
        means.reserveCapacity(frames.count)

        for pb in frames {
            let mask = try await device.generateMask(in: pb, kind: .foreground)
            means.append(meanByteValue(mask))
        }

        // Stability: adjacent-frame mean should not jump massively.
        // Threshold chosen to be robust across machines while still catching flicker.
        for i in 1..<means.count {
            let delta = abs(means[i] - means[i - 1])
            XCTAssertLessThan(delta, 35.0, "Mask mean changed too much between adjacent frames: \(means[i - 1]) -> \(means[i])")
        }
    }

    func test_mask_device_cut_window_surfaces_instability_reason() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/people_talking/two_scene_four_speakers.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        // Read a mid-clip window likely to span the scene cut.
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let dur = duration.seconds.isFinite ? duration.seconds : 0.0
        let start = max(0.0, min(dur, dur * 0.45))
        let window = max(0.5, min(7.0, dur - start))
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 120, startSeconds: start, maxSeconds: window)

        let device = MaskDevice()
        try await device.warmUp(kind: .foreground)

        var sawUnstable = false
        var sawAnyMask = false

        // Subsample to keep the test fast.
        for (i, pb) in frames.enumerated() {
            if i % 5 != 0 { continue }
            let res = try await device.generateMaskResult(in: pb, kind: .foreground)
            sawAnyMask = true
            if res.evidenceConfidence.reasons.contains(.mask_unstable_iou) {
                sawUnstable = true
                XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 0.85)
                break
            }
        }

        XCTAssertTrue(sawAnyMask)
        XCTAssertTrue(sawUnstable, "Expected cut window to surface mask instability via mask_unstable_iou")
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
