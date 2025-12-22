import Foundation
import XCTest
import MetaVisPerception
import MetaVisCore
@testable import MetaVisLab

final class DiarizeIntegrationTests: XCTestCase {

    func test_diarize_man_and_woman_produces_two_speakers_whenEnabled() async throws {
        let out = try await runPipeline(
            input: "Tests/Assets/people_talking/A_man_and_woman_talking.mp4",
            maxTranscriptSeconds: 22,
            allowLarge: false
        )

        let env = ProcessInfo.processInfo.environment
        let mode = (env["METAVIS_DIARIZE_MODE"] ?? "").lowercased()
        if mode != "ecapa" {
            throw XCTSkip("Aggressive multi-speaker expectations require METAVIS_DIARIZE_MODE=ecapa")
        }

        let speakerCount = out.nonOffscreenSpeakerCount
        XCTAssertEqual(speakerCount, 2, "Expected 2 speakers (man + woman). Got: \(speakerCount). map=\(out.speakerLabels)")
        XCTAssertTrue(out.vtt.contains("<v T1>") || out.vtt.contains("<v T2>"))
    }

    func test_diarize_two_men_produces_two_speakers_whenEnabled() async throws {
        let out = try await runPipeline(
            input: "Tests/Assets/people_talking/Two_men_talking_202512192152_8bc18.mp4",
            maxTranscriptSeconds: 25,
            allowLarge: false
        )

        let env = ProcessInfo.processInfo.environment
        let mode = (env["METAVIS_DIARIZE_MODE"] ?? "").lowercased()
        if mode != "ecapa" {
            throw XCTSkip("Aggressive multi-speaker expectations require METAVIS_DIARIZE_MODE=ecapa")
        }

        let speakerCount = out.nonOffscreenSpeakerCount
        XCTAssertEqual(speakerCount, 2, "Expected 2 speakers (two men). Got: \(speakerCount). map=\(out.speakerLabels)")
    }

    func test_diarize_two_scene_four_speakers_produces_three_or_four_speakers_whenEnabled() async throws {
        let out = try await runPipeline(
            input: "Tests/Assets/people_talking/two_scene_four_speakers.mp4",
            maxTranscriptSeconds: 40,
            allowLarge: false
        )

        let env = ProcessInfo.processInfo.environment
        let mode = (env["METAVIS_DIARIZE_MODE"] ?? "").lowercased()
        if mode != "ecapa" {
            throw XCTSkip("Aggressive multi-speaker expectations require METAVIS_DIARIZE_MODE=ecapa")
        }

        let n = out.nonOffscreenSpeakerCount
        XCTAssertTrue((3...4).contains(n), "Expected 3 or 4 speakers (allowing one brief speaker to be missed). Got: \(n). map=\(out.speakerLabels)")

        // Aggressive sanity: speaker labels should be contiguous T1..Tn (no gaps) for non-offscreen.
        XCTAssertTrue(out.hasContiguousTLabels, "Expected contiguous T labels. labels=\(out.speakerLabels)")

        // Aggressive sanity: should actually emit voice tags.
        XCTAssertTrue(out.vtt.contains("<v T1>"), "Expected VTT to include voice tags. Got:\n\(out.vtt.prefix(300))")

        // Assert diarized transcript is non-empty and has meaningful speaker switching.
        XCTAssertGreaterThan(out.diarizedWords.count, 10, "Expected diarized transcript to contain words")

        let speakerIds = out.diarizedWords.compactMap { w -> String? in
            let sid = w.speakerId
            if sid == nil { return nil }
            if sid == "OFFSCREEN" { return nil }
            return sid
        }
        XCTAssertGreaterThanOrEqual(Set(speakerIds).count, 3, "Expected >= 3 distinct non-offscreen speakerIds in diarized words")

        // Switch count (rough): adjacent diarized words with different speakerId.
        let switches = zip(speakerIds, speakerIds.dropFirst()).filter { $0 != $1 }.count
        XCTAssertGreaterThanOrEqual(switches, 2, "Expected multiple speaker switches in two-scene clip")
    }

