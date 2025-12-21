import XCTest
@testable import MetaVisCore

final class TimeRangeTests: XCTestCase {
    
    func testInitialization() {
        let start = RationalTime(value: 0, timescale: 1)
        let duration = RationalTime(value: 10, timescale: 1)
        let range = TimeRange(start: start, duration: duration)
        
        XCTAssertEqual(range.start, start)
        XCTAssertEqual(range.duration, duration)
        XCTAssertEqual(range.end, RationalTime(value: 10, timescale: 1))
    }
    
    func testContainsTime() {
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        ) // 10 to 20
        
        XCTAssertTrue(range.contains(RationalTime(value: 10, timescale: 1)))
        XCTAssertTrue(range.contains(RationalTime(value: 15, timescale: 1)))
        XCTAssertFalse(range.contains(RationalTime(value: 20, timescale: 1))) // Exclusive end
        XCTAssertFalse(range.contains(RationalTime(value: 9, timescale: 1)))
    }
    
    func testIntersection() {
        let r1 = TimeRange(
            start: RationalTime(value: 0, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        ) // 0-10
        
        let r2 = TimeRange(
            start: RationalTime(value: 5, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        ) // 5-15
        
        let intersection = r1.intersection(r2)
        XCTAssertNotNil(intersection)
        XCTAssertEqual(intersection?.start, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(intersection?.duration, RationalTime(value: 5, timescale: 1)) // 5 to 10
        
        let r3 = TimeRange(
            start: RationalTime(value: 20, timescale: 1),
            duration: RationalTime(value: 5, timescale: 1)
        ) // 20-25
        
        XCTAssertNil(r1.intersection(r3))
    }
    
    func testOffset() {
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 5, timescale: 1)
        )
        let offset = RationalTime(value: 2, timescale: 1)
        let newRange = range.offset(by: offset)
        
        XCTAssertEqual(newRange.start, RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(newRange.duration, range.duration)
    }
}
