import XCTest
import MetaVisCore

final class ConfidenceLevelV1Tests: XCTestCase {
    func test_encodeDecode_roundTrips() throws {
        let levels: [ConfidenceLevelV1] = [.deterministic, .heuristic, .modelEstimated, .inferred]
        let enc = JSONEncoder()
        let dec = JSONDecoder()

        for l in levels {
            let data = try enc.encode(l)
            let out = try dec.decode(ConfidenceLevelV1.self, from: data)
            XCTAssertEqual(out, l)
        }
    }

    func test_provenance_kind_unknown_decodes() throws {
        let json = #"{"kind":"new_future_kind","id":"x"}"#
        let dec = JSONDecoder()
        let ref = try dec.decode(ProvenanceRefV1.self, from: Data(json.utf8))
        XCTAssertEqual(ref.kind, .unknown)
        XCTAssertEqual(ref.id, "x")
    }
}
