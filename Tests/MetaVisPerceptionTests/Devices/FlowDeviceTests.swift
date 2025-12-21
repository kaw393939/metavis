import XCTest
import CoreVideo
import CoreImage
import MetaVisCore
@testable import MetaVisPerception

final class FlowDeviceTests: XCTestCase {

    func test_flow_device_emits_dense_flow_and_evidence_confidence() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        // Pull enough frames to ensure motion between samples.
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 20, maxSeconds: 1.0)
        XCTAssertGreaterThanOrEqual(frames.count, 2)

        // Downscale to a small BGRA grid for speed and compatibility.
        let prev = try downscaleToBGRA(frames[0], width: 160, height: 90)
        let curr = try downscaleToBGRA(frames[min(10, frames.count - 1)], width: 160, height: 90)

        let device = FlowDevice()
        let res = try await device.flowResult(previous: prev, current: curr)

        XCTAssertEqual(CVPixelBufferGetPixelFormatType(res.flow), kCVPixelFormatType_TwoComponent16Half)
        XCTAssertGreaterThan(CVPixelBufferGetWidth(res.flow), 0)
        XCTAssertGreaterThan(CVPixelBufferGetHeight(res.flow), 0)

        XCTAssertTrue(res.metrics.meanMagnitude.isFinite)
        XCTAssertGreaterThanOrEqual(res.metrics.meanMagnitude, 0.0)

        // EvidenceConfidence should be governed and deterministic.
        XCTAssertGreaterThanOrEqual(res.evidenceConfidence.score, 0.0)
        XCTAssertLessThanOrEqual(res.evidenceConfidence.score, 1.0)
        XCTAssertFalse(res.evidenceConfidence.sources.isEmpty)
        XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())
    }

    private func downscaleToBGRA(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let outPB = out else {
            throw NSError(domain: "FlowDeviceTests", code: Int(status), userInfo: nil)
        }

        let ciContext = CIContext(options: nil)
        let img = CIImage(cvPixelBuffer: pixelBuffer)
        let scaled = img.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(img.extent.width), y: CGFloat(height) / CGFloat(img.extent.height)))
        ciContext.render(scaled, to: outPB)
        return outPB
    }
}
