import XCTest

@testable import MetaVisPerception

final class AutoColorCorrectIntegrationE2ETests: XCTestCase {

    func test_realAsset_ingest_then_propose_is_deterministic_and_within_whitelist() async throws {
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

        let sensors1 = try await ingestor.ingest(url: url)
        let sensors2 = try await ingestor.ingest(url: url)
        XCTAssertEqual(sensors1, sensors2, "Expected sensors ingest to be deterministic for same input")

        let p1 = AutoColorGradeProposalV1.propose(from: sensors1, options: .init(seed: "seed"))
        let p2 = AutoColorGradeProposalV1.propose(from: sensors2, options: .init(seed: "seed"))
        XCTAssertEqual(p1, p2, "Expected grade proposal to be deterministic for same sensors")

        // Byte-stable JSON encoding for auditing / caching.
        let j1 = try encodeStableJSON(p1)
        let j2 = try encodeStableJSON(p2)
        XCTAssertEqual(j1, j2)

        // Assert proposal params are within its own whitelist bounds.
        for (key, value) in p1.grade.params {
            let wlKey = "grade.params.\(key)"
            guard let rule = p1.whitelist.numeric[wlKey] else {
                XCTFail("Missing whitelist rule for \(wlKey)")
                continue
            }
            XCTAssertGreaterThanOrEqual(value, rule.min, "\(wlKey) below min")
            XCTAssertLessThanOrEqual(value, rule.max, "\(wlKey) above max")
        }
    }

    private func encodeStableJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
