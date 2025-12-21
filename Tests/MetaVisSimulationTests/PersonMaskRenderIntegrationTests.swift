import XCTest
import MetaVisCore
import MetaVisSimulation

final class PersonMaskRenderIntegrationTests: XCTestCase {

    private func draftQuality() -> QualityProfile {
        QualityProfile(name: "Draft", fidelity: .draft, resolutionHeight: 144, colorDepth: 16)
    }

    func test_person_mask_drives_masked_grade_on_keith_talk() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let assetID = "keith_talk"
        let assetPath = "Tests/Assets/VideoEdit/keith_talk.mov"

        let src = RenderNode(
            name: "src",
            shader: "source_texture",
            parameters: [
                "asset_id": .string(assetID)
            ]
        )

        let mask = RenderNode(
            name: "personMask",
            shader: "source_person_mask",
            parameters: [
                "asset_id": .string(assetID),
                "kind": .string("foreground")
            ]
        )

        let grade = RenderNode(
            name: "bg_dim",
            shader: "fx_masked_grade",
            inputs: [
                "input": src.id,
                "mask": mask.id
            ],
            parameters: [
                "mode": .float(0.0),
                "invertMask": .float(1.0),
                "exposure": .float(-0.75),
                "saturation": .float(1.0),
                "softness": .float(0.0),
                "tolerance": .float(0.0),
                "hueShift": .float(0.0),
                "targetColor": .vector3(.init(0.0, 0.0, 0.0))
            ]
        )

        let graph = RenderGraph(nodes: [src, mask, grade], rootNodeID: grade.id)
        let baselineGraph = RenderGraph(nodes: [src], rootNodeID: src.id)

        let time = Time(seconds: 1.0)
        let quality = draftQuality()

        let req = RenderRequest(
            graph: graph,
            time: time,
            quality: quality,
            assets: [assetID: assetPath],
            renderFPS: 24.0
        )

        let baselineReq = RenderRequest(
            graph: baselineGraph,
            time: time,
            quality: quality,
            assets: [assetID: assetPath],
            renderFPS: 24.0
        )

        let out = try await engine.render(request: req)
        let base = try await engine.render(request: baselineReq)

        guard let outData = out.imageBuffer, let baseData = base.imageBuffer else {
            XCTFail("Missing image buffers")
            return
        }

        XCTAssertNotEqual(outData, baseData, "Masked grade output should differ from baseline")
    }
}
