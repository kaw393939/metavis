import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class ClipTests: XCTestCase {
    
    func testClipInitialization() {
        let start = RationalTime(value: 10, timescale: 24)
        let duration = RationalTime(value: 24, timescale: 24)
        let range = TimeRange(start: start, duration: duration)
        
        let sourceStart = RationalTime(value: 0, timescale: 24)
        // sourceRange is derived
        
        let clip = Clip(name: "Test Clip", assetId: UUID(), range: range, sourceStartTime: sourceStart)
        
        XCTAssertEqual(clip.name, "Test Clip")
        XCTAssertEqual(clip.range, range)
        XCTAssertEqual(clip.sourceRange.start, sourceStart)
        XCTAssertEqual(clip.sourceRange.duration, duration)
    }
    
    func testTimeMapping() {
        // Clip on timeline: 10s to 20s
        // Source media: 0s to 10s
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        )
        let sourceStart = RationalTime(value: 0, timescale: 1)
        
        let clip = Clip(name: "Mapping Test", assetId: UUID(), range: range, sourceStartTime: sourceStart)
        
        // Test inside
        let tMid = RationalTime(value: 15, timescale: 1)
        let mapped = clip.mapTime(tMid)
        XCTAssertEqual(mapped, RationalTime(value: 5, timescale: 1))
        
        // Test start boundary
        let tStart = RationalTime(value: 10, timescale: 1)
        XCTAssertEqual(clip.mapTime(tStart), RationalTime(value: 0, timescale: 1))
        
        // Test end boundary (exclusive)
        // Usually clips are [start, end).
        let tEnd = RationalTime(value: 20, timescale: 1)
        XCTAssertNil(clip.mapTime(tEnd))
        
        // Test outside
        let tPre = RationalTime(value: 9, timescale: 1)
        XCTAssertNil(clip.mapTime(tPre))
    }
    
    func testMoving() {
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        )
        let sourceStart = RationalTime(value: 0, timescale: 1)
        
        var clip = Clip(name: "Move Test", assetId: UUID(), range: range, sourceStartTime: sourceStart)
        
        // Move to 30s
        let newStart = RationalTime(value: 30, timescale: 1)
        clip.move(to: newStart)
        
        XCTAssertEqual(clip.range.start, newStart)
        XCTAssertEqual(clip.range.duration, range.duration)
        XCTAssertEqual(clip.sourceRange.start, sourceStart) // Source shouldn't change
    }
    
    func testTrimmingStart() {
        // Timeline: 10s-20s
        // Source: 0s-10s
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        )
        let sourceStart = RationalTime(value: 0, timescale: 1)
        
        var clip = Clip(name: "Trim Start", assetId: UUID(), range: range, sourceStartTime: sourceStart)
        
        // Trim 2s from start
        // New Timeline: 12s-20s (Duration 8s)
        // New Source: 2s-10s (Duration 8s)
        let trimAmount = RationalTime(value: 2, timescale: 1)
        clip.trimStart(by: trimAmount)
        
        XCTAssertEqual(clip.range.start, RationalTime(value: 12, timescale: 1))
        XCTAssertEqual(clip.range.duration, RationalTime(value: 8, timescale: 1))
        
        XCTAssertEqual(clip.sourceRange.start, RationalTime(value: 2, timescale: 1))
        XCTAssertEqual(clip.sourceRange.duration, RationalTime(value: 8, timescale: 1))
    }
    
    func testTrimmingEnd() {
        // Timeline: 10s-20s
        // Source: 0s-10s
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        )
        let sourceStart = RationalTime(value: 0, timescale: 1)
        
        var clip = Clip(name: "Trim End", assetId: UUID(), range: range, sourceStartTime: sourceStart)
        
        // Trim 2s from end
        // New Timeline: 10s-18s (Duration 8s)
        // New Source: 0s-8s (Duration 8s)
        let trimAmount = RationalTime(value: 2, timescale: 1)
        clip.trimEnd(by: trimAmount)
        
        XCTAssertEqual(clip.range.start, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(clip.range.duration, RationalTime(value: 8, timescale: 1))
        
        XCTAssertEqual(clip.sourceRange.start, RationalTime(value: 0, timescale: 1))
        XCTAssertEqual(clip.sourceRange.duration, RationalTime(value: 8, timescale: 1))
    }
    
    func testSlip() {
        // Slip: Changing the source range without changing the timeline range.
        // Timeline: 10s-20s
        // Source: 0s-10s
        let range = TimeRange(
            start: RationalTime(value: 10, timescale: 1),
            duration: RationalTime(value: 10, timescale: 1)
        )
        let sourceStart = RationalTime(value: 0, timescale: 1)
        
        var clip = Clip(name: "Slip Test", assetId: UUID(), range: range, sourceStartTime: sourceStart)
        
        // Slip 5s forward
        // Timeline: 10s-20s (Unchanged)
        // Source: 5s-15s
        let slipAmount = RationalTime(value: 5, timescale: 1)
        clip.slip(by: slipAmount)
        
        XCTAssertEqual(clip.range.start, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(clip.range.duration, RationalTime(value: 10, timescale: 1))
        
        XCTAssertEqual(clip.sourceRange.start, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(clip.sourceRange.duration, RationalTime(value: 10, timescale: 1))
    }
}
