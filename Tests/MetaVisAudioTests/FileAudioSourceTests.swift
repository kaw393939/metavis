import XCTest
import AVFoundation
import MetaVisAudio
import MetaVisCore
import MetaVisTimeline

final class FileAudioSourceTests: XCTestCase {

    func testFileBackedAudioRendersNonSilent() async throws {
        FileAudioStreamingDiagnostics.isEnabled = true
        FileAudioStreamingDiagnostics.reset()

        // Use a known repo asset that contains an audio track.
        let path = "Tests/Assets/VideoEdit/keith_talk.mov"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Missing test asset at \(path)")
        }

        let duration = Time(seconds: 1.0)

        let audioClip = Clip(
            name: "Kept Audio",
            asset: AssetReference(sourceFn: path),
            startTime: .zero,
            duration: duration
        )

        let audioTrack = Track(name: "A1", kind: .audio, clips: [audioClip])
        let timeline = Timeline(tracks: [audioTrack], duration: duration)

        let renderer = AudioTimelineRenderer()
        let buffer: AVAudioPCMBuffer? = try await renderer.render(timeline: timeline, timeRange: .zero..<duration)
        let b: AVAudioPCMBuffer = try XCTUnwrap(buffer)
        XCTAssertGreaterThan(b.frameLength, 0)

        // Structural contract: decoding should be bounded to the requested render duration,
        // not the full asset duration.
        //
        // This test deliberately renders only 1s; the old implementation would decode the
        // entire asset audio track up-front.
        XCTAssertGreaterThan(FileAudioStreamingDiagnostics.lastConfiguredDurationFrames, 0)
        XCTAssertGreaterThan(FileAudioStreamingDiagnostics.lastDecodedFrames, 0)
        XCTAssertLessThan(
            FileAudioStreamingDiagnostics.lastDecodedFrames,
            10 * 48_000,
            "Expected streaming decoder to avoid full-track eager decode"
        )

        // Assert "not silent" in a coarse way.
        guard let data = b.floatChannelData else {
            XCTFail("Missing floatChannelData")
            return
        }

        let channels = Int(b.format.channelCount)
        let frames = Int(b.frameLength)
        var peak: Float = 0
        for ch in 0..<channels {
            let ptr = data[ch]
            for i in 0..<frames {
                let a = abs(ptr[i])
                if a > peak { peak = a }
            }
        }

        XCTAssertGreaterThan(peak, 0.0001, "Expected decoded file audio to be non-silent")
    }
}
