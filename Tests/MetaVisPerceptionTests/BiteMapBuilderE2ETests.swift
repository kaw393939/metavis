import XCTest
@testable import MetaVisPerception

final class BiteMapBuilderE2ETests: XCTestCase {
    func test_biteMapBuilder_keithTalk_producesDeterministicNonEmptyBites() async throws {
        let url = URL(fileURLWithPath: "Tests/Assets/VideoEdit/keith_talk.mov")
        let sensors = try await MasterSensorIngestor().ingest(url: url)

        let bites = BiteMapBuilder.build(from: sensors)

        XCTAssertEqual(bites.schemaVersion, BiteMap.schemaVersion)
        XCTAssertFalse(bites.bites.isEmpty, "Expected some speech bites for keith_talk.mov")

        // Determinism: build twice from same sensors should match exactly.
        let bites2 = BiteMapBuilder.build(from: sensors)
        XCTAssertEqual(bites, bites2)

        // Basic invariants.
        for b in bites.bites {
            XCTAssertLessThan(b.start, b.end)
            XCTAssertFalse(b.personId.isEmpty)
            XCTAssertFalse(b.reason.isEmpty)
        }

        // Single-person fixture expectation.
        let personIds = Set(bites.bites.map { $0.personId })
        XCTAssertEqual(personIds, ["P0"])
    }
}
