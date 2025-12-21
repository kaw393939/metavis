import XCTest
import MetaVisPerception

final class FaceIdentityServiceHashTests: XCTestCase {

    func testAverageHash64MatchesExpectedBitPattern() {
        // 8x8 luma values 0..63.
        // Average is floor(sum(0..63)/64) = floor(2016/64) = 31.
        // Bits set when luma >= 31 => indices 31..63 are set.
        let luma = (0..<64).map { UInt8($0) }
        let hash = FaceIdentityService.averageHash64(fromLuma8x8: luma)
        XCTAssertEqual(hash, 0xFFFFFFFF80000000)
    }
}
