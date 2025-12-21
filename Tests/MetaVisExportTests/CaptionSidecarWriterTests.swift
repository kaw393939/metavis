import XCTest
@testable import MetaVisExport
import MetaVisCore

final class CaptionSidecarWriterTests: XCTestCase {

    func test_writeWebVTT_emptyCues_writesHeader() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("captions.vtt")
        try await CaptionSidecarWriter.writeWebVTT(to: url)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "WEBVTT\n\n")
    }

    func test_writeSRT_emptyCues_writesEmptyFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("captions.srt")
        try await CaptionSidecarWriter.writeSRT(to: url)

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 0)
    }

    func test_writeSRT_withCues_rendersIndexesAndTimestamps() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("captions.srt")
        let cues: [CaptionCue] = [
            .init(startSeconds: 0.0, endSeconds: 1.25, text: "Hello world", speaker: "SPEAKER_00"),
            .init(startSeconds: 1.25, endSeconds: 2.0, text: "Next line")
        ]

        try await CaptionSidecarWriter.writeSRT(to: url, cues: cues)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("1\n00:00:00,000 --> 00:00:01,250\n[SPEAKER_00] Hello world\n\n"))
        XCTAssertTrue(contents.contains("2\n00:00:01,250 --> 00:00:02,000\nNext line\n\n"))
    }

    func test_writeWebVTT_withCues_rendersVoiceTag() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("captions.vtt")
        let cues: [CaptionCue] = [
            .init(startSeconds: 0.0, endSeconds: 0.5, text: "Hey", speaker: "A")
        ]

        try await CaptionSidecarWriter.writeWebVTT(to: url, cues: cues)

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(contents.contains("00:00:00.000 --> 00:00:00.500\n<v A>Hey\n\n"))
    }

    func test_writeWebVTT_withCandidate_prefersCopy() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.captions.vtt")
        let expected = "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\n\n"
        try expected.data(using: .utf8)?.write(to: source, options: [.atomic])

        let dest = dir.appendingPathComponent("captions.vtt")
        try await CaptionSidecarWriter.writeWebVTT(to: dest, sidecarCandidates: [source])

        let contents = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertEqual(contents, expected)
    }

    func test_writeSRT_withCandidate_prefersCopy() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.captions.srt")
        let expected = "1\n00:00:00,000 --> 00:00:01,000\nHello\n\n"
        try expected.data(using: .utf8)?.write(to: source, options: [.atomic])

        let dest = dir.appendingPathComponent("captions.srt")
        try await CaptionSidecarWriter.writeSRT(to: dest, sidecarCandidates: [source])

        let contents = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertEqual(contents, expected)
    }

    func test_writeSRT_withVTTCandidate_convertsToSRT() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.captions.vtt")
        let vtt = "WEBVTT\n\n00:00:00.000 --> 00:00:01.250\n<v A>Hello\n\n"
        try vtt.data(using: .utf8)?.write(to: source, options: [.atomic])

        let dest = dir.appendingPathComponent("captions.srt")
        try await CaptionSidecarWriter.writeSRT(to: dest, sidecarCandidates: [source])

        let contents = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertTrue(contents.contains("1\n00:00:00,000 --> 00:00:01,250\n[A] Hello\n\n"))
    }

    func test_writeWebVTT_withSRTCandidate_convertsToVTT() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appendingPathComponent("source.captions.srt")
        let srt = "1\n00:00:00,000 --> 00:00:01,000\n[A] Hello\n\n"
        try srt.data(using: .utf8)?.write(to: source, options: [.atomic])

        let dest = dir.appendingPathComponent("captions.vtt")
        try await CaptionSidecarWriter.writeWebVTT(to: dest, sidecarCandidates: [source])

        let contents = try String(contentsOf: dest, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("WEBVTT\n\n"))
        XCTAssertTrue(contents.contains("00:00:00.000 --> 00:00:01.000\n<v A>Hello\n\n"))
    }
}
