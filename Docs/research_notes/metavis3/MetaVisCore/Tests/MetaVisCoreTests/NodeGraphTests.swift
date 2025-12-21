import XCTest
@testable import MetaVisCore

final class NodeGraphTests: XCTestCase {
    
    // MARK: - Phase 1: Basic Structure
    
    func testNodeCreation() {
        // 1. Define a node
        let nodeId = UUID()
        let node = Node(
            id: nodeId,
            name: "Camera Input",
            type: "com.metavis.source",
            position: SIMD2<Float>(0, 0),
            inputs: [
                NodePort(id: "in_trigger", name: "Trigger", type: .event)
            ],
            outputs: [
                NodePort(id: "out_video", name: "Video", type: .image)
            ]
        )
        
        // 2. Verify properties
        XCTAssertEqual(node.id, nodeId)
        XCTAssertEqual(node.type, "com.metavis.source")
        XCTAssertEqual(node.name, "Camera Input")
        XCTAssertEqual(node.inputs.count, 1)
        XCTAssertEqual(node.outputs.count, 1)
    }
    
    func testGraphAddNode() {
        // 1. Create a graph
        var graph = NodeGraph(name: "Main Sequence")
        
        // 2. Create and add a node
        let node = Node(name: "Blur Effect", type: "com.metavis.blur")
        graph.add(node: node)
        
        // 3. Verify lookup
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertNotNil(graph.nodes[node.id])
        XCTAssertEqual(graph.nodes[node.id]?.name, "Blur Effect")
    }
    
    func testGraphRemoveNode() {
        // 1. Setup graph with node
        var graph = NodeGraph()
        let node = Node(name: "Test Node", type: "com.metavis.test")
        graph.add(node: node)
        
        // 2. Remove it
        graph.remove(nodeId: node.id)
        
        // 3. Verify removal
        XCTAssertEqual(graph.nodes.count, 0)
        XCTAssertNil(graph.nodes[node.id])
    }
    
    func testGraphConnectNodes() throws {
        // 1. Setup graph with two nodes
        var graph = NodeGraph()
        let source = Node(
            name: "Source", 
            type: "com.metavis.source",
            outputs: [NodePort(id: "out", name: "Out", type: .image)]
        )
        let effect = Node(
            name: "Effect", 
            type: "com.metavis.effect",
            inputs: [NodePort(id: "in", name: "In", type: .image)]
        )
        
        graph.add(node: source)
        graph.add(node: effect)
        
        // 2. Connect them
        try graph.connect(
            fromNode: source.id,
            fromPort: "out",
            toNode: effect.id,
            toPort: "in"
        )
        
        // 3. Verify edge creation
        XCTAssertEqual(graph.edges.count, 1)
        let edge = graph.edges.first
        XCTAssertEqual(edge?.fromNode, source.id)
        XCTAssertEqual(edge?.toNode, effect.id)
    }
    
    func testGraphConnectInvalidNodes() {
        // 1. Setup graph with one node
        var graph = NodeGraph()
        let source = Node(
            name: "Source", 
            type: "com.metavis.source",
            outputs: [NodePort(id: "out", name: "Out", type: .image)]
        )
        graph.add(node: source)
        
        // 2. Try to connect to non-existent node
        XCTAssertThrowsError(try graph.connect(
            fromNode: source.id,
            fromPort: "out",
            toNode: UUID(), // Random UUID not in graph
            toPort: "in"
        )) { error in
            guard let graphError = error as? GraphError else {
                XCTFail("Expected GraphError")
                return
            }
            // case nodeNotFound(UUID)
        }
        
        // 3. Verify no edge created
        XCTAssertEqual(graph.edges.count, 0)
    }
    
    func testCycleDetection() throws {
        // A -> B -> C -> A
        var graph = NodeGraph()
        let nodeA = Node(
            name: "A", 
            type: "test",
            inputs: [NodePort(id: "in", name: "In", type: .image)],
            outputs: [NodePort(id: "out", name: "Out", type: .image)]
        )
        let nodeB = Node(
            name: "B", 
            type: "test",
            inputs: [NodePort(id: "in", name: "In", type: .image)],
            outputs: [NodePort(id: "out", name: "Out", type: .image)]
        )
        let nodeC = Node(
            name: "C", 
            type: "test",
            inputs: [NodePort(id: "in", name: "In", type: .image)],
            outputs: [NodePort(id: "out", name: "Out", type: .image)]
        )
        
        graph.add(node: nodeA)
        graph.add(node: nodeB)
        graph.add(node: nodeC)
        
        try graph.connect(fromNode: nodeA.id, fromPort: "out", toNode: nodeB.id, toPort: "in")
        try graph.connect(fromNode: nodeB.id, fromPort: "out", toNode: nodeC.id, toPort: "in")
        
        // This should fail
        XCTAssertThrowsError(try graph.connect(fromNode: nodeC.id, fromPort: "out", toNode: nodeA.id, toPort: "in")) { error in
            XCTAssertEqual(error as? GraphError, GraphError.cycleDetected)
        }
        
        // Verify edge was not added
        XCTAssertEqual(graph.edges.count, 2)
    }
    
    func testSelfConnection() {
        var graph = NodeGraph()
        let nodeA = Node(name: "A", type: "test")
        graph.add(node: nodeA)
        
        XCTAssertThrowsError(try graph.connect(fromNode: nodeA.id, fromPort: "out", toNode: nodeA.id, toPort: "in")) { error in
            XCTAssertEqual(error as? GraphError, GraphError.selfConnection)
        }
    }
    
    func testPortTypeValidation() {
        var graph = NodeGraph()
        
        let audioNode = Node(
            name: "Audio Source",
            type: "source",
            outputs: [NodePort(id: "out_audio", name: "Audio", type: .audio)]
        )
        
        let videoNode = Node(
            name: "Video Effect",
            type: "effect",
            inputs: [NodePort(id: "in_video", name: "Video", type: .image)]
        )
        
        graph.add(node: audioNode)
        graph.add(node: videoNode)
        
        // Try connecting Audio -> Image
        XCTAssertThrowsError(try graph.connect(
            fromNode: audioNode.id,
            fromPort: "out_audio",
            toNode: videoNode.id,
            toPort: "in_video"
        )) { error in
            XCTAssertEqual(error as? GraphError, GraphError.portTypeMismatch(from: .audio, to: .image))
        }
    }
}
