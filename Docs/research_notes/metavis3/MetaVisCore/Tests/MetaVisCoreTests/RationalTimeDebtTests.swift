import XCTest
@testable import MetaVisCore

final class RationalTimeDebtTests: XCTestCase {
    
    func testAdditionOverflowResilience() {
        // Case 1: LCM fits in Int32
        // 40000 and 60000. LCM = 120,000.
        let t3 = RationalTime(value: 1, timescale: 40000)
        let t4 = RationalTime(value: 1, timescale: 60000)
        let sum = t3 + t4
        
        XCTAssertEqual(sum.timescale, 24000, "Timescale should be simplified to 24000")
        XCTAssertEqual(sum.value, 1, "Value should be simplified to 1")
        
        // Case 2: LCM exceeds Int32.max (Fallback Clamping)
        // 60000 * 60001 = 3,600,060,000 > Int32.max
        let t1 = RationalTime(value: 1, timescale: 60000)
        let t2 = RationalTime(value: 1, timescale: 60001)
        let sumOverflow = t1 + t2
        
        // Should not crash. Should return a clamped value.
        XCTAssertEqual(sumOverflow.timescale, Int32.max)
        
        // Check approximation
        // Expected seconds: 1/60000 + 1/60001 = 0.0000166666 + 0.0000166664 = 0.000033333
        // Actual seconds: value / Int32.max
        let expectedSeconds = (1.0/60000.0) + (1.0/60001.0)
        let actualSeconds = sumOverflow.seconds
        
        XCTAssertEqual(actualSeconds, expectedSeconds, accuracy: 0.00000001)
    }
    
    func testComparisonPrecision() {
        // 1/3 vs 0.3333333333333333
        // Double precision has about 15-17 decimal digits.
        
        let t1 = RationalTime(value: 1, timescale: 3)
        // Use a timescale that fits in Int32. Max Int32 is ~2e9.
        // So we can't test 1e16 timescale with Int32 timescale.
        // Let's test something that fits but is close.
        // 1/3 = 0.333333333...
        // 333333333/1000000000 = 0.333333333
        
        let t2 = RationalTime(value: 333333333, timescale: 1000000000)
        
        // t1 is 0.333333333333...
        // t2 is 0.333333333
        // t1 should be strictly greater than t2
        
        XCTAssertTrue(t1 > t2, "1/3 should be greater than 0.333333333")
    }
}
