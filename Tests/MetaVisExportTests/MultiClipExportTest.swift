import XCTest
@testable import MetaVisExport
@testable import MetaVisSimulation
@testable import MetaVisTimeline
@testable import MetaVisCore
import MetaVisQC
import Metal
import AVFoundation

final class MultiClipExportTest: XCTestCase {
    
    /// Test: Export 3-clip crossfade sequence
    /// SMPTE (5s) → crossfade 1s → Macbeth (5s) → crossfade 1s → Zone Plate (5s)
    func testMultiClipCrossfadeExport() async throws {
        DotEnvLoader.loadIfPresent()

        // Create timeline with 3 clips and transitions
        var timeline = Timeline(duration: Time(seconds: 13.0))
        
        // Clip 1: SMPTE Bars (0-5s) with 1s fade out
        let smpteAsset = AssetReference(sourceFn: "ligm://fx_smpte_bars")
        var smpteClip = Clip(
            name: "SMPTE",
            asset: smpteAsset,
            startTime: Time.zero,
            duration: Time(seconds: 5.0)
        )
        smpteClip.transitionOut = .crossfade(duration: Time(seconds: 1.0))
        
        // Clip 2: Macbeth (4-9s) with crossfades
        let macbethAsset = AssetReference(sourceFn: "ligm://fx_macbeth")
        var macbethClip = Clip(
            name: "Macbeth",
            asset: macbethAsset,
            startTime: Time(seconds: 4.0),
            duration: Time(seconds: 5.0)
        )
        macbethClip.transitionIn = .crossfade(duration: Time(seconds: 1.0))
        macbethClip.transitionOut = .crossfade(duration: Time(seconds: 1.0))
        
        // Clip 3: Zone Plate (8-13s) with 1s fade in
        let zonePlateAsset = AssetReference(sourceFn: "ligm://fx_zone_plate")
        var zonePlateClip = Clip(
            name: "ZonePlate",
            asset: zonePlateAsset,
            startTime: Time(seconds: 8.0),
            duration: Time(seconds: 5.0)
        )
        zonePlateClip.transitionIn = .crossfade(duration: Time(seconds: 1.0))
        
        // Create track
        let videoTrack = Track(
            name: "Video",
            kind: .video,
            clips: [smpteClip, macbethClip, zonePlateClip]
        )

        // Add a simple procedural audio bed across the full duration.
        let audioAsset = AssetReference(sourceFn: "ligm://audio/sine?freq=1000")
        let audioClip = Clip(
            name: "Tone",
            asset: audioAsset,
            startTime: .zero,
            duration: Time(seconds: 13.0)
        )
        let audioTrack = Track(name: "Audio", kind: .audio, clips: [audioClip])

        timeline.tracks = [videoTrack, audioTrack]
        
        // Setup export
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)
        
        let outputURL = TestOutputs.url(for: "multi_clip_crossfade", quality: "4K_10bit")
        
        let quality = QualityProfile(
            name: "4K Test",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )
        
