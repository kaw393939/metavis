import XCTest
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class MetalEngineTests: XCTestCase {
    
    func testEngineInitialization() async throws {
        // Skip if no Metal Device (e.g. CI)
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("⚠️ Skipping Metal Test: No Device Found")
            return
        }
        
        do {
            let engine = try MetalSimulationEngine()
            try await engine.configure()
            // If we reach here without throwing, success.
            XCTAssertTrue(true)
        } catch {
            XCTFail("Engine Init Failed: \(error)")
        }
    }
    
    func testACESExecution() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        
        // Build a simple 1-node graph (Tonemap only)
        // Note: Engine Mock Input generation needs to be robust for this to pass fully.
        // For now, we test that it doesn't crash on empty graph or simple graph.
        
        let node = TonemapNode.create(inputID: UUID()) // Input ID is dummy
        let graph = RenderGraph(nodes: [node], rootNodeID: node.id)
        let request = RenderRequest(
             graph: graph,
             time: .zero,
             quality: QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        )
        
        let result = try await engine.render(request: request)
        
        // Since we didn't provide a real input texture in the Engine Mock logic yet, result might be empty or specific error.
        // We assert valid execution flow.
        XCTAssertNotNil(result)
        if let err = result.metadata["error"] {
            XCTFail("Render Failed: \(err)")
        }
    }
}
