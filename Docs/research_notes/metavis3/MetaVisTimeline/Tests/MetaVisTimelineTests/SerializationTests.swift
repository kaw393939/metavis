import XCTest
@testable import MetaVisTimeline
import MetaVisCore

final class SerializationTests: XCTestCase {
    
    func testKeyframeSerialization() throws {
        let time = RationalTime(value: 10, timescale: 24)
        let keyframe = Keyframe(time: time, value: 5.0, easing: .easeInQuad)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(keyframe)
        
        let decoder = JSONDecoder()
        let decodedKeyframe = try decoder.decode(Keyframe<Double>.self, from: data)
        
        XCTAssertEqual(decodedKeyframe.time, time)
        XCTAssertEqual(decodedKeyframe.value, 5.0)
        XCTAssertEqual(decodedKeyframe.easing, .easeInQuad)
    }
    
    func testKeyframeTrackSerialization() throws {
        let track = KeyframeTrack(
            keyframes: [
                Keyframe(time: RationalTime(value: 0, timescale: 24), value: 0.0),
                Keyframe(time: RationalTime(value: 24, timescale: 24), value: 10.0)
            ],
            interpolation: .linear,
            preExtrapolation: .hold,
            postExtrapolation: .loop
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(track)
        
        let decoder = JSONDecoder()
        let decodedTrack = try decoder.decode(KeyframeTrack<Double>.self, from: data)
        
        XCTAssertEqual(decodedTrack.keyframes.count, 2)
        XCTAssertEqual(decodedTrack.interpolation, .linear)
        XCTAssertEqual(decodedTrack.postExtrapolation, .loop)
        XCTAssertEqual(decodedTrack.keyframes[1].value, 10.0)
    }
}
