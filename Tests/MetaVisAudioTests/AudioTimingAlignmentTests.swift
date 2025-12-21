import XCTest
@testable import MetaVisAudio
import MetaVisCore
import MetaVisTimeline
import AVFoundation

final class AudioTimingAlignmentTests: XCTestCase {

    func testOffsetClipProducesSilenceBeforeStart() async throws {
        // Clip starts at 0.5s, lasts 0.5s.
        let clip = Clip(
            name: "Offset Sine",
            asset: AssetReference(sourceFn: "ligm://sine?freq=440"),
            startTime: Time(seconds: 0.5),
            duration: Time(seconds: 0.5)
        )

        let track = Track(name: "Audio", kind: .audio, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let renderer = AudioTimelineRenderer()
        guard let buffer = try await renderer.render(timeline: timeline, timeRange: Time.zero..<Time(seconds: 1.0), sampleRate: 48_000) else {
            XCTFail("Expected audio buffer")
            return
        }

        guard let channels = buffer.floatChannelData else {
            XCTFail("Expected float channel data")
            return
        }

        let sr = Int(buffer.format.sampleRate)
        let preStartRange = 0..<(Int(0.45 * Double(sr))) // safely before 0.5s
        let postStartRange = (Int(0.60 * Double(sr)))..<(Int(0.70 * Double(sr))) // safely after 0.5s

        func maxAbs(in range: Range<Int>) -> Float {
            var m: Float = 0
            let ptr = channels[0]
            for i in range {
                let v = abs(ptr[i])
                if v > m { m = v }
            }
            return m
        }

        let preMax = maxAbs(in: preStartRange)
        let postMax = maxAbs(in: postStartRange)

        XCTAssertLessThan(preMax, 1e-4, "Expected silence before clip start (max=\(preMax))")
        XCTAssertGreaterThan(postMax, 1e-3, "Expected signal after clip start (max=\(postMax))")
    }
}
