import XCTest
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSimulation

final class TimelineCompilerPortMappingTests: XCTestCase {
    func test_timelineCompiler_mapsSourcePort_fromCurrentOutput() async throws {
        let clip = Clip(
            name: "Test",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [FeatureApplication(id: StandardFeatures.vignette.id)]
        )
        let track = Track(name: "V1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality)

        let fxNode = try XCTUnwrap(request.graph.nodes.first(where: { $0.shader == "fx_vignette_physical" }))
        let inputID = try XCTUnwrap(fxNode.inputs["input"])
        let upstream = try XCTUnwrap(request.graph.nodes.first(where: { $0.id == inputID }))

        // The compiler inserts an IDT in front of clip effects.
        XCTAssertTrue(upstream.shader.hasPrefix("idt_"))
    }

    func test_timelineCompiler_mapsInputPort_fromCurrentOutput() async throws {
        let manifest = FeatureManifest(
            id: "test.fx.input_only",
            version: "1.0.0",
            name: "Test Input Only",
            category: .utility,
            inputs: [PortDefinition(name: "input", type: .image)],
            parameters: [],
            kernelName: "test_kernel_input_only"
        )
        await FeatureRegistry.shared.register(manifest)

        let clip = Clip(
            name: "Test",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [FeatureApplication(id: manifest.id)]
        )
        let track = Track(name: "V1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality)

        let fxNode = try XCTUnwrap(request.graph.nodes.first(where: { $0.shader == "test_kernel_input_only" }))
        let inputID = try XCTUnwrap(fxNode.inputs["input"])
        let upstream = try XCTUnwrap(request.graph.nodes.first(where: { $0.id == inputID }))

        // The compiler inserts an IDT in front of clip effects.
        XCTAssertTrue(upstream.shader.hasPrefix("idt_"))
    }

    func test_timelineCompiler_insertsFaceMaskGenerator_forFaceMaskPort() async throws {
        let clip = Clip(
            name: "Test",
            asset: AssetReference(sourceFn: "ligm://source_test_color"),
            startTime: .zero,
            duration: Time(seconds: 1.0),
            effects: [FeatureApplication(id: StandardFeatures.faceEnhance.id)]
        )
        let track = Track(name: "V1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: Time(seconds: 1.0))

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)

        let ctx = RenderFrameContext(faceRectsByClipID: [
            clip.id: [SIMD4<Float>(0.25, 0.25, 0.5, 0.5)]
        ])

        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality, frameContext: ctx)

        let maskNode = try XCTUnwrap(request.graph.nodes.first(where: { $0.shader == "fx_generate_face_mask" }))
        let enhanceNode = try XCTUnwrap(request.graph.nodes.first(where: { $0.shader == "fx_face_enhance" }))

        XCTAssertEqual(enhanceNode.inputs["faceMask"], maskNode.id)
        XCTAssertNotNil(enhanceNode.inputs["source"], "Expected face enhance to bind primary input on 'source'")
    }
}
