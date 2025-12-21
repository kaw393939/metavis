import Testing
@testable import MetaVisSimulation
import MetaVisCore
import Metal

@Test func testGraphCompiler_SimpleGraph() async throws {
    // 1. Setup
    guard let device = MTLCreateSystemDefaultDevice() else {
        // Skip if no Metal device (e.g. CI)
        return
    }
    let compiler = GraphCompiler(device: device)
    
    // 2. Create Graph
    var graph = NodeGraph(name: "Test Graph")
    let assetId = UUID()
    let sourceNode = Node(
        name: "Source", 
        type: NodeType.source,
        properties: ["assetId": .string(assetId.uuidString)],
        outputs: [NodePort(id: "output", name: "Output", type: .image)]
    )
    let outputNode = Node(
        name: "Output", 
        type: NodeType.output,
        inputs: [NodePort(id: "input", name: "Input", type: .image)]
    )
    
    graph.add(node: sourceNode)
    graph.add(node: outputNode)
    
    // Connect Source -> Output
    try graph.connect(fromNode: sourceNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
    
    // 3. Compile
    let pass = try compiler.compile(graph: graph)
    
    // 4. Verify
    #expect(!pass.commands.isEmpty)
    // We expect load and present
    let hasLoad = pass.commands.contains { if case .loadTexture = $0 { return true }; return false }
    let hasPresent = pass.commands.contains { if case .present = $0 { return true }; return false }
    
    #expect(hasLoad)
    #expect(hasPresent)
}

@Test func testGraphCompiler_EmptyGraph() async throws {
    guard let device = MTLCreateSystemDefaultDevice() else { return }
    let compiler = GraphCompiler(device: device)
    let graph = NodeGraph(name: "Empty")
    
    let pass = try compiler.compile(graph: graph)
    #expect(pass.commands.isEmpty)
}
