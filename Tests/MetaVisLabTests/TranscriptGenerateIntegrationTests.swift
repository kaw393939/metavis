import XCTest
@testable import MetaVisLab

final class TranscriptGenerateIntegrationTests: XCTestCase {
    func test_transcript_generate_runsWhisperAndEmitsArtifacts_whenEnabled() async throws {
        let env = ProcessInfo.processInfo.environment

        guard env["METAVIS_RUN_WHISPERCPP_TESTS"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_WHISPERCPP_TESTS=1 to enable whisper.cpp integration tests.")
        }
        guard let whisperCppBin = env["WHISPERCPP_BIN"], !whisperCppBin.isEmpty,
              let whisperCppModel = env["WHISPERCPP_MODEL"], !whisperCppModel.isEmpty else {
            throw XCTSkip("Set WHISPERCPP_BIN and WHISPERCPP_MODEL to enable whisper.cpp integration tests.")
        }

        let input = "Tests/Assets/people_talking/A_man_and_woman_talking.mp4"

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metavis_whisper_it", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        try await TranscriptCommand.run(args: [
            "generate",
            "--input", input,
            "--out", tmpDir.path,
            "--max-seconds", "12",
            "--write-adjacent-captions", "false"
        ])

        let wordsURL = tmpDir.appendingPathComponent("transcript.words.v1.jsonl")
        let summaryURL = tmpDir.appendingPathComponent("transcript.summary.v1.json")
        let captionsURL = tmpDir.appendingPathComponent("captions.vtt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: wordsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: captionsURL.path))

        // Validate JSONL is parseable and non-empty.
        let raw = try String(contentsOf: wordsURL, encoding: .utf8)
        let lines = raw.split(separator: "\n").map(String.init)
        XCTAssertFalse(lines.isEmpty, "Expected at least one word in JSONL")

        struct TranscriptWordV1: Decodable {
            var schema: String
            var wordId: String
            var word: String
            var confidence: Double
            var sourceTimeTicks: Int64
            var sourceTimeEndTicks: Int64
            var timelineTimeTicks: Int64?
            var timelineTimeEndTicks: Int64?
        }

        let decoder = JSONDecoder()
        for line in lines.prefix(10) {
            let obj = try decoder.decode(TranscriptWordV1.self, from: Data(line.utf8))
            XCTAssertEqual(obj.schema, "transcript.word.v1")
            XCTAssertTrue(obj.wordId.hasPrefix("w_"))
            XCTAssertFalse(obj.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertGreaterThanOrEqual(obj.confidence, 0.0)
            XCTAssertLessThanOrEqual(obj.confidence, 1.0)
            XCTAssertLessThanOrEqual(obj.sourceTimeTicks, obj.sourceTimeEndTicks)
            // v1: timeline mirrors source for raw transcription.
            XCTAssertEqual(obj.timelineTimeTicks, obj.sourceTimeTicks)
            XCTAssertEqual(obj.timelineTimeEndTicks, obj.sourceTimeEndTicks)
        }

        // Validate summary includes tool + model identifiers.
        struct TranscriptSummaryV1: Decodable {
            var schema: String
            var tool: Tool
            struct Tool: Decodable {
                var name: String
                var model: String
            }
        }
        let summary = try decoder.decode(TranscriptSummaryV1.self, from: Data(contentsOf: summaryURL))
        XCTAssertEqual(summary.schema, "transcript.summary.v1")
        XCTAssertTrue(summary.tool.name.lowercased().contains("whisper"), "Unexpected tool name: \(summary.tool.name)")
        XCTAssertEqual(summary.tool.name, URL(fileURLWithPath: whisperCppBin).lastPathComponent)
        XCTAssertEqual(summary.tool.model, URL(fileURLWithPath: whisperCppModel).lastPathComponent)

        // Captions should be non-empty.
        let vtt = try String(contentsOf: captionsURL, encoding: .utf8)
        XCTAssertTrue(vtt.contains("WEBVTT"))
    }
}
