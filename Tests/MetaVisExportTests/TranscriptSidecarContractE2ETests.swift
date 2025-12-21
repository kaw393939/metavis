import XCTest
import AVFoundation
import MetaVisExport
import MetaVisCore
import MetaVisSession
import MetaVisTimeline
@testable import MetaVisSimulation
import MetaVisQC

final class TranscriptSidecarContractE2ETests: XCTestCase {

    func test_export_deliverable_writes_transcript_words_json_sidecar() async throws {
        DotEnvLoader.loadIfPresent()

        let recipe = StandardRecipes.SmokeTest2s()
        let session = ProjectSession(recipe: recipe, entitlements: EntitlementManager(initialPlan: .pro))

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_transcript_words_contract", isDirectory: true)
        try? FileManager.default.removeItem(at: bundleURL)

        let cues: [CaptionCue] = [
            .init(startSeconds: 0.25, endSeconds: 0.75, text: "hello world", speaker: "A"),
            .init(startSeconds: 1.00, endSeconds: 1.50, text: "this is a test", speaker: nil)
        ]

        _ = try await session.exportDeliverable(
            using: exporter,
            to: bundleURL,
            deliverable: .reviewProxy,
            quality: QualityProfile(name: "Draft", fidelity: .draft, resolutionHeight: 256, colorDepth: 8),
            frameRate: 24,
            codec: AVVideoCodecType.hevc,
            audioPolicy: .auto,
            sidecars: [
                .transcriptWordsJSON(fileName: "transcript_words.json", cues: cues, required: true)
            ]
        )

        let transcriptURL = bundleURL.appendingPathComponent("transcript_words.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptURL.path), "Missing transcript_words.json")

        let data = try Data(contentsOf: transcriptURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(TranscriptArtifact.self, from: data)

        XCTAssertEqual(artifact.schemaVersion, 1)
        XCTAssertEqual(artifact.tickScale, 60000)
        XCTAssertGreaterThan(artifact.words.count, 0)

        // Basic monotonicity + tick mapping sanity.
        var prevTimelineStart: Int64 = -1
        for w in artifact.words {
            XCTAssertFalse(w.text.isEmpty)
            XCTAssertLessThanOrEqual(w.timelineStartTicks, w.timelineEndTicks)
            XCTAssertLessThanOrEqual(w.sourceStartTicks, w.sourceEndTicks)
            XCTAssertGreaterThanOrEqual(w.timelineStartTicks, prevTimelineStart)
            prevTimelineStart = w.timelineStartTicks
        }

        // Specific expected mapping for the first cue: "hello world" across 0.25-0.75 seconds.
        // 0.25s -> 15000 ticks, 0.75s -> 45000 ticks.
        XCTAssertEqual(artifact.words.first?.timelineStartTicks, 15000)
        XCTAssertEqual(artifact.words.first?.sourceStartTicks, 15000)
        XCTAssertEqual(artifact.words.first?.speaker, "A")

        // Ensure determinism on re-decode: the same file should decode identically.
        let artifact2 = try decoder.decode(TranscriptArtifact.self, from: data)
        XCTAssertEqual(artifact, artifact2)
    }

    func test_export_deliverable_transcript_words_json_uses_caption_discovery() async throws {
        DotEnvLoader.loadIfPresent()

        let fm = FileManager.default

        // Use a small file-backed source so caption discovery applies.
        let sourceURL = URL(fileURLWithPath: "Tests/Assets/genai/grey_void.mp4")
        XCTAssertTrue(fm.fileExists(atPath: sourceURL.path), "Missing fixture: \(sourceURL.path)")

        // Copy to a temp dir so we can write sibling caption files without modifying repo assets.
        let tempDir = TestOutputs.baseDirectory.appendingPathComponent("tmp_transcript_caption_discovery", isDirectory: true)
        try? fm.removeItem(at: tempDir)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let localMovieURL = tempDir.appendingPathComponent("source.mp4")
        try? fm.removeItem(at: localMovieURL)
        try fm.copyItem(at: sourceURL, to: localMovieURL)

        // This filename pattern is what `ProjectSession.captionSidecarCandidates(...)` looks for.
        let captionsURL = tempDir.appendingPathComponent("source.captions.vtt")
        let vtt = """
        WEBVTT

        00:00:00.200 --> 00:00:00.600
        <v A>hello world

        """
        try vtt.data(using: .utf8)!.write(to: captionsURL, options: [.atomic])

        let duration = Time(seconds: 2.0)
        let videoTrack = Track(
            name: "Video",
            kind: .video,
            clips: [
                Clip(
                    name: "FileClip",
                    asset: AssetReference(sourceFn: localMovieURL.path),
                    startTime: .zero,
                    duration: duration
                )
            ]
        )
        let timeline = Timeline(tracks: [videoTrack], duration: duration)

        let session = ProjectSession(
            initialState: ProjectState(timeline: timeline, config: ProjectConfig()),
            entitlements: EntitlementManager(initialPlan: .pro)
        )

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let bundleURL = TestOutputs.baseDirectory.appendingPathComponent("deliverable_transcript_words_discovery", isDirectory: true)
        try? fm.removeItem(at: bundleURL)

        _ = try await session.exportDeliverable(
            using: exporter,
            to: bundleURL,
            deliverable: .reviewProxy,
            quality: QualityProfile(name: "Draft", fidelity: .draft, resolutionHeight: 256, colorDepth: 8),
            frameRate: 24,
            codec: AVVideoCodecType.hevc,
            audioPolicy: .auto,
            sidecars: [
                // Empty cues forces the writer down the discovery path.
                .transcriptWordsJSON(fileName: "transcript_words.json", cues: [], required: true)
            ]
        )

        let transcriptURL = bundleURL.appendingPathComponent("transcript_words.json")
        XCTAssertTrue(fm.fileExists(atPath: transcriptURL.path), "Missing transcript_words.json")

        let data = try Data(contentsOf: transcriptURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let artifact = try decoder.decode(TranscriptArtifact.self, from: data)

        XCTAssertEqual(artifact.tickScale, 60000)
        XCTAssertGreaterThanOrEqual(artifact.words.count, 2)
        XCTAssertEqual(artifact.words[0].text, "hello")
        XCTAssertEqual(artifact.words[1].text, "world")
        XCTAssertEqual(artifact.words[0].speaker, "A")
        XCTAssertEqual(artifact.words[1].speaker, "A")

        // 0.2s -> 12000 ticks; 0.6s -> 36000 ticks; split across two words.
        XCTAssertEqual(artifact.words[0].timelineStartTicks, 12000)
        XCTAssertEqual(artifact.words[0].timelineEndTicks, 24000)
        XCTAssertEqual(artifact.words[1].timelineStartTicks, 24000)
        XCTAssertEqual(artifact.words[1].timelineEndTicks, 36000)
    }
}
