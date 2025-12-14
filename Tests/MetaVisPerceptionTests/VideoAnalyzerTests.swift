import XCTest
import CoreVideo
@testable import MetaVisPerception

final class VideoAnalyzerTests: XCTestCase {

    func testSolidRedStatsAreDeterministic() throws {
        let pb = try makeSolidBGRA(width: 64, height: 64, b: 0, g: 0, r: 255, a: 255)

        let analyzer = VideoAnalyzer(options: .init(maxDimension: 256))
        let analysis = try analyzer.analyze(pixelBuffer: pb)

        XCTAssertEqual(analysis.lumaHistogram.count, 256)

        // Histogram should sum to ~1.0
        let sum = analysis.lumaHistogram.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 1e-5)

        // Average color should be ~red.
        guard let avg = analysis.dominantColors.first else {
            return XCTFail("Expected at least one dominant color")
        }
        XCTAssertEqual(avg.x, 1.0, accuracy: 0.01)
        XCTAssertEqual(avg.y, 0.0, accuracy: 0.01)
        XCTAssertEqual(avg.z, 0.0, accuracy: 0.01)

        // Rec.709 luma for red ~0.2126, so bin near 54.
        let expectedBin = Int((0.2126 * 255.0).rounded(.toNearestOrAwayFromZero))
        let maxBin = analysis.lumaHistogram.enumerated().max(by: { $0.element < $1.element })?.offset
        XCTAssertNotNil(maxBin)
        XCTAssertTrue(abs((maxBin ?? -999) - expectedBin) <= 1)
    }

    func testAnalyzeIsDeterministicForSameInput() throws {
        let pb1 = try makePatternBGRA(width: 111, height: 73)
        let pb2 = try makePatternBGRA(width: 111, height: 73)

        let analyzer = VideoAnalyzer(options: .init(maxDimension: 256))

        let a1 = try analyzer.analyze(pixelBuffer: pb1)
        let a2 = try analyzer.analyze(pixelBuffer: pb1)
        let a3 = try analyzer.analyze(pixelBuffer: pb2)

        assertEqual(a1, a2)
        assertEqual(a1, a3)
    }
}

private func assertEqual(_ lhs: VideoAnalysis, _ rhs: VideoAnalysis, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.lumaHistogram.count, rhs.lumaHistogram.count, file: file, line: line)
    for i in 0..<min(lhs.lumaHistogram.count, rhs.lumaHistogram.count) {
        XCTAssertEqual(lhs.lumaHistogram[i], rhs.lumaHistogram[i], file: file, line: line)
    }

    XCTAssertEqual(lhs.dominantColors.count, rhs.dominantColors.count, file: file, line: line)
    for i in 0..<min(lhs.dominantColors.count, rhs.dominantColors.count) {
        XCTAssertEqual(lhs.dominantColors[i], rhs.dominantColors[i], file: file, line: line)
    }

    XCTAssertEqual(lhs.skinToneLikelihood, rhs.skinToneLikelihood, file: file, line: line)
    XCTAssertEqual(lhs.faces.count, rhs.faces.count, file: file, line: line)
}

private func makeSolidBGRA(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8, a: UInt8) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]

    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pb = pixelBuffer else {
        throw NSError(domain: "VideoAnalyzerTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed"])
    }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }

    guard let base = CVPixelBufferGetBaseAddress(pb) else {
        throw NSError(domain: "VideoAnalyzerTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "No base address"])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
    for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
            let i = x * 4
            row[i + 0] = b
            row[i + 1] = g
            row[i + 2] = r
            row[i + 3] = a
        }
    }

    return pb
}

private func makePatternBGRA(width: Int, height: Int) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]

    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pb = pixelBuffer else {
        throw NSError(domain: "VideoAnalyzerTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CVPixelBufferCreate failed"])
    }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }

    guard let base = CVPixelBufferGetBaseAddress(pb) else {
        throw NSError(domain: "VideoAnalyzerTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "No base address"])
    }

    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
    for y in 0..<height {
        let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
            let i = x * 4

            // Deterministic synthetic pattern with a mix of neutral and warm tones.
            let r = UInt8((x &* 17 &+ y &* 31) & 0xFF)
            let g = UInt8((x &* 23 &+ y &* 13 &+ 7) & 0xFF)
            let b = UInt8((x &* 11 &+ y &* 19 &+ 3) & 0xFF)

            row[i + 0] = b
            row[i + 1] = g
            row[i + 2] = r
            row[i + 3] = 255
        }
    }

    return pb
}
