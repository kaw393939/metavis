import XCTest
@testable import MetaVisCore

final class RationalTimeTests: XCTestCase {
    
    func testInitialization() {
        let t1 = RationalTime(value: 1, timescale: 2)
        XCTAssertEqual(t1.value, 1)
        XCTAssertEqual(t1.timescale, 2)
        XCTAssertEqual(t1.seconds, 0.5)
        
        let t2 = RationalTime(seconds: 1.5, preferredTimescale: 100)
        XCTAssertEqual(t2.value, 150)
        XCTAssertEqual(t2.timescale, 100)
    }
    
    func testEquality() {
        let t1 = RationalTime(value: 1, timescale: 2)
        let t2 = RationalTime(value: 2, timescale: 4) // Same time, different representation
        
        // Semantic equality: 1/2 == 2/4
        XCTAssertEqual(t1, t2)
        XCTAssertEqual(t1.hashValue, t2.hashValue)
    }
    
    func testComparison() {
        let t1 = RationalTime(value: 1, timescale: 3) // 0.333
        let t2 = RationalTime(value: 1, timescale: 2) // 0.5
        
        XCTAssertTrue(t1 < t2)
        XCTAssertFalse(t2 < t1)
    }
    
    func testAddition() {
        let t1 = RationalTime(value: 1, timescale: 4) // 0.25
        let t2 = RationalTime(value: 1, timescale: 4) // 0.25
        let sum = t1 + t2
        XCTAssertEqual(sum.value, 2)
        XCTAssertEqual(sum.timescale, 4)
        
        let t3 = RationalTime(value: 1, timescale: 3) // 1/3
        let t4 = RationalTime(value: 1, timescale: 6) // 1/6
        let sum2 = t3 + t4 // 2/6 + 1/6 = 3/6 = 1/2
        
        // Our implementation does naive multiplication of timescales: 3*6 = 18.
        // (1*6) + (1*3) = 9. Result 9/18.
        // Simplified: 1/2.
        
        XCTAssertEqual(sum2.simplified().value, 1)
        XCTAssertEqual(sum2.simplified().timescale, 2)
    }
}
