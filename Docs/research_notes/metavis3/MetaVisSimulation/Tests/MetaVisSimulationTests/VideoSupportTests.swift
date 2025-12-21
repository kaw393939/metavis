import XCTest
import MetaVisCore
import Metal
@testable import MetaVisSimulation

final class VideoSupportTests: XCTestCase {
    
    var device: MTLDevice!
    var compiler: GraphCompiler!
    
    override func setUp() {
        super.setUp()
        // Skip if no Metal device (CI environment)
        guard let d = MTLCreateSystemDefaultDevice() else {
            try? XCTSkipIf(true, "No Metal Device available")
            return
        }
        device = d
        compiler = GraphCompiler(device: device)
    }
    
    func testVideoNodeDefinition() {
        XCTAssertEqual(NodeType.videoSource, "com.metavis.source.video")
    }
    
    func testCompilerHandlesVideoNode() throws {
        // 1. Create Graph with Video Node
        var graph = NodeGraph(name: "Video Test Graph")
        let outputNode = Node(name: "Output", type: NodeType.output, inputs: [NodePort(id: "input", name: "Input", type: .image)])
        graph.add(node: outputNode)
        
        let videoId = UUID()
        let videoNode = Node(
            name: "My Video",
            type: NodeType.videoSource,
            properties: ["assetId": .string(videoId.uuidString)],
            outputs: [NodePort(id: "output", name: "Output", type: .image)]
        )
        graph.add(node: videoNode)
        
        try graph.connect(fromNode: videoNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
        
        // 2. Compile
        let pass = try compiler.compile(graph: graph)
        
        // 3. Verify Commands
        // Should have a loadTexture command, but we need to verify it's marked as video or handled correctly.
        // For now, let's assume the compiler treats it similar to a source but maybe with a different command or metadata?
        // In the spec, we decided to update RenderCommand.loadTexture to include source type.
        
        guard let firstCommand = pass.commands.first else {
            XCTFail("No commands generated")
            return
        }
        
        if case .loadTexture(let nodeId, let assetId, let isVideo, _, _) = firstCommand {
            XCTAssertEqual(nodeId, videoNode.id)
            XCTAssertEqual(assetId, videoId)
            XCTAssertTrue(isVideo, "Should be marked as video source")
        } else {
            XCTFail("Expected loadTexture command, got \(firstCommand)")
        }
    }
    
    func testVideoProviderRegistration() {
        let provider = VideoFrameProvider(device: device)
        let assetId = UUID()
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        
        provider.register(assetId: assetId, url: url)
        
        // Since we can't inspect private properties, we just verify it doesn't crash.
        // In a real test, we might check if asking for a texture returns nil (since file doesn't exist)
        // but doesn't throw.
        
        let texture = provider.texture(for: assetId, at: .zero)
        XCTAssertNil(texture, "Should return nil for non-existent video file")
    }
}
