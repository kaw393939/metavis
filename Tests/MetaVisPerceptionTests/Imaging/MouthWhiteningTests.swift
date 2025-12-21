import XCTest
import CoreVideo
import MetaVisCore
@testable import MetaVisPerception

final class MouthWhiteningTests: XCTestCase {

    func test_whitening_is_local_to_mouth_roi() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 30, maxSeconds: 1.0)
        XCTAssertFalse(frames.isEmpty)

        let faceParts = FacePartsDevice()
        try await faceParts.warmUp()

        var chosenFrame: CVPixelBuffer?
        var mouthRectTL: CGRect?

        for pb in frames {
            let res = try await faceParts.facePartsResult(in: pb)
            if let rect = res.mouthRectTopLeft {
                chosenFrame = pb
                mouthRectTL = rect
                break
            }
        }

        guard let frame = chosenFrame, let mouthRect = mouthRectTL else {
            XCTFail("Expected to find mouth ROI on keith_talk.mov")
            return
        }

        XCTAssertEqual(CVPixelBufferGetPixelFormatType(frame), kCVPixelFormatType_32BGRA)

        let beforeInside = meanLuma(in: frame, normalizedTopLeftRect: mouthRect, include: true)
        let beforeOutside = meanLuma(in: frame, normalizedTopLeftRect: mouthRect, include: false)

        let out = try MouthWhitening.apply(in: frame, mouthRectTopLeft: mouthRect, strength: 0.85)

        let afterInside = meanLuma(in: out, normalizedTopLeftRect: mouthRect, include: true)
        let afterOutside = meanLuma(in: out, normalizedTopLeftRect: mouthRect, include: false)

        // Inside ROI should brighten measurably.
        XCTAssertGreaterThan(afterInside, beforeInside + 0.005)

        // Outside ROI should remain essentially unchanged (very small numerical drift allowed).
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

        // PixelBuffer memory is top-left origin.
        let rx0 = max(0, min(w, x0))
        let rx1 = max(0, min(w, x1))
        let ry0 = max(0, min(h, y0TL))
        let ry1 = max(0, min(h, y1TL))

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0.0 }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        // Deterministic subsampling for speed.
        let step = 4

        var sum: Double = 0.0
        var count: Int = 0

        for y in stride(from: 0, to: h, by: step) {
            let inROI = (y >= ry0 && y < ry1)
            if include != inROI {
                // If include==true, skip non-ROI rows; if include==false, skip ROI rows.
                continue
            }

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
