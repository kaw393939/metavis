import XCTest
@testable import MetaVisCore

final class RationalTimePrecisionTests: XCTestCase {
    
    func testComparisonPrecision() {
        // Test values that are distinct in RationalTime but might be equal in Double
        // 1/3 vs (1/3 + epsilon)
        // 1/3 = 0.333333333333333333...
        // Let's construct two numbers that differ by less than Double.epsilon
        
        // Double has 53 bits of precision (~15-17 decimal digits).
        // Int64 has 63 bits.
        
        // t1 = 1 / 100
        // t2 = 1 / 100 + 1 / 10^17
        // 1/100 = 10^15 / 10^17
        // t2 = (10^15 + 1) / 10^17
        
        // Timescale 10^17 doesn't fit in Int32. RationalTime uses Int32 timescale.
        // So we are limited by Int32 timescale (2e9).
        // With Int32 timescale, the smallest difference is 1/2e9 = 5e-10.
        // Double precision is ~1e-16.
        // So Double is actually MORE precise than RationalTime with Int32 timescale for small deltas.
        
        // However, for LARGE values, Double loses precision.
        // t1 = 1,000,000,000.0
        // t2 = 1,000,000,000.0 + 1/2000
        // Double can handle this.
        
        // Let's try a case where Double fails: Large magnitude + small difference.
        // t1 = 2^53 (9,007,199,254,740,992)
        // t2 = 2^53 + 1
        // In Double, t1 == t2.
        // In RationalTime (value: 2^53, timescale: 1), they should be different.
        
        let largeVal = Int64(9_007_199_254_740_992)
        let t1 = RationalTime(value: largeVal, timescale: 1)
        let t2 = RationalTime(value: largeVal + 1, timescale: 1)
        
        XCTAssertNotEqual(t1, t2)
        XCTAssertTrue(t1 < t2)
        
        // Current implementation uses `lhs.seconds < rhs.seconds`.
        // t1.seconds = 9007199254740992.0
        // t2.seconds = 9007199254740993.0
        // Double(Int64) might lose precision if > 2^53.
        // 9007199254740993 cannot be represented exactly in Double. It rounds to ...992 or ...994.
        
        // Let's verify if the current implementation fails.
    }
    
    func testAdditionOverflow() {
        // Test addition that would overflow Int64 if not handled carefully
        // value = 1e10, timescale = 1
        // rhs = 1/1e9 (timescale 1e9)
        // common denom = 1e9
        // lhsScaled = 1e10 * 1e9 = 1e19 > Int64.max (9e18)
        
        let t1 = RationalTime(value: 10_000_000_000, timescale: 1)
        let t2 = RationalTime(value: 1, timescale: 1_000_000_000)
        
        // This should not crash
        let sum = t1 + t2
        
        // Expected: 10000000000 + 0.000000001
        // Value: 10000000000000000001 (overflows Int64)
        // So we expect it to handle it, maybe by simplifying or clamping?
        // Or maybe we expect it to fail currently?
        // The current implementation WILL crash or overflow.
    }
}
