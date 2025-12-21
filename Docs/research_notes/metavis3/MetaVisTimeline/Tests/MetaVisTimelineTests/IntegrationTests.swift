import XCTest
@testable import MetaVisTimeline
import MetaVisCore
import simd

final class IntegrationTests: XCTestCase {
    
    /// Tests that RationalTime maintains precision during interpolation calculations
    /// where Double conversion might fail or drift.
    func testHighPrecisionTiming() throws {
        // Scenario: A keyframe track placed very far in time (e.g., continuous recording timestamp).
        // 1,000,000 hours = 3,600,000,000 seconds.
        // Timescale 60,000.
        // Value = 216,000,000,000,000 (2.16e14).
        // This fits in Int64 (max 9e18) and Double (precision up to 9e15 integers).
        // Let's go bigger to force the issue, or just test that it works correctly at this scale.
        
        // Let's use a base time that is large but realistic for long-running systems.
        let largeBaseSeconds: Double = 1_000_000_000 // 1 billion seconds (~31 years)
        let timescale: Int32 = 60000
        
        let tStart = RationalTime(seconds: largeBaseSeconds, preferredTimescale: timescale)
        let tEnd = tStart + RationalTime(value: 60000, timescale: 60000) // 1 second later
        
        let k1 = Keyframe(time: tStart, value: 0.0)
        let k2 = Keyframe(time: tEnd, value: 1.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2], interpolation: .linear)
        
        // Evaluate exactly in the middle
        let tMid = tStart + RationalTime(value: 30000, timescale: 60000) // +0.5s
        
        // If we lose precision, this might not be exactly 0.5
        let val = try track.evaluate(at: tMid) as Double
        XCTAssertEqual(val, 0.5, accuracy: 0.000001)
        
        // Evaluate at a very small offset
        // 1 tick = 1/60000 sec.
        let tTick = tStart + RationalTime(value: 1, timescale: 60000)
        let valTick = try track.evaluate(at: tTick) as Double
        
        // Expected: 1/60000 = 0.000016666...
        let expected = 1.0 / 60000.0
        XCTAssertEqual(valTick, expected, accuracy: 0.000000001)
    }
    
    /// Tests that NodeValue wrapping works correctly for all supported types via TrackProtocol.
    func testNodeValueIntegration() throws {
        let t0 = RationalTime.zero
        let t1 = RationalTime(value: 1, timescale: 1)
        
        // 1. Float/Double Track
        let floatTrack = KeyframeTrack(keyframes: [
            Keyframe(time: t0, value: 0.0),
            Keyframe(time: t1, value: 10.0)
        ])
        
        // 2. Vector3 Track
        let vecTrack = KeyframeTrack(keyframes: [
            Keyframe(time: t0, value: SIMD3<Float>(0,0,0)),
            Keyframe(time: t1, value: SIMD3<Float>(1,1,1))
        ])
        
        // 3. Bool Track (Step)
        let boolTrack = KeyframeTrack(keyframes: [
            Keyframe(time: t0, value: false),
            Keyframe(time: t1, value: true)
        ], interpolation: .step)
        
        let tracks: [any TrackProtocol] = [floatTrack, vecTrack, boolTrack]
        
        let tMid = RationalTime(value: 1, timescale: 2) // 0.5s
        
        // Evaluate Float
        if case .float(let v) = try tracks[0].evaluate(at: tMid) {
            XCTAssertEqual(v, 5.0, accuracy: 0.001)
        } else { XCTFail("Wrong type for float track") }
        
        // Evaluate Vector
        if case .vector3(let v) = try tracks[1].evaluate(at: tMid) {
            XCTAssertEqual(v.x, 0.5, accuracy: 0.001)
        } else { XCTFail("Wrong type for vector track") }
        
        // Evaluate Bool
        if case .bool(let v) = try tracks[2].evaluate(at: tMid) {
            XCTAssertEqual(v, false) // Step interpolation holds first value
        } else { XCTFail("Wrong type for bool track") }
    }
    
    /// Tests that RationalTime arithmetic works correctly within the extrapolation logic.
    func testExtrapolationTimeMath() throws {
        // Setup a track 10s to 20s
        let tStart = RationalTime(value: 10, timescale: 1)
        let tEnd = RationalTime(value: 20, timescale: 1)
        
        let k1 = Keyframe(time: tStart, value: 10.0)
        let k2 = Keyframe(time: tEnd, value: 20.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2], preExtrapolation: .loop, postExtrapolation: .loop)
        
        // Evaluate at 25s (5s into loop) -> should be 15.0
        let tPost = RationalTime(value: 25, timescale: 1)
        XCTAssertEqual(try track.evaluate(at: tPost) as Double, 15.0, accuracy: 0.001)
        
        // Evaluate at 5s (5s before start, which is 5s from end of previous loop) -> should be 15.0
        // Loop: 10-20.
        // 0-10 is a loop. 5 is mid of 0-10.
        // 0 maps to 10. 10 maps to 20.
        // 5 maps to 15.
        let tPre = RationalTime(value: 5, timescale: 1)
        XCTAssertEqual(try track.evaluate(at: tPre) as Double, 15.0, accuracy: 0.001)
    }
}
