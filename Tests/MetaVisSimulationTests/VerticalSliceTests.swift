import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSimulation

final class VerticalSliceTests: XCTestCase {
    
    func testGoldenThreadCompilation() async throws {
        // 1. Setup Input (Timeline)
        // Create a Timeline with 1 Track and 1 Clip
        let assetRef = AssetReference(id: UUID(), sourceFn: "test_asset_1.png")
        let clip = Clip(id: UUID(), name: "Clip 1", asset: assetRef, startTime: .zero, duration: Time(seconds: 5))
        let track = Track(id: UUID(), name: "V1", clips: [clip])
        let timeline = Timeline(tracks: [track])
        
        // 2. Setup Compiler
        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 1080, colorDepth: 8)
        
        // 3. Compile (The Action)
        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality)
        
        // 4. Verify Output (RenderGraph)
        XCTAssertFalse(request.graph.nodes.isEmpty, "Graph should not be empty")
        
        // Use standard array functions instead of containment for easier debugging
        let nodeShaders = request.graph.nodes.map { $0.shader }
        
        // Check for ACEScg Enforcement
        XCTAssertTrue(nodeShaders.contains("idt_rec709_to_acescg"), "Graph MUST contain Input Device Transform")
        XCTAssertTrue(nodeShaders.contains("odt_acescg_to_rec709"), "Graph MUST contain Output Device Transform")
        XCTAssertTrue(nodeShaders.contains("source_texture"), "Graph MUST contain Source Node")
        
        // 5. Test Color Adjust (Manual Node Injection for Test)
        // In a real scenario, the Compiler would insert this based on Track Effects.
        // Here we just verify the Node Factory works.
        let exposureNode = ExposureNode.create(inputID: UUID(), ev: 1.0)
        XCTAssertEqual(exposureNode.shader, "exposure_adjust")
        if case .float(let val) = exposureNode.parameters["ev"] {
             XCTAssertEqual(val, 1.0)
        } else {
             XCTFail("Exposure parameter missing or wrong type")
        }
        
        // Check Linking
        // The Root Node should be the ODT
        let rootNode = request.graph.nodes.first { $0.id == request.graph.rootNodeID }
        XCTAssertNotNil(rootNode)
        XCTAssertEqual(rootNode?.shader, "odt_acescg_to_rec709")
    }
}
