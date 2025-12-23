import XCTest
import MetaVisCore
import MetaVisSimulation

final class AutoResizeEdgePolicyTests: XCTestCase {
    func testAutoResizePolicy_resizesMismatchedInputs() async throws {
        let engine = try MetalSimulationEngine(mode: .development)
        try await engine.configure()

        // Build a graph that intentionally introduces a size mismatch:
        // full-res source -> half-res blur -> full-res IDT.
        // The IDT kernel uses `source.read(gid)` and is unsafe when input is smaller than output
        // unless an adapter step is inserted.

        let src = RenderNode(
            name: "Ramp",
            shader: "source_linear_ramp"
        )

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
        let quality = QualityProfile(name: "AutoResize", fidelity: .draft, resolutionHeight: 256, colorDepth: 10)
        let request = RenderRequest(
            graph: graph,
            time: .zero,
            quality: quality,
            edgePolicy: .autoResizeBilinear
        )

        let result = try await engine.render(request: request)
        XCTAssertNotNil(result.imageBuffer)
        XCTAssertEqual(result.imageBuffer?.count, 256 * 256 * 4 * 4)

        // Verify that the engine reported a resize adapter step.
        let warnings = result.metadata["warnings"] ?? ""
        XCTAssertTrue(warnings.contains("auto_resize"), "Expected auto-resize warning, got: \(warnings)")
    }
}
