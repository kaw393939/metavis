import XCTest
import Foundation
import MetaVisPerception
import MetaVisCore

final class IdentityBindingGraphBuilderFixtureAcceptanceTests: XCTestCase {

    func test_fixture_bindsTwoSpeakersToDistinctTracks_withHighPosterior() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["METAVIS_BINDING_ACCEPTANCE"] == "1" else {
            throw XCTSkip(
                "Set METAVIS_BINDING_ACCEPTANCE=1 to enable this strict fixture-based acceptance test. " +
                "Point it at a pre-generated fixture directory via METAVIS_BINDING_ACCEPTANCE_FIXTURE_DIR=<dir> containing sensors.json + transcript.words.v1.jsonl. " +
                "(This test is intentionally strict and may require stronger visual speaking cues than face rects alone.)"
            )
        }

        // Uses pre-generated diarized words + sensors from test_outputs.
        // The directory is intentionally configurable so we can iterate on hard fixtures
        // without changing test code.
        let base: URL = {
            if let override = env["METAVIS_BINDING_ACCEPTANCE_FIXTURE_DIR"], !override.isEmpty {
                if override.hasPrefix("/") {
                    return URL(fileURLWithPath: override, isDirectory: true)
                }
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(override, isDirectory: true)
            }
            // Default (only used if no override is supplied): a short, clean two-speaker clip.
            return URL(fileURLWithPath: "test_outputs/_diarize_integration/Two_men_talking_202512192152_8bc18/run1", isDirectory: true)
        }()
        let sensorsURL = base.appendingPathComponent("sensors.json")
        let wordsURL = base.appendingPathComponent("transcript.words.v1.jsonl")

        guard FileManager.default.fileExists(atPath: sensorsURL.path), FileManager.default.fileExists(atPath: wordsURL.path) else {
            throw XCTSkip("Missing pre-generated diarize outputs at \(base.path)")
        }

        let decoder = JSONDecoder()
        let sensors = try decoder.decode(MasterSensors.self, from: Data(contentsOf: sensorsURL))

        let rawWords = try String(contentsOf: wordsURL, encoding: .utf8)
        let lines = rawWords
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map(String.init)

        let diarizedWords: [TranscriptWordV1] = try lines.map { line in
            try decoder.decode(TranscriptWordV1.self, from: Data(line.utf8))
        }

        // Sanity: ensure the fixture contains at least two non-offscreen speakers in diarized words.
        let speakerIds = Array(Set(diarizedWords.compactMap { w -> String? in
            guard let sid = w.speakerId, sid != "OFFSCREEN" else { return nil }
            return sid
        })).sorted()

        XCTAssertGreaterThanOrEqual(speakerIds.count, 2, "Expected >= 2 non-offscreen speakers in diarized words. Got \(speakerIds)")

        let bindings = IdentityBindingGraphBuilder.build(sensors: sensors, words: diarizedWords)

        func bestEdge(for speakerId: String) -> IdentityBindingEdgeV1? {
            let edges = bindings.bindings.filter { $0.speakerId == speakerId }
            return edges.max { a, b in
                if a.posterior != b.posterior { return a.posterior < b.posterior }
                return a.trackId.uuidString > b.trackId.uuidString
            }
        }

        let topA = bestEdge(for: speakerIds[0])
        let topB = bestEdge(for: speakerIds[1])

        let availableSpeakerIds = Array(Set(bindings.bindings.map { $0.speakerId })).sorted()
        let edgeSummary = bindings.bindings
            .sorted { a, b in
                if a.speakerId != b.speakerId { return a.speakerId < b.speakerId }
                if a.posterior != b.posterior { return a.posterior > b.posterior }
                return a.trackId.uuidString < b.trackId.uuidString
            }
            .map { e in
                let p = String(format: "%.3f", e.posterior)
                return "\(e.speakerId)->\(e.trackId.uuidString.prefix(8)) p=\(p)"
            }
            .joined(separator: ", ")

        XCTAssertNotNil(topA, "Missing binding edge for speaker \(speakerIds[0]). Available speakerIds: \(availableSpeakerIds). Edges: [\(edgeSummary)]")
        XCTAssertNotNil(topB, "Missing binding edge for speaker \(speakerIds[1]). Available speakerIds: \(availableSpeakerIds). Edges: [\(edgeSummary)]")

        guard let topA, let topB else { return }

        XCTAssertNotEqual(topA.trackId, topB.trackId, "Expected distinct face tracks for the two speakers. Got \(topA.trackId) for \(speakerIds[0]) and \(topB.trackId) for \(speakerIds[1]).")

        XCTAssertGreaterThanOrEqual(topA.posterior, 0.8, "Expected high posterior for speaker \(speakerIds[0]). Got \(topA.posterior)")
        XCTAssertGreaterThanOrEqual(topB.posterior, 0.8, "Expected high posterior for speaker \(speakerIds[1]). Got \(topB.posterior)")
    }
}
