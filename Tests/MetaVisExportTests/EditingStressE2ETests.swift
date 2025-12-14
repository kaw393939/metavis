import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisQC
import MetaVisSimulation

final class EditingStressE2ETests: XCTestCase {

    private func makeEngineAndExporter() async throws -> VideoExporter {
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        return VideoExporter(engine: engine)
    }

    private func master4K() -> QualityProfile {
        QualityProfile(name: "Master 4K", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)
    }

    func test_videoOnlyEditing_exportHasNoAudioTrack() async throws {
        let exporter = try await makeEngineAndExporter()

        let duration = Time(seconds: 1.5)
        let video = Track(
            name: "V",
            kind: .video,
            clips: [
                Clip(
                    name: "SMPTE",
                    asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
                    startTime: .zero,
                    duration: duration
                )
            ]
        )

        let timeline = Timeline(tracks: [video], duration: duration)
        let outputURL = TestOutputs.url(for: "e2e_video_only_no_audio", quality: "4K_10bit")

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: master4K(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .auto,
            governance: .none
        )

        let hasAudio = try await AudioMovieProbe.hasAudioTrack(at: outputURL)
        XCTAssertFalse(hasAudio)

        _ = try await VideoQC.validateMovie(at: outputURL, expectations: .hevc4K24fps(durationSeconds: duration.seconds))
    }

