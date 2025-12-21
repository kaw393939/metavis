import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class GraphBuilderMultiTrackTests: XCTestCase {
    
    func testMultiTrackTransition() throws {
        // Setup:
        // Track 1: Clip Background (0-20)
        // Track 2: Clip A (0-10) -> Dissolve -> Clip B (10-20)
        
        var timeline = Timeline(name: "MultiTrack Transition")
        
        // Track 1
        var track1 = Track(name: "Background")
        let bgClip = Clip(
            name: "BG",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 20, timescale: 1)),
            sourceStartTime: .zero
        )
        try track1.add(bgClip)
        timeline.addTrack(track1)
        
        // Track 2
        var track2 = Track(name: "Foreground")
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
        
        try track2.add(clipA)
        try track2.add(clipB)
        timeline.addTrack(track2)
        
        // Resolve
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // We expect a segment around 10s where:
        // Track 1 has BG
        // Track 2 has A and B (Transitioning)
        
        // Find the transition segment
        guard let transitionSegment = segments.first(where: { $0.transition != nil }) else {
            XCTFail("No transition segment found")
            return
        }
        
        // Build Graph
        let builder = TimelineGraphBuilder()
        let graph = try builder.build(from: transitionSegment)
        
        // Verify Graph Structure
        // Should have:
        // 1. Source BG
        // 2. Source A
        // 3. Source B
        // 4. Dissolve Node (Inputs: A, B)
        // 5. Output Node
        
        // Current Bug Prediction:
        // The builder sorts all clips by track index.
        // Sorted: [BG (Track 0), A (Track 1), B (Track 1)]
        // It takes first 2: BG and A.
        // It creates a transition between BG and A.
        // This is WRONG.
        
        let dissolveNode = graph.nodes.values.first { $0.type == NodeType.Transition.dissolve }
        XCTAssertNotNil(dissolveNode)
        
        // Check inputs to dissolve
        let edgesToDissolve = graph.edges.filter { $0.toNode == dissolveNode?.id }
        XCTAssertEqual(edgesToDissolve.count, 2)
        
        // Find the nodes connected to dissolve
        let inputNodeIDs = edgesToDissolve.map { $0.fromNode }
        let inputNodes = inputNodeIDs.compactMap { graph.nodes[$0] }
        
        // Verify inputs are A and B (from Track 2)
        // Not BG (from Track 1)
        
        let hasBG = inputNodes.contains { $0.properties["assetId"] == .string(bgClip.assetId.uuidString) }
        let hasA = inputNodes.contains { $0.properties["assetId"] == .string(clipA.assetId.uuidString) }
        let hasB = inputNodes.contains { $0.properties["assetId"] == .string(clipB.assetId.uuidString) }
        
        XCTAssertFalse(hasBG, "Dissolve should not include Background clip")
        XCTAssertTrue(hasA, "Dissolve should include Clip A")
        XCTAssertTrue(hasB, "Dissolve should include Clip B")
    }
}
