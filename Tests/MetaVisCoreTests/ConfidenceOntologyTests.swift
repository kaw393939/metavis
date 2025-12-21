import XCTest
@testable import MetaVisCore

final class ConfidenceOntologyTests: XCTestCase {

    func test_confidence_mapping_is_deterministic() {
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 1.0), .VERIFIED)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.95), .VERIFIED)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.94), .STRONG)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.80), .STRONG)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.79), .AMBIGUOUS)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.55), .AMBIGUOUS)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.54), .WEAK)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.30), .WEAK)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 0.29), .INVALID)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: -1.0), .INVALID)
        XCTAssertEqual(ConfidenceMappingV1.grade(for: 2.0), .VERIFIED)
    }

    func test_confidence_record_sorts_sources_and_reasons() {
        let rec = ConfidenceRecordV1(
            score: 0.9,
            grade: .STRONG,
            sources: [.vision, .audio],
            reasons: [.track_reacquired, .cluster_boundary]
        )

        XCTAssertEqual(rec.sources, [.audio, .vision])
        XCTAssertEqual(rec.reasons, [.cluster_boundary, .track_reacquired])
    }
}