    func test_audioOnlyEditing_movesToneEarlier() async throws {
        let exporter = try await makeEngineAndExporter()
        let duration = Time(seconds: 2.0)

        let video = Track(
            name: "V",
            kind: .video,
            clips: [
                Clip(
                    name: "SMPTE",
                    asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
                    startTime: .zero,
                    duration: duration
                )
            ]
        )

        func makeAudioTrack(start: Time) -> Track {
            Track(
                name: "A",
                kind: .audio,
                clips: [
                    Clip(
                        name: "440Hz",
                        asset: AssetReference(sourceFn: "ligm://audio/sine?freq=440"),
                        startTime: start,
                        duration: Time(seconds: 0.8)
                    )
                ]
            )
        }

        // Export 1: tone starts later
        do {
            let timeline = Timeline(tracks: [video, makeAudioTrack(start: Time(seconds: 1.0))], duration: duration)
            let outputURL = TestOutputs.url(for: "e2e_audio_only_edit_before", quality: "4K_10bit")

            try await exporter.export(
                timeline: timeline,
                to: outputURL,
                quality: master4K(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .required,
                governance: .none
            )

            let peakEarly = try await AudioMovieProbe.peak(at: outputURL, startSeconds: 0.0, durationSeconds: 0.4)
            let peakLate = try await AudioMovieProbe.peak(at: outputURL, startSeconds: 1.0, durationSeconds: 0.4)

            XCTAssertLessThan(peakEarly, 0.001)
            XCTAssertGreaterThan(peakLate, 0.01)
        }

        // Export 2: audio-only edit moves tone earlier
        do {
            let timeline = Timeline(tracks: [video, makeAudioTrack(start: .zero)], duration: duration)
            let outputURL = TestOutputs.url(for: "e2e_audio_only_edit_after", quality: "4K_10bit")

            try await exporter.export(
                timeline: timeline,
                to: outputURL,
                quality: master4K(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .required,
                governance: .none
            )

            let peakEarly = try await AudioMovieProbe.peak(at: outputURL, startSeconds: 0.0, durationSeconds: 0.4)
            XCTAssertGreaterThan(peakEarly, 0.01)
        }
    }

    func test_avEditing_offsetShiftsImpulseEnergy() async throws {
        let exporter = try await makeEngineAndExporter()

        let duration = Time(seconds: 1.5)
        let video = Track(
            name: "V",
            kind: .video,
            clips: [
                Clip(
                    name: "SMPTE",
                    asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
                    startTime: .zero,
                    duration: duration
                )
            ]
        )

        let impulse = Clip(
            name: "Impulse",
            asset: AssetReference(sourceFn: "ligm://audio/impulse?interval=0.5"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            offset: Time(seconds: 0.25)
        )

        let audio = Track(name: "A", kind: .audio, clips: [impulse])
        let timeline = Timeline(tracks: [video, audio], duration: duration)
        let outputURL = TestOutputs.url(for: "e2e_av_offset_impulse", quality: "4K_10bit")

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: master4K(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required,
            governance: .none
        )

        let peakVeryEarly = try await AudioMovieProbe.peak(at: outputURL, startSeconds: 0.0, durationSeconds: 0.1)
        let peakAroundOffset = try await AudioMovieProbe.peak(at: outputURL, startSeconds: 0.22, durationSeconds: 0.15)

        XCTAssertLessThan(peakVeryEarly, 0.01)
        XCTAssertGreaterThan(peakAroundOffset, 0.1)
    }

    func test_stress_manyOverlappingAudioClips_exportsAndIsFinite() async throws {
        let exporter = try await makeEngineAndExporter()

        let duration = Time(seconds: 2.0)
        let video = Track(
            name: "V",
            kind: .video,
            clips: [
                Clip(
                    name: "SMPTE",
                    asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
                    startTime: .zero,
                    duration: duration
                )
            ]
        )

        func audioSource(for i: Int) -> String {
            switch i % 5 {
            case 0: return "ligm://audio/sine?freq=220"
            case 1: return "ligm://audio/sine?freq=440"
            case 2: return "ligm://audio/white_noise"
            case 3: return "ligm://audio/pink_noise"
            default: return "ligm://audio/sweep?start=100&end=8000"
            }
        }

        var tracks: [Track] = [video]
        for t in 0..<6 {
            var clips: [Clip] = []
            for i in 0..<24 {
                let start = Double((t * 7 + i * 3) % 160) / 100.0 // 0.00 .. 1.59
                let clipDuration = 0.25
                let fade = Time(seconds: 0.02)
                clips.append(
                    Clip(
                        name: "A_\(t)_\(i)",
                        asset: AssetReference(sourceFn: audioSource(for: t * 100 + i)),
                        startTime: Time(seconds: start),
                        duration: Time(seconds: clipDuration),
                        offset: Time(seconds: Double((i % 5)) * 0.01),
                        transitionIn: .crossfade(duration: fade, easing: .easeIn),
                        transitionOut: .crossfade(duration: fade, easing: .easeOut)
                    )
                )
            }
            tracks.append(Track(name: "A\(t)", kind: .audio, clips: clips))
        }

        let timeline = Timeline(tracks: tracks, duration: duration)
        let outputURL = TestOutputs.url(for: "e2e_stress_audio_overlap", quality: "4K_10bit")

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: master4K(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .required,
            governance: .none
        )

        let peak = try await AudioMovieProbe.peak(at: outputURL, startSeconds: 0.0, durationSeconds: 0.5)
        let rms = try await AudioMovieProbe.rms(at: outputURL, startSeconds: 0.0, durationSeconds: 0.5)

        XCTAssertTrue(peak.isFinite)
        XCTAssertTrue(rms.isFinite)
        XCTAssertGreaterThan(peak, 0.0005)

        try await VideoQC.assertAudioNotSilent(at: outputURL)
    }

    func test_stress_manyVideoLayers_exports() async throws {
        let exporter = try await makeEngineAndExporter()

        let duration = Time(seconds: 2.0)
        let fade = Time(seconds: 0.15)

        let sources = [
            "ligm://video/smpte_bars",
            "ligm://video/macbeth",
            "ligm://video/zone_plate?speed=1.0",
            "ligm://video/frame_counter"
        ]

        var tracks: [Track] = []
        for t in 0..<6 {
            var clips: [Clip] = []
            for i in 0..<3 {
                let start = Double(i) * 0.5
                let src = sources[(t + i) % sources.count]
                clips.append(
                    Clip(
                        name: "V_\(t)_\(i)",
                        asset: AssetReference(sourceFn: src),
                        startTime: Time(seconds: start),
                        duration: Time(seconds: 1.2),
                        transitionIn: .crossfade(duration: fade, easing: .easeInOut),
                        transitionOut: .crossfade(duration: fade, easing: .easeInOut)
                    )
                )
            }
            tracks.append(Track(name: "V\(t)", kind: .video, clips: clips))
        }

        let timeline = Timeline(tracks: tracks, duration: duration)
        let outputURL = TestOutputs.url(for: "e2e_stress_video_layers", quality: "4K_10bit")

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: master4K(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        _ = try await VideoQC.validateMovie(at: outputURL, expectations: .hevc4K24fps(durationSeconds: duration.seconds))
        let hasAudio = try await AudioMovieProbe.hasAudioTrack(at: outputURL)
        XCTAssertFalse(hasAudio)
    }
}
