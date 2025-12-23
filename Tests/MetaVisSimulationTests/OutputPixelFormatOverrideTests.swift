import XCTest
import MetaVisCore
import MetaVisSimulation

final class OutputPixelFormatOverrideTests: XCTestCase {
    func testRenderRequest_readbackOverridesNonFloatOutputFormat() async throws {
        let engine = try MetalSimulationEngine(mode: .development)
        try await engine.configure()

        let node = RenderNode(
            name: "SMPTE",
            shader: "fx_smpte_bars",
            output: .init(resolution: .full, pixelFormat: .bgra8Unorm)
        )
        let graph = RenderGraph(nodes: [node], rootNodeID: node.id)
        let quality = QualityProfile(name: "FmtOverride", fidelity: .draft, resolutionHeight: 256, colorDepth: 10)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let result = try await engine.render(request: request)
        XCTAssertNotNil(result.imageBuffer)
        XCTAssertEqual(result.imageBuffer?.count, 256 * 256 * 4 * 4)

        let warnings = result.metadata["warnings"] ?? ""
        XCTAssertTrue(warnings.contains("output_format_override"), "Expected override warning, got: \(warnings)")
    }
}
