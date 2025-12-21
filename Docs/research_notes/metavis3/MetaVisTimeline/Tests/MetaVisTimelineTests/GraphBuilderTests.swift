import XCTest
import MetaVisCore
@testable import MetaVisTimeline

final class GraphBuilderTests: XCTestCase {
    
    func testSimpleCutGraph() throws {
        // Setup: 1 Clip
        var timeline = Timeline(name: "Simple Cut")
        var track = Track(name: "V1")
        let clip = Clip(
            name: "Clip A",
            assetId: UUID(),
            range: TimeRange(start: .zero, duration: RationalTime(value: 10, timescale: 1)),
            sourceStartTime: .zero
        )
        try track.add(clip)
        timeline.addTrack(track)
        
        // Resolve
        let resolver = TimelineResolver()
        let segments = resolver.resolve(timeline: timeline)
        
        // Build Graph
        let builder = TimelineGraphBuilder()
        let graph = try builder.build(from: segments[0])
        
        // Verify
        // Should have:
        // 1. Source Node (for Clip A)
        // 2. Output Node
        // 3. Edge Source -> Output
        
        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.edges.count, 1)
        
        let sourceNode = graph.nodes.values.first { $0.type == NodeType.source }
        let outputNode = graph.nodes.values.first { $0.type == NodeType.output }
        
        XCTAssertNotNil(sourceNode)
        XCTAssertNotNil(outputNode)
        
        // Check Edge
        let edge = graph.edges.first
        XCTAssertEqual(edge?.fromNode, sourceNode?.id)
        XCTAssertEqual(edge?.toNode, outputNode?.id)
    }
    
    func testTransitionGraph() throws {
        // Setup: Clip A -> Dissolve -> Clip B
        var timeline = Timeline(name: "Transition")
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
        
        // Segment 1: Transition (Index 1 in the previous test logic)
        // The resolver produces: [A only], [A+B Transition], [B only]
        // We want to test the graph for the Transition segment.
        let transitionSegment = segments[1]
        
        let builder = TimelineGraphBuilder()
        let graph = try builder.build(from: transitionSegment)
        
        // Verify
        // Should have:
        // 1. Source Node A
        // 2. Source Node B
        // 3. Dissolve Node
        // 4. Output Node
        // Edges: A -> Dissolve, B -> Dissolve, Dissolve -> Output
        
        XCTAssertEqual(graph.nodes.count, 4)
        XCTAssertEqual(graph.edges.count, 3)
        
        let dissolveNode = graph.nodes.values.first { $0.type == NodeType.Transition.dissolve }
        XCTAssertNotNil(dissolveNode)
        
        // Check inputs to dissolve
        let edgesToDissolve = graph.edges.filter { $0.toNode == dissolveNode?.id }
        XCTAssertEqual(edgesToDissolve.count, 2)
    }
}
