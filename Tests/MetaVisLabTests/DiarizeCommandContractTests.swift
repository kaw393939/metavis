import Foundation
import XCTest
import MetaVisCore
import MetaVisExport
import MetaVisPerception
@testable import MetaVisLab

final class DiarizeCommandContractTests: XCTestCase {

    func test_emits_vtt_with_voice_tags() async throws {
        let outDir = URL(fileURLWithPath: "test_outputs/_diarize_test", isDirectory: true)
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let sensorsURL = outDir.appendingPathComponent("sensors.json")
        let transcriptURL = outDir.appendingPathComponent("transcript.words.v1.jsonl")

        // Minimal sensors: one face + one speechLike segment.
        let faceId = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let sensors = makeSensors(faceId: faceId)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sensorsData = try enc.encode(sensors)
        try sensorsData.write(to: sensorsURL, options: [.atomic])

        // Minimal transcript JSONL.
        let words: [TranscriptWordV1] = [
            TranscriptWordV1(
                schema: "transcript.word.v1",
                wordId: "w1",
                word: "hello",
                confidence: 1.0,
                sourceTimeTicks: 60000,
                sourceTimeEndTicks: 65000,
                speakerId: nil,
                speakerLabel: nil,
                timelineTimeTicks: 60000,
                timelineTimeEndTicks: 65000,
                clipId: nil,
                segmentId: nil
            )
        ]

        let jsonEnc = JSONEncoder()
        jsonEnc.outputFormatting = [.sortedKeys]
        var jsonl = Data()
        for w in words {
            jsonl.append(try jsonEnc.encode(w))
            jsonl.append(0x0A)
        }
        try jsonl.write(to: transcriptURL, options: [.atomic])

        try await DiarizeCommand.run(args: [
            "--sensors", sensorsURL.path,
            "--transcript", transcriptURL.path,
            "--out", outDir.path
        ])

        let vttURL = outDir.appendingPathComponent("captions.vtt")
        let raw = try String(contentsOf: vttURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("<v T1>"), "Expected VTT voice tag. Got:\n\(raw)")

        let attributionURL = outDir.appendingPathComponent("transcript.attribution.v1.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attributionURL.path))

        let attributionRaw = try String(contentsOf: attributionURL, encoding: .utf8)
        let attributionLines = attributionRaw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(attributionLines.count, 1)

        let dec = JSONDecoder()
        let rec = try dec.decode(TranscriptAttributionV1.self, from: Data(attributionLines[0].utf8))
        XCTAssertEqual(rec.wordId, "w1")
        XCTAssertEqual(rec.speakerLabel, "T1")
        XCTAssertGreaterThanOrEqual(rec.attributionConfidence.score, 0.0)
        XCTAssertLessThanOrEqual(rec.attributionConfidence.score, 1.0)
        XCTAssertEqual(rec.attributionConfidence.sources, rec.attributionConfidence.sources.sorted())
        XCTAssertEqual(rec.attributionConfidence.reasons, rec.attributionConfidence.reasons.sorted())

        let mapURL = outDir.appendingPathComponent("speaker_map.v1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mapURL.path))

        let timelineURL = outDir.appendingPathComponent("identity.timeline.v1.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: timelineURL.path))
        let timelineData = try Data(contentsOf: timelineURL)
        let timeline = try JSONDecoder().decode(IdentityTimelineV1.self, from: timelineData)
        XCTAssertEqual(timeline.schema, "identity.timeline.v1")
        XCTAssertGreaterThanOrEqual(timeline.analyzedSeconds, 0.0)
        XCTAssertFalse(timeline.speakers.isEmpty)
        XCTAssertFalse(timeline.spans.isEmpty)
    }

    func test_diarize_outputs_are_deterministic_byte_for_byte() async throws {
        let outA = URL(fileURLWithPath: "test_outputs/_diarize_determinism_a", isDirectory: true)
        let outB = URL(fileURLWithPath: "test_outputs/_diarize_determinism_b", isDirectory: true)
        try? FileManager.default.removeItem(at: outA)
        try? FileManager.default.removeItem(at: outB)
        try FileManager.default.createDirectory(at: outA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outB, withIntermediateDirectories: true)

        let sensorsURL = outA.appendingPathComponent("sensors.json")
        let transcriptURL = outA.appendingPathComponent("transcript.words.v1.jsonl")

        // Minimal sensors: one face + one speechLike segment.
        let faceId = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let sensors = makeSensors(faceId: faceId)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sensorsData = try enc.encode(sensors)
        try sensorsData.write(to: sensorsURL, options: [.atomic])

        // Minimal transcript JSONL.
        let words: [TranscriptWordV1] = [
            TranscriptWordV1(
                schema: "transcript.word.v1",
                wordId: "w1",
                word: "hello",
                confidence: 1.0,
                sourceTimeTicks: 60000,
                sourceTimeEndTicks: 65000,
                speakerId: nil,
                speakerLabel: nil,
                timelineTimeTicks: 60000,
                timelineTimeEndTicks: 65000,
                clipId: nil,
                segmentId: nil
            ),
            TranscriptWordV1(
                schema: "transcript.word.v1",
                wordId: "w2",
                word: "world",
                confidence: 1.0,
                sourceTimeTicks: 65000,
                sourceTimeEndTicks: 70000,
                speakerId: nil,
                speakerLabel: nil,
                timelineTimeTicks: 65000,
                timelineTimeEndTicks: 70000,
                clipId: nil,
                segmentId: nil
            )
        ]

        let jsonEnc = JSONEncoder()
        jsonEnc.outputFormatting = [.sortedKeys]
        var jsonl = Data()
        for w in words {
            jsonl.append(try jsonEnc.encode(w))
            jsonl.append(0x0A)
        }
        try jsonl.write(to: transcriptURL, options: [.atomic])

        // Run A
        try await DiarizeCommand.run(args: [
            "--sensors", sensorsURL.path,
            "--transcript", transcriptURL.path,
            "--out", outA.path
        ])

        // Copy identical inputs into B so paths are independent.
        try sensorsData.write(to: outB.appendingPathComponent("sensors.json"), options: [.atomic])
        try jsonl.write(to: outB.appendingPathComponent("transcript.words.v1.jsonl"), options: [.atomic])

        // Run B
        try await DiarizeCommand.run(args: [
            "--sensors", outB.appendingPathComponent("sensors.json").path,
            "--transcript", outB.appendingPathComponent("transcript.words.v1.jsonl").path,
            "--out", outB.path
        ])

        let artifactNames = [
            "transcript.words.v1.jsonl",
            "transcript.attribution.v1.jsonl",
            "captions.vtt",
            "speaker_map.v1.json",
            "identity.timeline.v1.json"
        ]

        for name in artifactNames {
            let aURL = outA.appendingPathComponent(name)
            let bURL = outB.appendingPathComponent(name)
            let a = try Data(contentsOf: aURL)
            let b = try Data(contentsOf: bURL)
            XCTAssertEqual(a, b, "Expected deterministic artifact: \(name)")
        }
    }

    private func makeSensors(faceId: UUID) -> MasterSensors {
        MasterSensors(
            schemaVersion: 4,
            source: .init(path: "synthetic.mov", durationSeconds: 10.0, width: 1920, height: 1080, nominalFPS: 30),
            sampling: .init(videoStrideSeconds: 0.25, maxVideoSeconds: 10.0, audioAnalyzeSeconds: 10.0),
            videoSamples: [
                .init(
                    time: 1.0,
                    meanLuma: 0,
                    skinLikelihood: 0,
                    dominantColors: [],
                    faces: [
                        .init(trackId: faceId, rect: CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2), personId: "P0")
                    ],
                    personMaskPresence: nil,
                    peopleCountEstimate: 1
                )
            ],
            audioSegments: [
                .init(start: 0.0, end: 10.0, kind: .speechLike, confidence: 0.9)
            ],
            audioFrames: nil,
            audioBeats: nil,
            warnings: [],
            descriptors: nil,
            suggestedStart: nil,
            summary: .init(
                analyzedSeconds: 10.0,
                scene: .init(indoorOutdoor: .init(label: .unknown, confidence: 0.0), lightSource: .init(label: .unknown, confidence: 0.0)),
                audio: .init(approxRMSdBFS: -20, approxPeakDB: -3)
            )
        )
    }
}
