import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisAudio

final class DialogCleanwaterTests: XCTestCase {

    func testDialogCleanwaterIncreasesPeakDeterministically() throws {
        let duration = Time(seconds: 1.0)

        func makeTimeline(withCleanwater: Bool) -> Timeline {
            let effect = withCleanwater ? [FeatureApplication(id: "audio.dialogCleanwater.v1")] : []
            let clip = Clip(
                name: "Tone",
                asset: AssetReference(sourceFn: "ligm://audio/sine?freq=1000"),
                startTime: .zero,
                duration: duration,
                effects: effect
            )
            let track = Track(name: "Dialog", kind: .audio, clips: [clip])
            return Timeline(tracks: [track], duration: duration)
        }

        func peak(of buffer: AVAudioPCMBuffer) -> Float {
            guard let data = buffer.floatChannelData else { return 0 }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            var p: Float = 0
            for ch in 0..<channels {
                let ptr = data[ch]
                for i in 0..<frames {
                    let a = abs(ptr[i])
                    if a > p { p = a }
                }
            }
            return p
        }

        let rendererA = AudioTimelineRenderer()
        let bufNo = try rendererA.render(timeline: makeTimeline(withCleanwater: false), timeRange: .zero..<duration)
        XCTAssertNotNil(bufNo)
        let peakNo = peak(of: try XCTUnwrap(bufNo))

        let rendererB = AudioTimelineRenderer()
        let bufYes = try rendererB.render(timeline: makeTimeline(withCleanwater: true), timeRange: .zero..<duration)
        XCTAssertNotNil(bufYes)
        let peakYes = peak(of: try XCTUnwrap(bufYes))

        // Preset sets +6dB global gain; expect a clear increase.
        XCTAssertGreaterThan(peakYes, peakNo * 1.6)
    }
}
