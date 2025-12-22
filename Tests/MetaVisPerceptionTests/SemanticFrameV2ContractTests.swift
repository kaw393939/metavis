import XCTest
import MetaVisPerception
import MetaVisCore

final class SemanticFrameV2ContractTests: XCTestCase {
    func test_encodeDecode_roundTrips() throws {
        let conf = ConfidenceRecordV1.evidence(score: 1.0, sources: [.vision])
        let v = EvidencedValueV1(value: "P1", confidence: conf, confidenceLevel: .deterministic, provenance: [.metric("x", value: 1.0)])
        let attr = SemanticAttributeV1(key: "personId", value: .string(v))
        let subj = SemanticSubjectV2(trackId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, personId: "P1", rect: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4), attributes: [attr])
        let frame = SemanticFrameV2(timestampSeconds: 1.25, subjects: [subj])

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(frame)

        let dec = JSONDecoder()
        let out = try dec.decode(SemanticFrameV2.self, from: data)
        XCTAssertEqual(out, frame)
        XCTAssertEqual(out.schema, "semantic.frame.v2")
    }
}
