import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class KeyframeDebtTests: XCTestCase {
    
    func assertDoubleEqual(_ v1: Double, _ v2: Double, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(v1, v2, accuracy: 0.0001, file: file, line: line)
    }
    
    func testDuplicateKeyframes() {
        // Scenario: User adds two keyframes at the exact same time.
        // Expected: The second one should replace the first.
        
        var track = KeyframeTrack<Double>(keyframes: [])
        
        let k1 = Keyframe(time: RationalTime(value: 10, timescale: 1), value: 1.0)
        let k2 = Keyframe(time: RationalTime(value: 10, timescale: 1), value: 2.0)
        
        track.addKeyframe(k1)
        track.addKeyframe(k2)
        
        // We expect the first one to be removed.
        XCTAssertEqual(track.keyframes.count, 1)
        
        // If we evaluate at 10, what do we get?
        // Should be 2.0
        let val: Double? = try? track.evaluate(at: RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(val, 2.0)
    }
    
    func testExtrapolationLoop() {
        // 0s -> 0.0
        // 10s -> 10.0
        // Loop
        
        let k1 = Keyframe<Double>(time: RationalTime(value: 0, timescale: 1), value: 0.0)
        let k2 = Keyframe<Double>(time: RationalTime(value: 10, timescale: 1), value: 10.0)
        
        let track = KeyframeTrack<Double>(
            keyframes: [k1, k2],
            interpolation: .linear,
            preExtrapolation: .loop,
            postExtrapolation: .loop
        )
        
        // At 15s, it should map to 5s -> 5.0
        do {
            // Explicitly type as Double to force the correct overload
            let val: Double = try track.evaluate(at: RationalTime(value: 15, timescale: 1))
            XCTAssertEqual(val, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
        
        // At 25s, it should map to 5s -> 5.0
        do {
            let val2: Double = try track.evaluate(at: RationalTime(value: 25, timescale: 1))
            XCTAssertEqual(val2, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
    }
    
    func testExtrapolationPingPong() {
        // 0s -> 0.0
        // 10s -> 10.0
        // PingPong
        
        let k1 = Keyframe<Double>(time: RationalTime(value: 0, timescale: 1), value: 0.0)
        let k2 = Keyframe<Double>(time: RationalTime(value: 10, timescale: 1), value: 10.0)
        
        let track = KeyframeTrack<Double>(
            keyframes: [k1, k2],
            interpolation: .linear,
            preExtrapolation: .pingPong,
            postExtrapolation: .pingPong
        )
        
        // 0-10: Forward (0->10)
        // 10-20: Backward (10->0)
        // 20-30: Forward (0->10)
        
        // At 15s (Middle of 10-20) -> Should be 5.0
        do {
            let val: Double = try track.evaluate(at: RationalTime(value: 15, timescale: 1))
            XCTAssertEqual(val, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
        
        // At 12s (2s into return trip) -> Should be 8.0
        // 10s -> 10. 12s -> 8. 20s -> 0.
        do {
            let val2: Double = try track.evaluate(at: RationalTime(value: 12, timescale: 1))
            assertDoubleEqual(val2, 8.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
    }
    
    func testBezierInterpolation() {
        // 0s -> 0.0
        // 10s -> 10.0
        // Bezier with tangents
        
        // Tangents are slopes.
        // If we want ease-in ease-out, we want slope 0 at start and end.
        // Hermite spline with m0=0, m1=0 is the standard S-curve (3t^2 - 2t^3).
        
        let k1 = Keyframe<Double>(
            time: RationalTime(value: 0, timescale: 1),
            value: 0.0,
            outTangent: 0.0
        )
        let k2 = Keyframe<Double>(
            time: RationalTime(value: 10, timescale: 1),
            value: 10.0,
            inTangent: 0.0
        )
        
        let track = KeyframeTrack<Double>(
            keyframes: [k1, k2],
            interpolation: .bezier
        )
        
        // At 5s (t=0.5), value should be 5.0 (symmetric)
        do {
            let val: Double = try track.evaluate(at: RationalTime(value: 5, timescale: 1))
            assertDoubleEqual(val, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
        
        // At 2.5s (t=0.25)
        // Linear would be 2.5.
        // Hermite (0, 0, 10, 0) at t=0.25:
        // h1 = 2(1/64) - 3(1/16) + 1 = 1/32 - 3/16 + 1 = 2/64 - 12/64 + 64/64 = 54/64 = 27/32 = 0.84375
        // h2 = ... (m0=0)
        // h3 = -2(1/64) + 3(1/16) = -1/32 + 3/16 = -2/64 + 12/64 = 10/64 = 5/32 = 0.15625
        // h4 = ... (m1=0)
        // val = 0.84375 * 0 + 0.15625 * 10 = 1.5625
        
        do {
            let val: Double = try track.evaluate(at: RationalTime(value: 25, timescale: 10)) // 2.5s
            // Linear would be 2.5
            XCTAssertTrue(val < 2.5, "Ease-in should be less than linear at 25%")
            assertDoubleEqual(val, 1.5625)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
    }
}
