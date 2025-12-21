import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class TransitionTests: XCTestCase {
    
    func testTransitionStruct() {
        let transition = Transition(type: .dissolve, duration: RationalTime(value: 1, timescale: 1))
        XCTAssertEqual(transition.type, .dissolve)
        XCTAssertEqual(transition.duration, RationalTime(value: 1, timescale: 1))
    }
    
    func testClipWithTransition() {
        let transition = Transition(type: .dissolve, duration: RationalTime(value: 1, timescale: 1))
        var clip = Clip(
            name: "Clip A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        clip.outTransition = transition
        
        XCTAssertEqual(clip.outTransition, transition)
    }
    
    func testResolverWithTransition() throws {
        // Setup: Clip A (0-10) -> Dissolve (1s) -> Clip B (10-20)
        // Transition is centered at 10s.
        // Overlap: 9.5s to 10.5s.
        
        var timeline = Timeline(name: "Transition Test")
        var track = Track(name: "V1")
        
        let transition = Transition(type: .dissolve, duration: RationalTime(value: 1, timescale: 1))
        
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
        // 1. 0.0 - 9.5: [A]
        // 2. 9.5 - 10.5: [A, B] (Transition)
        // 3. 10.5 - 20.0: [B]
        
        // Note: RationalTime(1, 1) / 2 = RationalTime(1, 2) = 0.5s
        // 10s - 0.5s = 9.5s = 19/2
        // 10s + 0.5s = 10.5s = 21/2
        
        XCTAssertEqual(segments.count, 3)
        
        // Segment 1
        XCTAssertEqual(segments[0].range.end, RationalTime(value: 19, timescale: 2)) // 9.5s
        XCTAssertEqual(segments[0].activeClips.count, 1)
        XCTAssertEqual(segments[0].activeClips.first?.id, clipA.id)
        XCTAssertNil(segments[0].transition)
        
        // Segment 2 (Transition)
        let transSegment = segments[1]
        XCTAssertEqual(transSegment.range.start, RationalTime(value: 19, timescale: 2)) // 9.5s
        XCTAssertEqual(transSegment.range.duration, RationalTime(value: 1, timescale: 1)) // 1.0s
        XCTAssertEqual(transSegment.activeClips.count, 2)
        XCTAssertEqual(transSegment.transition, transition) // New property on TimelineSegment
        
        // Segment 3
        XCTAssertEqual(segments[2].range.start, RationalTime(value: 21, timescale: 2)) // 10.5s
        XCTAssertEqual(segments[2].activeClips.count, 1)
        XCTAssertEqual(segments[2].activeClips.first?.id, clipB.id)
    }
}
