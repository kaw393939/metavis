import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TimelineResolverPerformanceTests: XCTestCase {
    
    func testComplexTimelineResolution() throws {
        // Create a timeline with overlapping clips on multiple tracks
        var timeline = Timeline(name: "Complex")
        
        // Track 1: Clips at 0-10, 20-30
        var t1 = Track(name: "V1")
        let cA = Clip(name: "A", assetId: UUID(), range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)), sourceStartTime: .zero)
        let cB = Clip(name: "B", assetId: UUID(), range: TimeRange(start: RationalTime(value: 20, timescale: 1), duration: RationalTime(value: 10, timescale: 1)), sourceStartTime: .zero)
        try t1.add(cA)
        try t1.add(cB)
        
        // Track 2: Clips at 5-15, 25-35
        var t2 = Track(name: "V2")
        let cC = Clip(name: "C", assetId: UUID(), range: TimeRange(start: RationalTime(value: 5, timescale: 1), duration: RationalTime(value: 10, timescale: 1)), sourceStartTime: .zero)
        let cD = Clip(name: "D", assetId: UUID(), range: TimeRange(start: RationalTime(value: 25, timescale: 1), duration: RationalTime(value: 10, timescale: 1)), sourceStartTime: .zero)
        try t2.add(cC)
        try t2.add(cD)
        
        timeline.addTrack(t1)
        timeline.addTrack(t2)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Expected Segments (skipping gaps):
        // 1. 0-5: [A]
        // 2. 5-10: [A, C]
        // 3. 10-15: [C]
        // -- Gap 15-20 --
        // 4. 20-25: [B]
        // 5. 25-30: [B, D]
        // 6. 30-35: [D]
        
        XCTAssertEqual(segments.count, 6)
        
        // Verify Segment 2 (5-10)
        let seg2 = segments[1]
        XCTAssertEqual(seg2.range.start, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(seg2.range.duration, RationalTime(value: 5, timescale: 1))
        XCTAssertEqual(seg2.activeClips.count, 2)
        
        // Verify IDs
        let ids = Set(seg2.activeClips.map { $0.id })
        XCTAssertTrue(ids.contains(cA.id))
        XCTAssertTrue(ids.contains(cC.id))
    }
}
