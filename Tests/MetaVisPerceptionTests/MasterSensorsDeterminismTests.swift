import XCTest

@testable import MetaVisPerception

final class MasterSensorsDeterminismTests: XCTestCase {

    func test_ingest_json_is_byte_stable_for_same_input() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")

        let ingestor = MasterSensorIngestor(
            .init(
                videoStrideSeconds: 1.0,
                maxVideoSeconds: 4.0,
                audioAnalyzeSeconds: 4.0,
                enableFaces: true,
                enableSegmentation: true,
                enableAudio: true,
                enableWarnings: true,
                enableDescriptors: true,
                enableSuggestedStart: true
            )
        )

        let s1 = try await ingestor.ingest(url: url)
        let s2 = try await ingestor.ingest(url: url)

        if s1 != s2 {
            XCTFail("In-memory sensors differ across runs: \(describeFirstDifference(a: s1, b: s2))")
            return
        }

        let j1 = try encodeStableJSON(s1)
        let j2 = try encodeStableJSON(s2)

        XCTAssertEqual(j1, j2, "Expected byte-stable JSON encoding for the same input and options")
    }

    private func encodeStableJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func describeFirstDifference(a: MasterSensors, b: MasterSensors) -> String {
        if a.schemaVersion != b.schemaVersion { return "schemaVersion \(a.schemaVersion) != \(b.schemaVersion)" }
        if a.source != b.source { return "source differs: \(a.source) vs \(b.source)" }
        if a.sampling != b.sampling { return "sampling differs: \(a.sampling) vs \(b.sampling)" }

        if a.summary != b.summary { return "summary differs: \(a.summary) vs \(b.summary)" }
        if a.suggestedStart != b.suggestedStart { return "suggestedStart differs: \(String(describing: a.suggestedStart)) vs \(String(describing: b.suggestedStart))" }

        if a.audioSegments.count != b.audioSegments.count {
            return "audioSegments count \(a.audioSegments.count) != \(b.audioSegments.count)"
        }
        for i in 0..<a.audioSegments.count {
            if a.audioSegments[i] != b.audioSegments[i] {
                return "audioSegments[\(i)] differs: \(a.audioSegments[i]) vs \(b.audioSegments[i])"
            }
        }

        if a.warnings.count != b.warnings.count {
            return "warnings count \(a.warnings.count) != \(b.warnings.count)"
        }
        for i in 0..<a.warnings.count {
            if a.warnings[i] != b.warnings[i] {
                return "warnings[\(i)] differs: \(a.warnings[i]) vs \(b.warnings[i])"
            }
        }

        if a.descriptors != b.descriptors {
            let ac = a.descriptors?.count ?? 0
            let bc = b.descriptors?.count ?? 0
            if ac != bc { return "descriptors count \(ac) != \(bc)" }
            if let ad = a.descriptors, let bd = b.descriptors {
                for i in 0..<ad.count {
                    if ad[i] != bd[i] {
                        return "descriptors[\(i)] differs: \(ad[i]) vs \(bd[i])"
                    }
                }
            }
            return "descriptors differ (unknown mismatch)"
        }

        if a.videoSamples.count != b.videoSamples.count {
            return "videoSamples count \(a.videoSamples.count) != \(b.videoSamples.count)"
        }
        for i in 0..<a.videoSamples.count {
            if a.videoSamples[i] != b.videoSamples[i] {
                let va = a.videoSamples[i]
                let vb = b.videoSamples[i]
                if va.faces != vb.faces {
                    return "videoSamples[\(i)] faces differ (t=\(va.time)): \(va.faces) vs \(vb.faces)"
                }
                return "videoSamples[\(i)] differs (t=\(va.time)): \(va) vs \(vb)"
            }
        }

        return "no difference found, but Equatable reported mismatch"
    }
}
