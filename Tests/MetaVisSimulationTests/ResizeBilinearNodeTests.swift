import XCTest
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class ResizeBilinearNodeTests: XCTestCase {

    func testResizeBilinear_allowsMixedResolutionGraph() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let baseSize = RenderNode.OutputSpec(resolution: .fixed, fixedWidth: 256, fixedHeight: 256)
        let halfSize = RenderNode.OutputSpec(resolution: .fixed, fixedWidth: 128, fixedHeight: 128)

        let ramp = RenderNode(
            name: "Ramp",
            shader: "source_linear_ramp",
            output: baseSize
        )

        let down = RenderNode(
            name: "Down",
            shader: "resize_bilinear_rgba16f",
            inputs: ["input": ramp.id],
            output: halfSize
        )

        let up = RenderNode(
            name: "Up",
            shader: "resize_bilinear_rgba16f",
            inputs: ["input": down.id],
            output: baseSize
        )

        let graph = RenderGraph(nodes: [ramp, down, up], rootNodeID: up.id)

        let request = RenderRequest(
            graph: graph,
            time: .zero,
            quality: QualityProfile(name: "ResizeTest", fidelity: .high, resolutionHeight: 256, colorDepth: 32)
        )

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            XCTFail("Expected imageBuffer")
            return
        }

        XCTAssertEqual(data.count, 256 * 256 * 4 * 4, "Expected Float32 RGBA buffer")
        XCTAssertFalse(result.metadata.keys.contains("error"), "Should not return an error")
    }
}
