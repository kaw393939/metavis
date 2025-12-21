import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class CascadingTransitionTests: XCTestCase {
    
    func testCascadingTransitions() throws {
        // Setup:
        // Clip A (0-10) -> Dissolve (4s) -> Clip B (10-11) -> Dissolve (4s) -> Clip C (11-20)
        // Transition A->B: 4s. Half is 2s.
        // A ends at 10 + 2 = 12.
        // B starts at 10 - 2 = 8.
        
        // Transition B->C: 4s. Half is 2s.
        // B ends at 11 + 2 = 13.
        // C starts at 11 - 2 = 9.
        
        // Overlap Analysis:
        // 0-8: A
        // 8-9: A, B (Transition A->B starts)
        // 9-12: A, B, C (Transition B->C starts, A still fading out) -> TRIPLE OVERLAP
        // 12-13: B, C (A finished, B fading out)
        // 13-20: C
        
        var timeline = Timeline(name: "Cascading Transition")
        var track = Track(name: "V1")
        
        let transition = Transition(type: .dissolve, duration: RationalTime(value: 4, timescale: 1))
        
        var clipA = Clip(
            name: "A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        clipA.outTransition = transition
        
        var clipB = Clip(
            name: "B",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 10, timescale: 1), duration: RationalTime(value: 1, timescale: 1)),
            sourceStartTime: .zero
        )
        clipB.outTransition = transition
        
        let clipC = Clip(
            name: "C",
            assetId: UUID(),
            range: TimeRange(start: RationalTime(value: 11, timescale: 1), duration: RationalTime(value: 9, timescale: 1)),
            sourceStartTime: .zero
        )
        
        try track.add(clipA)
        try track.add(clipB)
        try track.add(clipC)
        timeline.addTrack(track)
        
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Find the triple overlap segment (around time 10)
        // We expect a segment with 3 active clips.
        
        let tripleOverlapSegment = segments.first { $0.activeClips.count == 3 }
        XCTAssertNotNil(tripleOverlapSegment, "Should find a segment with 3 active clips")
        
        if let segment = tripleOverlapSegment {
            // Try to build graph
            let builder = TimelineGraphBuilder()
            let graph = try builder.build(from: segment)
            
            // Verify Graph
            // Current implementation of Builder:
            // guard clips.count == 2 else { return graph }
            // So it will return a graph with NO transition node, just 3 source nodes disconnected (or maybe one connected to output).
            
            // We expect it to FAIL to produce a valid transition graph currently.
            // Or rather, we want to see what it does.
            
            let transitionNodes = graph.nodes.values.filter { $0.type.contains("transition") }
            XCTAssertGreaterThan(transitionNodes.count, 0, "Graph should contain transition nodes for triple overlap")
        }
    }
}
