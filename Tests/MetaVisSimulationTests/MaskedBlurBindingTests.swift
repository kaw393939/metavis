import XCTest
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class MaskedBlurBindingTests: XCTestCase {
    func test_maskedBlur_passThroughWhenMaskIsZero() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let quality = QualityProfile(name: "MaskedBlur", fidelity: .draft, resolutionHeight: 64, colorDepth: 32)
        let time = Time(seconds: 0.0)

        func renderFloats(root: RenderNode, nodes: [RenderNode]) async throws -> [Float] {
            let request = RenderRequest(
                graph: RenderGraph(nodes: nodes, rootNodeID: root.id),
                time: time,
                quality: quality
            )

            let result = try await engine.render(request: request)
            guard let output = result.imageBuffer else {
                XCTFail("No output")
                return []
            }

            let width = 64
            let height = 64
            let expectedCount = width * height * 4
            let floats: [Float] = output.withUnsafeBytes { ptr in
                let base = ptr.bindMemory(to: Float.self)
                return Array(base.prefix(expectedCount))
            }
            XCTAssertEqual(floats.count, expectedCount)
            return floats
        }

        // Source reference.
        let source = RenderNode(name: "Source", shader: "source_test_color")
        let ref = try await renderFloats(root: source, nodes: [source])

        // Black mask.
        let mask = RenderNode(name: "Mask", shader: "clear_color")

        // Masked blur with threshold so a zero mask becomes pass-through.
        let maskedBlur = RenderNode(
            name: "MaskedBlur",
            shader: "fx_masked_blur",
            inputs: ["input": source.id, "mask": mask.id],
            parameters: [
                "radius": .float(12.0),
                "threshold": .float(1.0)
            ]
        )

        let got = try await renderFloats(root: maskedBlur, nodes: [source, mask, maskedBlur])

        let compare = ImageComparator.compare(bufferA: got, bufferB: ref, tolerance: 1e-4)
        switch compare {
        case .match:
            XCTAssertTrue(true)
        case .different(let maxDelta, let avgDelta):
            XCTFail("Masked blur did not pass-through as expected. max=\(maxDelta) avg=\(avgDelta)")
        }
    }
}
