import XCTest
import CoreVideo
import MetaVisCore
@testable import MetaVisPerception

final class DepthDeviceTests: XCTestCase {

    func test_depth_missing_is_explicit_and_governed() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 1.0)
        let rgb = frames[0]

        let device = DepthDevice()
        try await device.warmUp()

        let res = try await device.depthResult(in: rgb, depthSample: nil, confidenceSample: nil)

        XCTAssertNil(res.depth)
        XCTAssertEqual(res.metrics.validPixelRatio, 0.0)
        XCTAssertTrue(res.evidenceConfidence.reasons.contains(.depth_missing))
        XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())
        XCTAssertEqual(res.evidenceConfidence.grade, .INVALID)
    }

    func test_depth_metrics_are_reasonable_for_synthetic_depth() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 1.0)
        let rgb = frames[0]

        let depth = try makeDepthFloat32(width: CVPixelBufferGetWidth(rgb), height: CVPixelBufferGetHeight(rgb), valueMeters: 2.0)

        let device = DepthDevice()
        try await device.warmUp()

        let res = try await device.depthResult(in: rgb, depthSample: depth, confidenceSample: nil)

        XCTAssertNotNil(res.depth)
        XCTAssertGreaterThan(res.metrics.validPixelRatio, 0.99)
        XCTAssertEqual(res.evidenceConfidence.reasons, [])
        XCTAssertGreaterThan(res.evidenceConfidence.score, 0.50)

        if let minD = res.metrics.minDepthMeters, let maxD = res.metrics.maxDepthMeters {
            XCTAssertGreaterThan(minD, 1.5)
            XCTAssertLessThan(minD, 2.5)
            XCTAssertGreaterThan(maxD, 1.5)
            XCTAssertLessThan(maxD, 2.5)
        } else {
            XCTFail("Expected min/max depth metrics")
        }
    }

    private func makeDepthFloat32(width: Int, height: Int, valueMeters: Float) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_DepthFloat32),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DepthFloat32, attrs as CFDictionary, &out)
        guard status == kCVReturnSuccess, let pb = out else {
            throw NSError(domain: "DepthDeviceTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create DepthFloat32 CVPixelBuffer"]) 
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return pb }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        for y in 0..<h {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float.self)
            for x in 0..<w {
                row[x] = valueMeters
            }
        }

        return pb
    }
}
