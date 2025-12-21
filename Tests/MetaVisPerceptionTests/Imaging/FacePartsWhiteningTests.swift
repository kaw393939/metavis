import XCTest
import CoreVideo
@testable import MetaVisPerception

final class FacePartsWhiteningTests: XCTestCase {

    func test_pipeline_whitens_inside_mouth_roi_only() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 30, maxSeconds: 1.0)
        XCTAssertFalse(frames.isEmpty)

        // Run pipeline until we get a frame with a mouth rect.
        let device = FacePartsDevice()
        try await device.warmUp()

        var chosen: CVPixelBuffer?
        var rect: CGRect?
        for pb in frames {
            let parts = try await device.facePartsResult(in: pb)
            if let r = parts.mouthRectTopLeft {
                chosen = pb
                rect = r
                break
            }
        }

        guard let frame = chosen, let mouthRect = rect else {
            XCTFail("Expected to find mouth ROI on keith_talk.mov")
            return
        }

        let beforeInside = meanLuma(in: frame, normalizedTopLeftRect: mouthRect, include: true)
        let beforeOutside = meanLuma(in: frame, normalizedTopLeftRect: mouthRect, include: false)

        let res = await FacePartsWhitening.apply(frame: frame, strength: 0.85, facePartsDevice: device)
        XCTAssertTrue(res.didApply)
        XCTAssertNotNil(res.mouthRectTopLeft)
        XCTAssertEqual(res.evidenceConfidence.reasons, res.evidenceConfidence.reasons.sorted())

        let afterInside = meanLuma(in: res.outputFrame, normalizedTopLeftRect: mouthRect, include: true)
        let afterOutside = meanLuma(in: res.outputFrame, normalizedTopLeftRect: mouthRect, include: false)

        XCTAssertGreaterThan(afterInside, beforeInside + 0.005)
        XCTAssertLessThan(abs(afterOutside - beforeOutside), 0.001)
    }

    private func meanLuma(in pb: CVPixelBuffer, normalizedTopLeftRect: CGRect, include: Bool) -> Double {
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(pb), kCVPixelFormatType_32BGRA)

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)

        let r = normalizedTopLeftRect
            .standardized
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        let x0 = Int(floor(CGFloat(w) * r.minX))
        let x1 = Int(ceil(CGFloat(w) * r.maxX))
        let y0TL = Int(floor(CGFloat(h) * r.minY))
        let y1TL = Int(ceil(CGFloat(h) * r.maxY))

        let rx0 = max(0, min(w, x0))
        let rx1 = max(0, min(w, x1))
        let ry0 = max(0, min(h, y0TL))
        let ry1 = max(0, min(h, y1TL))

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0.0 }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        let step = 4

        var sum: Double = 0.0
        var count: Int = 0

        for y in stride(from: 0, to: h, by: step) {
            let inROI = (y >= ry0 && y < ry1)
            if include != inROI { continue }

            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: w, by: step) {
                if include {
                    if x < rx0 || x >= rx1 { continue }
                } else {
                    if x >= rx0 && x < rx1 { continue }
                }

                let i = x * 4
                let b = Double(row[i + 0])
                let g = Double(row[i + 1])
                let rC = Double(row[i + 2])

                let yv = (0.114 * b + 0.587 * g + 0.299 * rC) / 255.0
                sum += yv
                count += 1
            }
        }

        if count == 0 { return 0.0 }
        return sum / Double(count)
    }
}
