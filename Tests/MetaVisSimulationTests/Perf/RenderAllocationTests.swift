import XCTest
import MetaVisCore
import MetaVisSimulation

final class RenderAllocationTests: XCTestCase {

    private func draft256() -> QualityProfile {
        QualityProfile(name: "Draft 256", fidelity: .draft, resolutionHeight: 256, colorDepth: 16)
    }

    func test_multipass_has_no_steady_state_texture_allocations() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        // Simple multi-pass-ish graph: SMPTE -> blur_h -> blur_v
        let src = RenderNode(name: "SMPTE", shader: "fx_smpte_bars")
        let blurH = RenderNode(
            name: "BlurH",
            shader: "fx_blur_h",
            inputs: ["input": src.id],
            parameters: ["radius": .float(6)]
        )
        let blurV = RenderNode(
            name: "BlurV",
            shader: "fx_blur_v",
            inputs: ["input": blurH.id],
            parameters: ["radius": .float(6)]
        )

        let graph = RenderGraph(nodes: [src, blurH, blurV], rootNodeID: blurV.id)
        let request = RenderRequest(graph: graph, time: .zero, quality: draft256())

        // Warm up (populate pool buckets).
        _ = try await engine.render(request: request)
        _ = try await engine.render(request: request)

        MetalSimulationDiagnostics.reset()

        // Steady-state: should reuse pooled textures (no new allocations).
        for _ in 0..<5 {
            _ = try await engine.render(request: request)
        }

        XCTAssertEqual(
            MetalSimulationDiagnostics.textureAllocationCount,
            0,
            "Expected no steady-state texture allocations; got \(MetalSimulationDiagnostics.textureAllocationCount)"
        )
    }
}
