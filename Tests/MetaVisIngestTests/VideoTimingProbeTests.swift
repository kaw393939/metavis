import XCTest
@testable import MetaVisIngest

final class VideoTimingProbeTests: XCTestCase {

    func test_probe_keithTalk_returnsReasonableStats() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MetaVisIngestTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root

        let url = root
            .appendingPathComponent("Tests")
            .appendingPathComponent("Assets")
            .appendingPathComponent("VideoEdit")
            .appendingPathComponent("keith_talk.mov")

        let profile = try await VideoTimingProbe.probe(url: url)

        if let fps = profile.nominalFPS {
            XCTAssertTrue(fps.isFinite)
            XCTAssertGreaterThan(fps, 0)
            XCTAssertLessThan(fps, 240)
        }

        if let estimated = profile.estimatedFPS {
            XCTAssertTrue(estimated.isFinite)
            XCTAssertGreaterThan(estimated, 0)
            XCTAssertLessThan(estimated, 240)
        }

        if let deltas = profile.deltas {
            XCTAssertGreaterThan(deltas.sampleCount, 10)
            XCTAssertGreaterThan(deltas.meanSeconds, 0)
            XCTAssertGreaterThanOrEqual(deltas.maxSeconds, deltas.minSeconds)
        } else {
            XCTFail("Expected deltas for fixture")
        }
    }
}