    func test_diarize_two_scene_four_speakers_detects_offscreen_whenStrictEnabled() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["METAVIS_DIARIZE_STRICT"] == "1" else {
            throw XCTSkip("Set METAVIS_DIARIZE_STRICT=1 to enable strict offscreen expectations.")
        }

        let out = try await runPipeline(
            input: "Tests/Assets/people_talking/two_scene_four_speakers.mp4",
            maxTranscriptSeconds: 40,
            allowLarge: false
        )

        let mode = (env["METAVIS_DIARIZE_MODE"] ?? "").lowercased()
        if mode != "ecapa" {
            throw XCTSkip("Strict multi-speaker expectations require METAVIS_DIARIZE_MODE=ecapa")
        }

        let hasOffscreenInMap = out.speakerMap.speakers.contains { $0.speakerId == "OFFSCREEN" || $0.speakerLabel == "OFFSCREEN" }
        let hasOffscreenInWords = out.diarizedWords.contains { $0.speakerId == "OFFSCREEN" || $0.speakerLabel == "OFFSCREEN" }
        XCTAssertTrue(hasOffscreenInMap || hasOffscreenInWords, "Expected OFFSCREEN speaker to be detected in strict mode. map=\(out.speakerLabels)")
    }

    func test_diarize_keith_talk_produces_one_or_two_speakers_whenEnabled() async throws {
        let out = try await runPipeline(
            input: "Tests/Assets/VideoEdit/keith_talk.mov",
            maxTranscriptSeconds: 35,
            allowLarge: true
        )

        let n = out.nonOffscreenSpeakerCount
        XCTAssertTrue((1...2).contains(n), "Expected 1–2 speakers for keith_talk. Got: \(n). map=\(out.speakerLabels)")
    }

    // MARK: - Pipeline

    private struct PipelineOutput {
        var speakerMap: SpeakerDiarizer.SpeakerMapV1
        var vtt: String
        var diarizedWords: [TranscriptWordV1]
        var attributions: [TranscriptAttributionV1]

        var speakerLabels: [String] {
            speakerMap.speakers.map { "\($0.speakerLabel)" }
        }

        var nonOffscreenSpeakerCount: Int {
            speakerMap.speakers.filter { $0.speakerLabel != "OFFSCREEN" && $0.speakerId != "OFFSCREEN" }.count
        }

        var hasContiguousTLabels: Bool {
            let labels = speakerMap.speakers
                .map { $0.speakerLabel }
                .filter { $0 != "OFFSCREEN" }
            guard !labels.isEmpty else { return true }
            let tNumbers: [Int] = labels.compactMap { label in
                guard label.hasPrefix("T") else { return nil }
                return Int(label.dropFirst())
            }
            guard tNumbers.count == labels.count else { return false }
            let sorted = tNumbers.sorted()
            guard let first = sorted.first else { return true }
            if first != 1 { return false }
            for (idx, n) in sorted.enumerated() {
                if n != idx + 1 { return false }
            }
            return true
        }
    }

    private struct DiarizeRunArtifacts {
        var speakerMap: SpeakerDiarizer.SpeakerMapV1
        var vtt: String
        var diarizedWords: [TranscriptWordV1]
        var attributions: [TranscriptAttributionV1]
        var temporal: TemporalContextV1
        var bindings: IdentityBindingGraphV1
        var semanticFrames: [SemanticFrameV2]
    }

    private func runPipeline(input: String, maxTranscriptSeconds: Int, allowLarge: Bool) async throws -> PipelineOutput {
        let env = ProcessInfo.processInfo.environment

        guard env["METAVIS_RUN_DIARIZE_TESTS"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_DIARIZE_TESTS=1 to enable diarization integration tests.")
        }
        guard env["METAVIS_RUN_WHISPERCPP_TESTS"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_WHISPERCPP_TESTS=1 to enable whisper.cpp integration dependency.")
        }
        guard let whisperCppBin = env["WHISPERCPP_BIN"], !whisperCppBin.isEmpty,
              let whisperCppModel = env["WHISPERCPP_MODEL"], !whisperCppModel.isEmpty else {
            throw XCTSkip("Set WHISPERCPP_BIN and WHISPERCPP_MODEL to enable diarization integration tests.")
        }

        // Keep output in a deterministic location for debugging.
        let base = URL(fileURLWithPath: "test_outputs/_diarize_integration", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let stem = URL(fileURLWithPath: input).deletingPathExtension().lastPathComponent
        let outDir = base.appendingPathComponent(stem, isDirectory: true)
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var sensorsArgs: [String] = [
            "ingest",
            "--input", input,
            "--out", outDir.path,
            "--stride", "0.25",
            "--max-video-seconds", String(Double(maxTranscriptSeconds) + 5.0),
            "--audio-seconds", String(Double(maxTranscriptSeconds) + 5.0)
        ]
        if allowLarge {
            sensorsArgs.append("--allow-large")
        }

        try await SensorsCommand.run(args: sensorsArgs)

        var transcriptArgs: [String] = [
            "generate",
            "--input", input,
            "--out", outDir.path,
            "--max-seconds", String(maxTranscriptSeconds),
            "--write-adjacent-captions", "false"
        ]
        if allowLarge {
            transcriptArgs.append("--allow-large")
        }

        // TranscriptCommand uses env vars already present (WHISPERCPP_*).
        _ = whisperCppBin
        _ = whisperCppModel
        try await TranscriptCommand.run(args: transcriptArgs)

        let sensorsURL = outDir.appendingPathComponent("sensors.json")
        let transcriptURL = outDir.appendingPathComponent("transcript.words.v1.jsonl")

        // Run diarization twice from identical inputs and assert byte-for-byte determinism.
        let artifacts1 = try await runDiarizeOnce(outDir: outDir, runName: "run1", sensorsURL: sensorsURL, transcriptURL: transcriptURL)
        _ = try await runDiarizeOnce(outDir: outDir, runName: "run2", sensorsURL: sensorsURL, transcriptURL: transcriptURL)

        let compareFiles: [String] = [
            "transcript.words.v1.jsonl",
            "transcript.attribution.v1.jsonl",
            "captions.vtt",
            "speaker_map.v1.json",
            "temporal.context.v1.json",
            "identity.bindings.v1.json",
            "semantic.frame.v2.jsonl"
        ]

        for f in compareFiles {
            let a = outDir.appendingPathComponent("run1", isDirectory: true).appendingPathComponent(f)
            let b = outDir.appendingPathComponent("run2", isDirectory: true).appendingPathComponent(f)
            let da = try Data(contentsOf: a)
            let db = try Data(contentsOf: b)
            XCTAssertEqual(da, db, "Expected deterministic diarize output for \(f)")
        }

        // Validate attribution sidecar aligns with diarized transcript.
        XCTAssertEqual(artifacts1.attributions.count, artifacts1.diarizedWords.count, "Expected one attribution per transcript word")

        let wordIds = Set(artifacts1.diarizedWords.map { $0.wordId })
        let attributionWordIds = Set(artifacts1.attributions.map { $0.wordId })
        XCTAssertEqual(wordIds, attributionWordIds, "Attribution wordIds should match transcript wordIds")

        for a in artifacts1.attributions {
            XCTAssertEqual(a.schema, "transcript.attribution.v1")
            XCTAssertTrue((0.0...1.0).contains(a.attributionConfidence.score), "Score must be in [0,1]. Got \(a.attributionConfidence.score)")
            XCTAssertEqual(a.attributionConfidence.sources, a.attributionConfidence.sources.sorted())
            XCTAssertEqual(a.attributionConfidence.reasons, a.attributionConfidence.reasons.sorted())
        }

        XCTAssertEqual(artifacts1.temporal.schema, "temporal.context.v1")
        XCTAssertTrue(artifacts1.temporal.analyzedSeconds > 0)

        XCTAssertEqual(artifacts1.bindings.schema, "identity.bindings.v1")
        XCTAssertTrue(artifacts1.bindings.analyzedSeconds > 0)

        for e in artifacts1.bindings.bindings {
            XCTAssertTrue((0.0...1.0).contains(e.posterior), "Posterior must be in [0,1]. Got \(e.posterior)")
            XCTAssertTrue((0.0...1.0).contains(Double(e.confidence.score)), "Score must be in [0,1]. Got \(e.confidence.score)")
        }

        XCTAssertFalse(artifacts1.semanticFrames.isEmpty, "Expected semantic.frame.v2.jsonl to contain records")
        XCTAssertEqual(artifacts1.semanticFrames.first?.schema, "semantic.frame.v2")

        // SemanticFrameV2Builder extensions sanity: frame-level metric tags and per-subject speaking surface.
        if let first = artifacts1.semanticFrames.first {
            XCTAssertFalse(first.contextTags.isEmpty)
            XCTAssertTrue(first.contextTags.contains("video.meanLuma"))
            XCTAssertTrue(first.contextTags.contains("video.faces.count"))
        }

        if let firstSubject = artifacts1.semanticFrames.first?.subjects.first {
            let keys = Set(firstSubject.attributes.map { $0.key })
            XCTAssertTrue(keys.contains("isSpeaking"))
        }

        return PipelineOutput(
            speakerMap: artifacts1.speakerMap,
            vtt: artifacts1.vtt,
            diarizedWords: artifacts1.diarizedWords,
            attributions: artifacts1.attributions
        )
    }

    private func runDiarizeOnce(outDir: URL, runName: String, sensorsURL: URL, transcriptURL: URL) async throws -> DiarizeRunArtifacts {
        let runDir = outDir.appendingPathComponent(runName, isDirectory: true)
        try? FileManager.default.removeItem(at: runDir)
        try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)

        // Copy inputs so each diarize run starts from identical bytes.
        try FileManager.default.copyItem(at: sensorsURL, to: runDir.appendingPathComponent("sensors.json"))
        try FileManager.default.copyItem(at: transcriptURL, to: runDir.appendingPathComponent("transcript.words.v1.jsonl"))

        try await DiarizeCommand.run(args: [
            "--sensors", runDir.appendingPathComponent("sensors.json").path,
            "--transcript", runDir.appendingPathComponent("transcript.words.v1.jsonl").path,
            "--out", runDir.path
        ])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let mapURL = runDir.appendingPathComponent("speaker_map.v1.json")
        let vttURL = runDir.appendingPathComponent("captions.vtt")
        let diarizedWordsURL = runDir.appendingPathComponent("transcript.words.v1.jsonl")
        let attributionsURL = runDir.appendingPathComponent("transcript.attribution.v1.jsonl")
        let temporalURL = runDir.appendingPathComponent("temporal.context.v1.json")
        let bindingsURL = runDir.appendingPathComponent("identity.bindings.v1.json")
        let semanticURL = runDir.appendingPathComponent("semantic.frame.v2.jsonl")

        let map = try decoder.decode(SpeakerDiarizer.SpeakerMapV1.self, from: Data(contentsOf: mapURL))
        let vtt = try String(contentsOf: vttURL, encoding: .utf8)

        let rawWords = try String(contentsOf: diarizedWordsURL, encoding: .utf8)
        let wordLines = rawWords.split(separator: "\n").map(String.init)
        let diarizedWords: [TranscriptWordV1] = try wordLines.map { line in
            try decoder.decode(TranscriptWordV1.self, from: Data(line.utf8))
        }

        let rawAttrib = try String(contentsOf: attributionsURL, encoding: .utf8)
        let attribLines = rawAttrib.split(separator: "\n").map(String.init)
        let attributions: [TranscriptAttributionV1] = try attribLines.map { line in
            try decoder.decode(TranscriptAttributionV1.self, from: Data(line.utf8))
        }

        let temporal = try decoder.decode(TemporalContextV1.self, from: Data(contentsOf: temporalURL))
        let bindings = try decoder.decode(IdentityBindingGraphV1.self, from: Data(contentsOf: bindingsURL))

        let rawSemantic = try String(contentsOf: semanticURL, encoding: .utf8)
        let semanticLines = rawSemantic.split(separator: "\n").map(String.init)
        let semanticFrames: [SemanticFrameV2] = try semanticLines.map { line in
            try decoder.decode(SemanticFrameV2.self, from: Data(line.utf8))
        }

        return DiarizeRunArtifacts(
            speakerMap: map,
            vtt: vtt,
            diarizedWords: diarizedWords,
            attributions: attributions,
            temporal: temporal,
            bindings: bindings,
            semanticFrames: semanticFrames
        )
    }
}
