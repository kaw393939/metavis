import XCTest
@testable import MetaVisCore

final class NodeGraphDebtTests: XCTestCase {
    
    func testDeepGraphCycleDetection() throws {
        // Create a graph with a long chain of nodes
        // A -> B -> C -> ... -> Z
        // Then try to connect Z -> A
        
        var graph = NodeGraph(name: "Deep Graph")
        
        let chainLength = 5000 // 5000 might be enough to blow the stack in debug mode
        var nodes: [Node] = []
        
        // Create nodes
        for i in 0..<chainLength {
            let node = Node(
                name: "Node \(i)",
                type: "test_node",
                inputs: [NodePort(id: "in", name: "In", type: .image)],
                outputs: [NodePort(id: "out", name: "Out", type: .image)]
            )
            nodes.append(node)
            graph.add(node: node)
        }
        
        // Connect them in a chain
        for i in 0..<(chainLength - 1) {
            try graph.connect(fromNode: nodes[i].id, fromPort: "out", toNode: nodes[i+1].id, toPort: "in")
        }
        
        // Now try to connect the last node to the first node to create a cycle
        // This triggers hasCycle() which runs DFS
        
        do {
            try graph.connect(fromNode: nodes.last!.id, fromPort: "out", toNode: nodes.first!.id, toPort: "in")
            XCTFail("Should have thrown cycleDetected error")
        } catch GraphError.cycleDetected {
            // Success
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
