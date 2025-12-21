import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class ClipDebtTests: XCTestCase {
    
    func testCodableValidation() throws {
        // Case 1: Mismatched durations via JSON
        // We can't create mismatched durations via init anymore, so we test Codable.
        
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000000",
            "name": "Bad Clip",
            "assetId": "00000000-0000-0000-0000-000000000001",
            "range": {
                "start": { "value": 0, "timescale": 1 },
                "duration": { "value": 10, "timescale": 1 }
            },
            "sourceRange": {
                "start": { "value": 0, "timescale": 1 },
                "duration": { "value": 5, "timescale": 1 }
            }
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(try JSONDecoder().decode(Clip.self, from: json)) { error in
            guard let decodingError = error as? DecodingError,
                  case .dataCorrupted(let context) = decodingError else {
                XCTFail("Expected dataCorrupted error")
                return
            }
            XCTAssertTrue(context.debugDescription.contains("must match"))
        }
    }
    
    func testNegativeTrimming() {
        var clip = Clip(
            name: "Trim Test",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        // Trim by negative amount (Grow?)
        // Current implementation:
        // range.start += amount (-2) -> start = -2
        // range.duration -= amount (-2) -> duration = 12
        // This effectively grows the clip backwards.
        
        let neg = RationalTime(value: -2, timescale: 1)
        clip.trimStart(by: neg)
        
        XCTAssertEqual(clip.range.start, neg)
        XCTAssertEqual(clip.range.duration, RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(clip.sourceRange.duration, RationalTime(value: 12, timescale: 1))
    }
}
