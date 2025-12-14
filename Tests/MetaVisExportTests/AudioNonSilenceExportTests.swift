import XCTest
import AVFoundation
import MetaVisCore
import MetaVisSession
import MetaVisExport
import MetaVisQC
import MetaVisSimulation

final class AudioNonSilenceExportTests: XCTestCase {

    func testExportWithAudioPassesNonSilenceQC() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let exporter = VideoExporter(engine: engine)

        var timeline = GodTestBuilder.build()
        timeline.duration = Time(seconds: 2.0) // keep test fast

        let outputURL = TestOutputs.url(for: "audio_non_silence", quality: "4K_10bit")
        let quality = QualityProfile(name: "Master 4K", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required,
            governance: .none
        )

        let expectedFrames = Int((timeline.duration.seconds * 24.0).rounded())
        let minSamples = max(1, Int(Double(expectedFrames) * 0.85))

        let policy = DeterministicQCPolicy(
            video: VideoContainerPolicy(
                minDurationSeconds: 1.5,
                maxDurationSeconds: 2.5,
                expectedWidth: 3840,
                expectedHeight: 2160,
                expectedNominalFrameRate: 24.0,
                minVideoSampleCount: minSamples
            ),
            requireAudioTrack: true,
            requireAudioNotSilent: true,
            audioSampleSeconds: 0.5,
            minAudioPeak: 0.0005
        )

        _ = try await VideoQC.validateMovie(at: outputURL, policy: policy)
    }
}
