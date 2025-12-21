import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class KeyframeTests: XCTestCase {
    
    func testLinearInterpolation() throws {
        let t0 = RationalTime(value: 0, timescale: 60)
        let t1 = RationalTime(value: 60, timescale: 60) // 1 second
        
        let k1 = Keyframe(time: t0, value: 0.0)
        let k2 = Keyframe(time: t1, value: 100.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2], interpolation: .linear)
        
        // Test start
        XCTAssertEqual(try track.evaluate(at: t0) as Double, 0.0)
        
        // Test end
        XCTAssertEqual(try track.evaluate(at: t1) as Double, 100.0)
        
        // Test mid (0.5s)
        let tMid = RationalTime(value: 30, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tMid) as Double, 50.0)
        
        // Test quarter (0.25s)
        let tQuarter = RationalTime(value: 15, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tQuarter) as Double, 25.0)
    }
    
    func testStepInterpolation() throws {
        let t0 = RationalTime(value: 0, timescale: 60)
        let t1 = RationalTime(value: 60, timescale: 60)
        
        let k1 = Keyframe(time: t0, value: 0.0)
        let k2 = Keyframe(time: t1, value: 100.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2], interpolation: .step)
        
        let tMid = RationalTime(value: 30, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tMid) as Double, 0.0) // Should hold k1 value
        
        let tAlmostEnd = RationalTime(value: 59, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tAlmostEnd) as Double, 0.0)
        
        XCTAssertEqual(try track.evaluate(at: t1) as Double, 100.0) // At exactly t1, it might switch depending on logic, usually k1 holds until k2
        // In our logic: if time >= k1.time && time < k2.time -> return k1.value
        // So at t1, loop finishes, returns k2.value (last keyframe)
    }
    
    func testExtrapolationHold() throws {
        let t0 = RationalTime(value: 10, timescale: 60)
        let t1 = RationalTime(value: 20, timescale: 60)
        
        let k1 = Keyframe(time: t0, value: 10.0)
        let k2 = Keyframe(time: t1, value: 20.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2], preExtrapolation: .hold, postExtrapolation: .hold)
        
        // Pre
        let tPre = RationalTime(value: 0, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tPre) as Double, 10.0)
        
        // Post
        let tPost = RationalTime(value: 30, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tPost) as Double, 20.0)
    }
    
    func testVectorInterpolation() throws {
        let t0 = RationalTime(value: 0, timescale: 60)
        let t1 = RationalTime(value: 60, timescale: 60)
        
        let v1 = SIMD3<Float>(0, 0, 0)
        let v2 = SIMD3<Float>(10, 20, 30)
        
        let k1 = Keyframe(time: t0, value: v1)
        let k2 = Keyframe(time: t1, value: v2)
        
        let track = KeyframeTrack(keyframes: [k1, k2])
        
        let tMid = RationalTime(value: 30, timescale: 60)
        let result: SIMD3<Float> = try track.evaluate(at: tMid)
        
        XCTAssertEqual(result.x, 5.0)
        XCTAssertEqual(result.y, 10.0)
        XCTAssertEqual(result.z, 15.0)
    }
    
    func testEasingApplication() throws {
        let t0 = RationalTime(value: 0, timescale: 60)
        let t1 = RationalTime(value: 60, timescale: 60)
        
        // EaseInQuad: t^2. At 0.5, value should be 0.25 * 100 = 25.
        let k1 = Keyframe(time: t0, value: 0.0, easing: .easeInQuad)
        let k2 = Keyframe(time: t1, value: 100.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2])
        
        let tMid = RationalTime(value: 30, timescale: 60)
        let result: Double = try track.evaluate(at: tMid)
        
        XCTAssertEqual(result, 25.0, accuracy: 0.001)
    }
    
    func testPingPongExtrapolation() throws {
        let t0 = RationalTime(value: 0, timescale: 60)
        let t1 = RationalTime(value: 10, timescale: 60)
        
        let k1 = Keyframe(time: t0, value: 0.0)
        let k2 = Keyframe(time: t1, value: 10.0)
        
        let track = KeyframeTrack(keyframes: [k1, k2], preExtrapolation: .pingPong, postExtrapolation: .pingPong)
        
        // Duration is 10 frames.
        // t = 15 (5 frames past end). Should be halfway back to 0 -> 5.0
        let tPost = RationalTime(value: 15, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tPost) as Double, 5.0, accuracy: 0.001)
        
        // t = 25 (15 frames past end).
        // 0-10: Forward (0->10)
        // 10-20: Backward (10->0)
        // 20-30: Forward (0->10)
        // 25 is mid of 20-30 -> 5.0
        let tPost2 = RationalTime(value: 25, timescale: 60)
        XCTAssertEqual(try track.evaluate(at: tPost2) as Double, 5.0, accuracy: 0.001)
    }
    
    func testEmptyTrackError() {
        let track = KeyframeTrack<Double>(keyframes: [])
        XCTAssertThrowsError(try track.evaluate(at: .zero) as Double) { error in
            XCTAssertEqual(error as? TimelineError, .emptyTrack)
        }
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
        let val = try? track.evaluate(at: RationalTime(value: 10, timescale: 1)) as Double
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
            let val = try track.evaluate(at: RationalTime(value: 15, timescale: 1)) as Double
            XCTAssertEqual(val, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
        
        // At 25s, it should map to 5s -> 5.0
        do {
            let val2 = try track.evaluate(at: RationalTime(value: 25, timescale: 1)) as Double
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
            let val = try track.evaluate(at: RationalTime(value: 15, timescale: 1)) as Double
            XCTAssertEqual(val, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
        
        // At 12s (2s into return trip) -> Should be 8.0
        // 10s -> 10. 12s -> 8. 20s -> 0.
        do {
            let val2 = try track.evaluate(at: RationalTime(value: 12, timescale: 1)) as Double
            XCTAssertEqual(val2, 8.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
    }
    
    func testBezierInterpolation() {
        // 0s -> 0.0
        // 10s -> 10.0
        // Bezier with tangents
        
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
            let val = try track.evaluate(at: RationalTime(value: 5, timescale: 1)) as Double
            XCTAssertEqual(val, 5.0)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
        
        // At 2.5s (t=0.25)
        // Linear would be 2.5.
        // Hermite (0, 0, 10, 0) at t=0.25:
        // val = 1.5625
        
        do {
            let val = try track.evaluate(at: RationalTime(value: 25, timescale: 10)) as Double // 2.5s
            XCTAssertTrue(val < 2.5, "Ease-in should be less than linear at 25%")
            XCTAssertEqual(val, 1.5625, accuracy: 0.0001)
        } catch {
            XCTFail("Evaluation threw error: \(error)")
        }
    }
}
