import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisQC
import MetaVisSimulation
import MetaVisSession

final class AssetsCoverageE2ETests: XCTestCase {

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

    private func testsAssetsRoot() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let assets = root.appendingPathComponent("Tests").appendingPathComponent("Assets")
        guard FileManager.default.fileExists(atPath: assets.path) else {
            throw XCTSkip("Missing test assets directory: \(assets.path)")
        }
        return assets
    }

    func test_testsAssets_contains_expected_extensions() async throws {
        let assets = try testsAssetsRoot()
        let exts = try allExtensions(under: assets)

        XCTAssertTrue(exts.contains("mov"), "Expected .mov in Tests/Assets")
        XCTAssertTrue(exts.contains("mp4"), "Expected .mp4 in Tests/Assets")
        XCTAssertTrue(exts.contains("exr"), "Expected .exr in Tests/Assets")
        XCTAssertTrue(exts.contains("fits") || exts.contains("fit"), "Expected .fits/.fit in Tests/Assets")
        XCTAssertTrue(exts.contains("vtt"), "Expected .vtt in Tests/Assets")
    }

    func test_each_asset_type_can_be_used_end_to_end() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        DotEnvLoader.loadIfPresent()

        let assets = try testsAssetsRoot()

        let movURL = assets.appendingPathComponent("VideoEdit").appendingPathComponent("keith_talk.mov")
        guard FileManager.default.fileExists(atPath: movURL.path) else {
            throw XCTSkip("Missing asset: \(movURL.path)")
        }

        let vttURL = assets.appendingPathComponent("VideoEdit").appendingPathComponent("keith_talk.captions.vtt")
        guard FileManager.default.fileExists(atPath: vttURL.path) else {
            throw XCTSkip("Missing asset: \(vttURL.path)")
        }

        let mp4URL = try firstFile(withExtension: "mp4", under: assets.appendingPathComponent("genai"))
        let exrURL = try firstFile(withExtension: "exr", under: assets.appendingPathComponent("Exr"))
        let fitsDir = assets.appendingPathComponent("fits")
        let fitsURL = try firstFile(withExtensions: ["fits", "fit"], under: fitsDir)

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        // MOV input path
        do {
            let timeline = Timeline(
                tracks: [
                    Track(
                        name: "MOV",
                        kind: .video,
                        clips: [
                            Clip(
                                name: "keith",
                                asset: AssetReference(sourceFn: movURL.absoluteURL.absoluteString),
                                startTime: .zero,
                                duration: Time(seconds: 0.75)
                            )
                        ]
                    )
                ],
                duration: Time(seconds: 0.75)
            )

            let out = TestOutputs.url(for: "assets_cov_mov", quality: "240p")
            try await exporter.export(
                timeline: timeline,
                to: out,
                quality: draft240p(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .forbidden,
                governance: .none
            )

            _ = try await VideoQC.validateMovie(at: out, expectations: expectations(height: 240, durationSeconds: 0.75, fps: 24.0))
        }

        // MP4 input path
        do {
            let timeline = Timeline(
                tracks: [
                    Track(
                        name: "MP4",
                        kind: .video,
                        clips: [
                            Clip(
                                name: "genai",
                                asset: AssetReference(sourceFn: mp4URL.absoluteURL.absoluteString),
                                startTime: .zero,
                                duration: Time(seconds: 0.75)
                            )
                        ]
                    )
                ],
                duration: Time(seconds: 0.75)
            )

            let out = TestOutputs.url(for: "assets_cov_mp4", quality: "240p")
            try await exporter.export(
                timeline: timeline,
                to: out,
                quality: draft240p(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .forbidden,
                governance: .none
            )

            _ = try await VideoQC.validateMovie(at: out, expectations: expectations(height: 240, durationSeconds: 0.75, fps: 24.0))
        }

        // EXR input path
        do {
            var clip = Clip(
                name: "exr",
                asset: AssetReference(sourceFn: exrURL.absoluteURL.absoluteString),
                startTime: .zero,
                duration: Time(seconds: 0.25)
            )
            clip.effects = [.init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])]

            let timeline = Timeline(
                tracks: [Track(name: "EXR", kind: .video, clips: [clip])],
                duration: Time(seconds: 0.25)
            )

            let out = TestOutputs.url(for: "assets_cov_exr", quality: "240p")
            try await exporter.export(
                timeline: timeline,
                to: out,
                quality: draft240p(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .forbidden,
                governance: .none
            )

            _ = try await VideoQC.validateMovie(at: out, expectations: expectations(height: 240, durationSeconds: 0.25, fps: 24.0))
            _ = try await VideoContentQC.validateColorStats(
                movieURL: out,
                samples: [
                    .init(
                        timeSeconds: 0.0,
                        label: "exr",
                        minMeanLuma: 0.01,
                        maxMeanLuma: 0.99,
                        maxChannelDelta: 1.0,
                        minLowLumaFraction: 0.0,
                        minHighLumaFraction: 0.0
                    )
                ]
            )
        }

        // FITS input path
        do {
            var clip = Clip(
                name: "fits",
                asset: AssetReference(sourceFn: fitsURL.absoluteURL.absoluteString),
                startTime: .zero,
                duration: Time(seconds: 0.25)
            )
            clip.effects = [
                .init(
                    id: "com.metavis.fx.false_color.turbo",
                    parameters: ["exposure": .float(0.0), "gamma": .float(1.0)]
                )
            ]

            let timeline = Timeline(
                tracks: [Track(name: "FITS", kind: .video, clips: [clip])],
                duration: Time(seconds: 0.25)
            )

            let out = TestOutputs.url(for: "assets_cov_fits", quality: "240p")
            try await exporter.export(
                timeline: timeline,
                to: out,
                quality: draft240p(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .forbidden,
                governance: .none
            )

            _ = try await VideoQC.validateMovie(at: out, expectations: expectations(height: 240, durationSeconds: 0.25, fps: 24.0))
            _ = try await VideoContentQC.validateColorStats(
                movieURL: out,
                samples: [
                    .init(
                        timeSeconds: 0.0,
                        label: "fits",
                        minMeanLuma: 0.01,
                        maxMeanLuma: 0.99,
                        maxChannelDelta: 1.0,
                        minLowLumaFraction: 0.0,
                        minHighLumaFraction: 0.0
                    )
                ]
            )
        }

        // VTT sidecar path (best-effort caption discovery based on a single file-backed clip)
        do {
            let recipe = CustomSingleClipRecipe(assetURL: movURL, durationSeconds: 2.0)
            let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

            let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("assets_cov_vtt_deliverable", isDirectory: true)
            try? FileManager.default.removeItem(at: bundleURL)

            _ = try await session.exportDeliverable(
                using: exporter,
                to: bundleURL,
                deliverable: .reviewProxy,
                quality: draft240p(),
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .forbidden,
                sidecars: [.captionsVTT()]
            )

            let outVTT = bundleURL.appendingPathComponent("captions.vtt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: outVTT.path), "Expected captions.vtt sidecar")

            let text = String(data: try Data(contentsOf: outVTT), encoding: .utf8) ?? ""
            XCTAssertTrue(text.contains("WEBVTT"), "Expected WEBVTT header in captions.vtt")
            XCTAssertTrue(text.contains("Welcome back."), "Expected captions.vtt to contain content from the sibling sidecar")
        }
    }

    // MARK: - Helpers

    private func allExtensions(under root: URL) throws -> Set<String> {
        var out: Set<String> = []
        let fm = FileManager.default
        let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = e?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty { out.insert(ext) }
        }
        return out
    }

    private func firstFile(withExtension ext: String, under dir: URL) throws -> URL {
        try firstFile(withExtensions: [ext], under: dir)
    }

    private func firstFile(withExtensions exts: [String], under dir: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw XCTSkip("Missing directory: \(dir.path)")
        }

        let allowed = Set(exts.map { $0.lowercased() })
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard let first = urls.first else {
            throw XCTSkip("No files with extensions \(exts) found in \(dir.path)")
        }

        return first
    }

    private struct CustomSingleClipRecipe: ProjectRecipe {
        let id: String = "com.metavis.recipe.assets_cov_single_clip"
        let name: String = "Assets Coverage Single Clip"
        let assetURL: URL
        let durationSeconds: Double

        func makeInitialState() -> ProjectState {
            let duration = Time(seconds: durationSeconds)
            let clip = Clip(
                name: "Input",
                asset: AssetReference(sourceFn: assetURL.absoluteURL.absoluteString),
                startTime: .zero,
                duration: duration
            )

            let video = Track(name: "Video", kind: .video, clips: [clip])
            let timeline = Timeline(tracks: [video], duration: duration)

            return ProjectState(timeline: timeline, config: ProjectConfig())
        }
    }
}
