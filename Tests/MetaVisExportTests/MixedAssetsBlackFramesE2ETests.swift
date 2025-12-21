import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisQC
import MetaVisSimulation

final class MixedAssetsBlackFramesE2ETests: XCTestCase {

    private func requireTool(_ name: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [name, "-version"]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw XCTSkip("\(name) not available")
        }
    }

    private func draft240p() -> QualityProfile {
        QualityProfile(name: "Draft 240p", fidelity: .draft, resolutionHeight: 240, colorDepth: 10)
    }

    private func expectations(height: Int, durationSeconds: Double, fps: Double) -> VideoQC.Expectations {
        let tol = max(0.10, min(0.50, durationSeconds * 0.02))
        let expectedFrames = Int((durationSeconds * fps).rounded())
        return VideoQC.Expectations(
            minDurationSeconds: durationSeconds - tol,
            maxDurationSeconds: durationSeconds + tol,
            expectedWidth: height * 16 / 9,
            expectedHeight: height,
            expectedNominalFrameRate: fps,
            minVideoSampleCount: max(1, Int(Double(expectedFrames) * 0.80))
        )
    }

    private func assertNoNearBlackFrames(
        movieURL: URL,
        durationSeconds: Double,
        sampleCount: Int = 24,
        minMeanLuma: Float = 0.012,
        maxLowLumaFraction: Float = 0.985,
        maxNearBlackSamples: Int = 0,
        allowNearBlackTimeRanges: [(start: Double, end: Double)] = []
    ) async throws {
        let endEpsilon = 1.0 / 600.0
        let maxT = max(0.0, durationSeconds - endEpsilon)
        guard maxT > 0 else { return }

        let n = max(3, sampleCount)
        let times = (0..<n).map { i -> Double in
            let t = (Double(i) + 0.5) / Double(n)
            return min(maxT, t * maxT)
        }

        func isInAllowedWindow(_ t: Double) -> Bool {
            for r in allowNearBlackTimeRanges {
                if t >= r.start && t <= r.end { return true }
            }
            return false
        }

        let samples: [VideoContentQC.ColorStatsSample] = times.enumerated().compactMap { (i, t) -> VideoContentQC.ColorStatsSample? in
            if isInAllowedWindow(t) { return nil }
            return VideoContentQC.ColorStatsSample(
                timeSeconds: t,
                label: String(format: "t%02d", i),
                // Keep these tolerant but still catch black-frame regressions.
                minMeanLuma: minMeanLuma,
                maxMeanLuma: 0.995,
                maxChannelDelta: 1.0,
                minLowLumaFraction: 0.0,
                minHighLumaFraction: 0.0
            )
        }

        if samples.isEmpty { return }

        let results = try await VideoContentQC.validateColorStats(movieURL: movieURL, samples: samples)

        var nearBlackCount = 0
        for r in results {
            let isNearBlack = (r.meanLuma < minMeanLuma) || (r.lowLumaFraction > maxLowLumaFraction)
            if isNearBlack {
                nearBlackCount += 1
                XCTFail("Near-black frame at \(r.label): meanLuma=\(r.meanLuma), lowLumaFraction=\(r.lowLumaFraction)")
            }
        }

        if nearBlackCount > maxNearBlackSamples {
            XCTFail("Too many near-black samples: \(nearBlackCount) > \(maxNearBlackSamples)")
        }
    }

    func test_mixedTimeline_includingFITS_exports_andIsNotNearBlack() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        DotEnvLoader.loadIfPresent()

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let assets = root.appendingPathComponent("Tests").appendingPathComponent("Assets")

        let movURL = assets.appendingPathComponent("VideoEdit").appendingPathComponent("keith_talk.mov")
        guard FileManager.default.fileExists(atPath: movURL.path) else {
            throw XCTSkip("Missing asset: \(movURL.path)")
        }

        let genaiDir = assets.appendingPathComponent("genai")
        let mp4s = try FileManager.default.contentsOfDirectory(at: genaiDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let mp4URL = mp4s.first else {
            throw XCTSkip("Missing MP4 under \(genaiDir.path)")
        }

        let exrDir = assets.appendingPathComponent("Exr")
        let exrs = try FileManager.default.contentsOfDirectory(at: exrDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "exr" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let exrURL = exrs.first else {
            throw XCTSkip("Missing EXR under \(exrDir.path)")
        }

        let fitsDir = assets.appendingPathComponent("fits")
        let fits = try FileManager.default.contentsOfDirectory(at: fitsDir, includingPropertiesForKeys: nil)
            .filter { ["fits", "fit"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard let fitsURL = fits.first else {
            throw XCTSkip("Missing FITS under \(fitsDir.path)")
        }

        // Stress composition and decoding: mix file-backed video + stills (EXR/FITS) with transitions.
        // Keep short and deterministic.
        let fps: Int = 24
        let fade = Time(seconds: 0.20)

        // Clip 0: MP4 0.0..0.7 with wipe out.
        var c0 = Clip(name: "mp4", asset: AssetReference(sourceFn: mp4URL.absoluteURL.absoluteString), startTime: .zero, duration: Time(seconds: 0.7))
        c0.transitionOut = Transition(type: .wipe(direction: .leftToRight), duration: fade, easing: .linear)

        // Clip 1: FITS 0.5..1.0 with wipe in, dip out. Add turbo false color so it’s visually non-black.
        var c1 = Clip(name: "fits", asset: AssetReference(sourceFn: fitsURL.absoluteURL.absoluteString), startTime: Time(seconds: 0.5), duration: Time(seconds: 0.5))
        c1.transitionIn = Transition(type: .wipe(direction: .leftToRight), duration: fade, easing: .linear)
        c1.transitionOut = .dipToBlack(duration: fade)
        c1.effects = [
            .init(id: "com.metavis.fx.false_color.turbo", parameters: ["exposure": .float(0.0), "gamma": .float(1.0)])
        ]

        // Clip 2: EXR 0.9..1.2 with dip in. Add tonemap so it lands in Rec.709 range.
        var c2 = Clip(name: "exr", asset: AssetReference(sourceFn: exrURL.absoluteURL.absoluteString), startTime: Time(seconds: 0.9), duration: Time(seconds: 0.3))
        c2.transitionIn = .dipToBlack(duration: fade)
        c2.effects = [
            .init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])
        ]

        // Clip 3: MOV 1.1..1.8 with crossfade in.
        var c3 = Clip(name: "mov", asset: AssetReference(sourceFn: movURL.absoluteURL.absoluteString), startTime: Time(seconds: 1.1), duration: Time(seconds: 0.7))
        c3.transitionIn = .crossfade(duration: fade, easing: .easeInOut)

        let track = Track(name: "V", kind: .video, clips: [c0, c1, c2, c3])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.8))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let out = TestOutputs.url(for: "mixed_assets_including_fits", quality: "240p")

        try await exporter.export(
            timeline: timeline,
            to: out,
            quality: draft240p(),
            frameRate: fps,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        _ = try await VideoQC.validateMovie(
            at: out,
            expectations: expectations(height: 240, durationSeconds: timeline.duration.seconds, fps: 24.0)
        )

        // Prove content changes over time (guards against stuck clip selection).
        try await VideoContentQC.assertTemporalVariety(
            movieURL: out,
            samples: [
                .init(timeSeconds: 0.20, label: "mp4"),
                .init(timeSeconds: 0.75, label: "fits"),
                .init(timeSeconds: 1.05, label: "exr"),
                .init(timeSeconds: 1.55, label: "mov")
            ]
        )

        // Stronger black-frame guard across the whole deliverable.
        // Note: this timeline includes an intentional dip-to-black region around the FITS→EXR handoff.
        // Exclude that small window so this check only catches unexpected black frames.
        try await assertNoNearBlackFrames(
            movieURL: out,
            durationSeconds: timeline.duration.seconds,
            sampleCount: 28,
            minMeanLuma: 0.012,
            maxLowLumaFraction: 0.985,
            maxNearBlackSamples: 0,
            allowNearBlackTimeRanges: [(start: 0.90, end: 1.02)]
        )
    }

    func test_exported_video_has_no_black_frame_regression_on_realMOV() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        DotEnvLoader.loadIfPresent()

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let movURL = root
            .appendingPathComponent("Tests")
            .appendingPathComponent("Assets")
            .appendingPathComponent("VideoEdit")
            .appendingPathComponent("keith_talk.mov")

        guard FileManager.default.fileExists(atPath: movURL.path) else {
            throw XCTSkip("Missing asset: \(movURL.path)")
        }

        let clip = Clip(
            name: "keith",
            asset: AssetReference(sourceFn: movURL.absoluteURL.absoluteString),
            startTime: .zero,
            duration: Time(seconds: 1.5)
        )

        let timeline = Timeline(tracks: [Track(name: "V", kind: .video, clips: [clip])], duration: Time(seconds: 1.5))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let out = TestOutputs.url(for: "black_frame_guard_keith", quality: "240p")
        try await exporter.export(
            timeline: timeline,
            to: out,
            quality: draft240p(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        _ = try await VideoQC.validateMovie(
            at: out,
            expectations: expectations(height: 240, durationSeconds: 1.5, fps: 24.0)
        )

        try await assertNoNearBlackFrames(
            movieURL: out,
            durationSeconds: 1.5,
            sampleCount: 24,
            minMeanLuma: 0.015,
            maxLowLumaFraction: 0.98,
            maxNearBlackSamples: 0
        )
    }
}
