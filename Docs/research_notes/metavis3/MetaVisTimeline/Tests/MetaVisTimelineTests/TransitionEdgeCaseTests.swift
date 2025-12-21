import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TransitionEdgeCaseTests: XCTestCase {
    
    func testTransitionLongerThanClip() throws {
        // Setup: Clip A (0-10) -> Dissolve (20s) -> Clip B (10-20)
        // Transition duration 20s. Half duration 10s.
        // Clip A ends at 10. Extended end: 10 + 10 = 20.
        // Clip B starts at 10. Extended start: 10 - 10 = 0.
        // Overlap: 0 to 20.
        // Clip A starts at 0.
        // So the entire duration of Clip A is covered by the transition.
        
        var timeline = Timeline(name: "Long Transition Test")
        var track = Track(name: "V1")
        
        let transition = Transition(type: .dissolve, duration: RationalTime(value: 20, timescale: 1))
        
        var clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        clipA.outTransition = transition
        
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 10, timescale: 1), duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        
        try track.add(clipA)
        try track.add(clipB)
        timeline.addTrack(track)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Expected Segments:
        // 1. 0.0 - 20.0: [A, B] (Transition)
        // Because Clip A ends at 10, extended to 20.
        // Clip B starts at 10, extended to 0.
        // So from 0 to 20, both are active.
        
        XCTAssertEqual(segments.count, 1)
        
        let segment = segments[0]
        XCTAssertEqual(segment.range.start, .zero)
        XCTAssertEqual(segment.range.duration, RationalTime(value: 20, timescale: 1))
        XCTAssertEqual(segment.activeClips.count, 2)
        XCTAssertEqual(segment.transition, transition)
    }
    
    func testTransitionLongerThanBothClips() throws {
        // Setup: Clip A (0-5) -> Dissolve (20s) -> Clip B (5-10)
        // Transition duration 20s. Half duration 10s.
        // Clip A ends at 5. Extended end: 5 + 10 = 15.
        // Clip B starts at 5. Extended start: 5 - 10 = -5.
        // Overlap: -5 to 15.
        
        var timeline = Timeline(name: "Very Long Transition Test")
        var track = Track(name: "V1")
        
        let transition = Transition(type: .dissolve, duration: RationalTime(value: 20, timescale: 1))
        
        var clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 5, timescale: 1)),
            sourceStartTime: .zero
        )
        clipA.outTransition = transition
        
        let clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 5, timescale: 1), duration: RationalTime(value: 5, timescale: 1)),
            sourceStartTime: .zero
        )
        
        try track.add(clipA)
        try track.add(clipB)
        timeline.addTrack(track)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Expected Segments:
        // 1. -5.0 - 0.0: [B] (Because A starts at 0)
        // 2. 0.0 - 5.0: [A, B]
        // 3. 5.0 - 10.0: [A, B]
        // 4. 10.0 - 15.0: [A] (Because B ends at 10)
        
        // Wait, let's trace carefully.
        // Events:
        // A Start: 0
        // A End: 5 + 10 = 15
        // B Start: 5 - 10 = -5
        // B End: 10
        
        // Sorted Events:
        // -5: Start B
        // 0: Start A
        // 10: End B
        // 15: End A
        
        // Segments:
        // 1. -5 to 0: [B]
        // 2. 0 to 10: [A, B] (Transition)
        // 3. 10 to 15: [A]
        
        XCTAssertEqual(segments.count, 3)
        
        // Segment 1
        XCTAssertEqual(segments[0].range.start, RationalTime(value: -5, timescale: 1))
        XCTAssertEqual(segments[0].activeClips.count, 1)
        XCTAssertEqual(segments[0].activeClips.first?.id, clipB.id)
        
        // Segment 2
        XCTAssertEqual(segments[1].range.start, .zero)
        XCTAssertEqual(segments[1].range.end, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(segments[1].activeClips.count, 2)
        XCTAssertNotNil(segments[1].transition)
        
        // Segment 3
        XCTAssertEqual(segments[2].range.start, RationalTime(value: 10, timescale: 1))
        XCTAssertEqual(segments[2].range.end, RationalTime(value: 15, timescale: 1))
        XCTAssertEqual(segments[2].activeClips.count, 1)
        XCTAssertEqual(segments[2].activeClips.first?.id, clipA.id)
    }
}
