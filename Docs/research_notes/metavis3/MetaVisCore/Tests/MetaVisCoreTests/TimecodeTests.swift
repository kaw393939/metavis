import XCTest
@testable import MetaVisCore

final class TimecodeTests: XCTestCase {
    
    func testTimecodeString() {
        // 30 FPS (non-drop)
        // Frame duration = 1/30
        let frameDuration = RationalTime(value: 1, timescale: 30)
        
        // 1.5 seconds = 1 second + 15 frames
        let time = RationalTime(value: 3, timescale: 2) // 1.5s
        
        let tc = Timecode.string(from: time, at: frameDuration)
        // Expected: 00:00:01:15
        // Wait, my implementation of `string(from:at:)` assumed the second arg was Frame Rate (FPS), 
        // but I passed Frame Duration.
        // Let's check the implementation logic again.
        // "If frameRate is actually frameDuration (e.g. 1001/30000), we invert it."
        // My implementation:
        // let fpsNumerator = Int64(frameRate.timescale)
        // let fpsDenominator = Int64(frameRate.value)
        // So if I pass 1/30, it calculates FPS as 30/1 = 30. Correct.
        
        XCTAssertEqual(tc, "00:00:01:15")
    }
    
    func testFrameIndex() {
        let frameDuration = RationalTime(value: 1, timescale: 30)
        let time = RationalTime(value: 1, timescale: 1) // 1 second
        
        let index = Timecode.frameIndex(from: time, step: frameDuration)
        XCTAssertEqual(index, 30)
    }
}
