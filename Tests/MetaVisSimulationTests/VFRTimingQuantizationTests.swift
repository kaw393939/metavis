import XCTest
@testable import MetaVisSimulation

final class VFRTimingQuantizationTests: XCTestCase {

    func test_quantize_23976_uses1001Over24000FrameDuration() {
        // 23.976 fps -> 1001/24000 = 0.041708333...
        let t = 1.0 / 24.0 // 0.0416666...
        let q = ClipReader.quantize(timeSeconds: t, toTargetFPS: 23.976)
        XCTAssertEqual(q, 1001.0 / 24000.0, accuracy: 1e-9)
    }

    func test_quantize_2997_uses1001Over30000FrameDuration() {
        // 29.97 fps -> 1001/30000 = 0.033366666...
        let t = 1.0 / 30.0 // 0.0333333...
        let q = ClipReader.quantize(timeSeconds: t, toTargetFPS: 29.97)
        XCTAssertEqual(q, 1001.0 / 30000.0, accuracy: 1e-9)
    }

    func test_quantize_24_snapsTo1Over24Grid() {
        let t = 0.040
        let q = ClipReader.quantize(timeSeconds: t, toTargetFPS: 24.0)
        XCTAssertEqual(q, 1.0 / 24.0, accuracy: 1e-9)
    }
}
