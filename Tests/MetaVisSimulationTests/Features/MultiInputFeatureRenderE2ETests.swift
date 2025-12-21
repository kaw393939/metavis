import XCTest
import MetaVisCore
import MetaVisSimulation

final class MultiInputFeatureRenderE2ETests: XCTestCase {

    func testRenderGraphWithMultiInputFeaturePassRenders() async throws {
        // Build a small graph:
        // 1) source_test_color -> primary input
        // 2) fx_generate_face_mask -> mask (empty faceRects => deterministic empty mask)
        // 3) fx_face_enhance consumes input + faceMask

        let sourceNode = RenderNode(name: "Source", shader: "source_test_color")
        let maskNode = RenderNode(name: "Mask", shader: "fx_generate_face_mask")

        let manifest = FeatureManifest(
            id: "com.metavis.fx.face_enhance",
            version: "1.0.0",
            name: "Face Enhance",
            category: .utility,
            inputs: [
                PortDefinition(name: "source", type: .image),
                PortDefinition(name: "faceMask", type: .image)
            ],
            parameters: [],
            kernelName: "fx_face_enhance",
            passes: [
                FeaturePass(logicalName: "face_enhance", function: "fx_face_enhance", inputs: ["source", "faceMask"], output: "output")
            ]
        )

        let compiler = MultiPassFeatureCompiler()
        let compiled = try await compiler.compile(
            manifest: manifest,
            externalInputs: ["source": sourceNode.id, "faceMask": maskNode.id]
        )
        let fxNode = try XCTUnwrap(compiled.nodes.first)

        let graph = RenderGraph(nodes: [sourceNode, maskNode, fxNode], rootNodeID: fxNode.id)
        let quality = QualityProfile(name: "Draft", fidelity: .draft, resolutionHeight: 256, colorDepth: 10)
        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        XCTAssertNotNil(result.imageBuffer)
    }
}