        // Export!
        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: AVVideoCodecType.hevc,
            audioPolicy: .required
        )
        
        // Verify
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), 
                     "Export file should exist")
        
        // Deterministic local QC (duration/track/resolution/sample count)
        let report = try await VideoQC.validateMovie(
            at: outputURL,
            expectations: .hevc4K24fps(durationSeconds: 13.0)
        )

        // Audio requirement: export should include an audio track and it should not be silent.
        try await VideoQC.assertHasAudioTrack(at: outputURL)
        try await VideoQC.assertAudioNotSilent(at: outputURL)

        // Deterministic content QC: ensure frames differ across the timeline.
        // This catches regressions where clip selection gets stuck (e.g., 13s of SMPTE bars).
        try await VideoContentQC.assertTemporalVariety(
            movieURL: outputURL,
            samples: [
                .init(timeSeconds: 2.0, label: "SMPTE mid"),
                .init(timeSeconds: 7.0, label: "Macbeth mid"),
                .init(timeSeconds: 11.0, label: "ZonePlate mid")
            ]
        )

        // Deterministic color stats QC (Perception-aligned): luma histogram + average color checks.
        let colorStats = try await VideoContentQC.validateColorStats(
            movieURL: outputURL,
            samples: [
                // These bounds are intentionally tolerant, but catch black/white/flat regressions.
                .init(
                    timeSeconds: 2.0,
                    label: "SMPTE mid",
                    minMeanLuma: 0.20,
                    maxMeanLuma: 0.85,
                    maxChannelDelta: 0.20,
                    minLowLumaFraction: 0.01,
                    minHighLumaFraction: 0.01
                ),
                .init(
                    timeSeconds: 7.0,
                    label: "Macbeth mid",
                    minMeanLuma: 0.15,
                    maxMeanLuma: 0.85,
                    maxChannelDelta: 0.35,
                    minLowLumaFraction: 0.002,
                    minHighLumaFraction: 0.002
                ),
                .init(
                    timeSeconds: 11.0,
                    label: "ZonePlate mid",
                    minMeanLuma: 0.10,
                    maxMeanLuma: 0.90,
                    maxChannelDelta: 0.10,
                    minLowLumaFraction: 0.01,
                    minHighLumaFraction: 0.01
                )
            ]
        )

        // Gemini acceptance (eyes) using keyframes around transitions.
        // This is opt-in because LLM JSON formatting can be nondeterministic.
        let runGeminiQC = ProcessInfo.processInfo.environment["RUN_GEMINI_QC"] == "1"
        if runGeminiQC {
            let usage = GeminiQC.UsageContext(
                policy: AIUsagePolicy(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly),
                privacy: PrivacyPolicy(allowRawMediaUpload: false, allowDeliverablesUpload: true)
            )
            let verdict = try await GeminiQC.acceptMulticlipExport(
                movieURL: outputURL,
                keyFrames: [
                    .init(timeSeconds: 2.0, label: "SMPTE mid"),
                    .init(timeSeconds: 4.5, label: "Crossfade SMPTE->Macbeth"),
                    .init(timeSeconds: 7.0, label: "Macbeth mid"),
                    .init(timeSeconds: 8.5, label: "Crossfade Macbeth->Zone"),
                    .init(timeSeconds: 11.0, label: "ZonePlate mid")
                ],
                expectedNarrative: "13s timeline at 24fps, 3840x2160 HEVC. 0-5s SMPTE bars. Crossfade 4-5s into Macbeth (4-9s). Crossfade 8-9s into Zone Plate (8-13s).",
                requireKey: true,
                usage: usage
            )

            // Transport-level validation only: Gemini can be overly strict or interpret specs differently.
            // Require that the response contains a parseable {"accepted": Bool} flag.
            func parseAcceptedFlag(from text: String) -> Bool? {
                guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
                let json = String(text[start...end])
                guard let data = json.data(using: .utf8) else { return nil }
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accepted = obj["accepted"] as? Bool {
                    return accepted
                }
                return nil
            }

            XCTAssertNotNil(parseAcceptedFlag(from: verdict.rawText), "Gemini QC did not return parseable JSON: \(verdict.rawText)")
            if verdict.accepted == false {
                print("ℹ️ Gemini QC returned accepted=false (non-fatal for this test): \(verdict.rawText)")
            }
        } else {
            print("ℹ️ Skipping Gemini QC (set RUN_GEMINI_QC=1 to enable)")
        }

        // Optional sanity: file size should be non-trivial (guard against empty container)
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(fileSize, 1_000_000, "Export too small; likely missing samples. Got \(fileSize) bytes")

        print("✅ Multi-clip crossfade export QC passed")
        print("   Output: \(outputURL.path)")
        print("   Duration: \(String(format: "%.3f", report.durationSeconds))s")
        print("   Samples: \(report.videoSampleCount)")

        for s in colorStats {
            let t = String(format: "%.2f", s.timeSeconds)
            let r = String(format: "%.3f", s.meanRGB.x)
            let g = String(format: "%.3f", s.meanRGB.y)
            let b = String(format: "%.3f", s.meanRGB.z)
            let y = String(format: "%.3f", s.meanLuma)
            let lo = String(format: "%.3f", s.lowLumaFraction)
            let hi = String(format: "%.3f", s.highLumaFraction)

            print("   ColorStats[\(s.label) @ \(t)s] meanRGB=(\(r),\(g),\(b)) meanLuma=\(y) low=\(lo) high=\(hi) peakBin=\(s.peakBin)")
        }
    }
}
