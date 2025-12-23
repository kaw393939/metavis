import XCTest
import MetaVisCore
import MetaVisSimulation

final class RequireExplicitAdaptersEdgePolicyTests: XCTestCase {
    func testRequireExplicitAdapters_emitsWarningOnSizeMismatch() async throws {
        let engine = try MetalSimulationEngine(mode: .development)
        try await engine.configure()

        // Intentionally mismatch sizes without inserting a resize node.
        let src = RenderNode(name: "Ramp", shader: "source_linear_ramp")
        let half = RenderNode(
            name: "HalfBlur",
            shader: "fx_blur_h",
            inputs: ["input": src.id],
            parameters: ["radius": .float(0.0)],
            output: .init(resolution: .half)
        )
        let full = RenderNode(
            name: "IDT",
            shader: "idt_rec709_to_acescg",
            inputs: ["input": half.id]
        )

        let graph = RenderGraph(nodes: [src, half, full], rootNodeID: full.id)
        let quality = QualityProfile(name: "StrictEdges", fidelity: .draft, resolutionHeight: 256, colorDepth: 10)
        let request = RenderRequest(
            graph: graph,
            time: .zero,
            quality: quality,
            edgePolicy: .requireExplicitAdapters
        )

        let result = try await engine.render(request: request)
        XCTAssertNotNil(result.imageBuffer)

        let warnings = result.metadata["warnings"] ?? ""
        XCTAssertTrue(warnings.contains("size_mismatch"), "Expected size_mismatch warning, got: \(warnings)")
        XCTAssertFalse(warnings.contains("auto_resize"), "Did not expect auto_resize under requireExplicitAdapters")
    }
}
