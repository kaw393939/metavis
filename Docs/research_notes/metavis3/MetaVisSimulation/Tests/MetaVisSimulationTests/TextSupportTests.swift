import XCTest
import MetaVisCore
import Metal
@testable import MetaVisSimulation

final class TextSupportTests: XCTestCase {
    
    var device: MTLDevice!
    var compiler: GraphCompiler!
    
    override func setUp() {
        super.setUp()
        guard let d = MTLCreateSystemDefaultDevice() else {
            try? XCTSkipIf(true, "No Metal Device available")
            return
        }
        device = d
        compiler = GraphCompiler(device: device)
    }
    
    func testTextNodeDefinition() {
        XCTAssertEqual(NodeType.text, "com.metavis.source.text")
        XCTAssertEqual(NodeType.generator, "com.metavis.source.generator")
    }
    
    func testCompilerHandlesTextNode() throws {
        // 1. Create Graph with Text Node
        var graph = NodeGraph(name: "Text Test Graph")
        let outputNode = Node(name: "Output", type: NodeType.output, inputs: [NodePort(id: "input", name: "Input", type: .image)])
        graph.add(node: outputNode)
        
        let textNode = Node(
            name: "Hello World",
            type: NodeType.text,
            properties: [
                "text": .string("Hello Metal"),
                "font": .string("Helvetica"),
                "size": .float(64.0)
            ],
            outputs: [NodePort(id: "output", name: "Output", type: .image)]
        )
        graph.add(node: textNode)
        
        try graph.connect(fromNode: textNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
        
        // 2. Compile
        let pass = try compiler.compile(graph: graph)
        
        // 3. Verify Commands
        guard let firstCommand = pass.commands.first else {
            XCTFail("No commands generated")
            return
        }
        
        if case .generateText(let nodeId, let text, let font, let size) = firstCommand {
            XCTAssertEqual(nodeId, textNode.id)
            XCTAssertEqual(text, "Hello Metal")
            XCTAssertEqual(font, "Helvetica")
            XCTAssertEqual(size, 64.0)
        } else {
            XCTFail("Expected generateText command, got \(firstCommand)")
        }
    }
    
    func testEngineRendersTextNode() async throws {
        // 1. Setup Engine
        let clock = MasterClock()
        let engine = try SimulationEngine(clock: clock)
        
        // 2. Create Graph
        var graph = NodeGraph(name: "Text Render Test")
        let outputNode = Node(name: "Output", type: NodeType.output, inputs: [NodePort(id: "input", name: "Input", type: .image)])
        graph.add(node: outputNode)
        
        let textNode = Node(
            name: "Render Me",
            type: NodeType.text,
            properties: [
                "text": .string("Render Test"),
                "font": .string("Helvetica"),
                "size": .float(48.0)
            ],
            outputs: [NodePort(id: "output", name: "Output", type: .image)]
        )
        graph.add(node: textNode)
        
        try graph.connect(fromNode: textNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
        
        // 3. Compile
        let pass = try compiler.compile(graph: graph)
        
        // 4. Render
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 512, height: 512, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        guard let outputTexture = device.makeTexture(descriptor: desc) else {
            XCTFail("Failed to create output texture")
            return
        }
        
        do {
            try await engine.render(pass: pass, outputTexture: outputTexture)
            // If we get here without throwing, success!
            // Ideally we'd check pixels, but that's complex for unit tests.
        } catch {
            XCTFail("Render failed: \(error)")
        }
    }
    
    func testCompilerHandlesGeneratorNode() throws {
        var graph = NodeGraph(name: "Generator Test")
        let outputNode = Node(name: "Output", type: NodeType.output, inputs: [NodePort(id: "input", name: "Input", type: .image)])
        graph.add(node: outputNode)
        
        let genNode = Node(
            name: "Checkerboard",
            type: NodeType.generator,
            properties: [
                "type": .string("checkerboard"),
                "scale": .float(10.0)
            ],
            outputs: [NodePort(id: "output", name: "Output", type: .image)]
        )
        graph.add(node: genNode)
        
        try graph.connect(fromNode: genNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
        
        let pass = try compiler.compile(graph: graph)
        
        guard let firstCommand = pass.commands.first else {
            XCTFail("No commands")
            return
        }
        
        if case .process(let nodeId, let kernel, let inputs, let params) = firstCommand {
            XCTAssertEqual(nodeId, genNode.id)
            XCTAssertEqual(kernel, "checkerboard")
            XCTAssertTrue(inputs.isEmpty)
            XCTAssertEqual(params["scale"]?.floatValue, 10.0)
        } else {
            XCTFail("Expected process command for generator")
        }
    }
}
