import XCTest
@testable import MetaVisTimeline
import MetaVisCore
import simd

final class TrackProtocolTests: XCTestCase {
    
    func testHeterogeneousTracks() throws {
        // Create a Double track
        var doubleTrack = KeyframeTrack<Double>(
            keyframes: [],
            interpolation: .linear,
            preExtrapolation: .hold,
            postExtrapolation: .hold
        )
        doubleTrack.addKeyframe(Keyframe(time: RationalTime(value: 0, timescale: 24), value: 0.0))
        doubleTrack.addKeyframe(Keyframe(time: RationalTime(value: 24, timescale: 24), value: 10.0))
        
        // Create a Vector3 track
        var vecTrack = KeyframeTrack<SIMD3<Float>>(
            keyframes: [],
            interpolation: .linear,
            preExtrapolation: .hold,
            postExtrapolation: .hold
        )
        vecTrack.addKeyframe(Keyframe(time: RationalTime(value: 0, timescale: 24), value: SIMD3<Float>(0, 0, 0)))
        vecTrack.addKeyframe(Keyframe(time: RationalTime(value: 24, timescale: 24), value: SIMD3<Float>(1, 1, 1)))
        
        // Store in a heterogeneous array
        let tracks: [any TrackProtocol] = [doubleTrack, vecTrack]
        
        // Evaluate at t=12 (0.5s, halfway)
        let time = RationalTime(value: 12, timescale: 24)
        
        let val1 = try tracks[0].evaluate(at: time)
        let val2 = try tracks[1].evaluate(at: time)
        
        // Check Double track result
        if case .float(let d) = val1 {
            XCTAssertEqual(d, 5.0, accuracy: 0.001)
        } else {
            XCTFail("Expected float value for track 0")
        }
        
        // Check Vector3 track result
        if case .vector3(let v) = val2 {
            XCTAssertEqual(v.x, 0.5, accuracy: 0.001)
            XCTAssertEqual(v.y, 0.5, accuracy: 0.001)
            XCTAssertEqual(v.z, 0.5, accuracy: 0.001)
        } else {
            XCTFail("Expected vector3 value for track 1")
        }
    }
}
