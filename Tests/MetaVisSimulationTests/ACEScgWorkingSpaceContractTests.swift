import XCTest
@testable import MetaVisSimulation
import MetaVisTimeline
import MetaVisCore

final class ACEScgWorkingSpaceContractTests: XCTestCase {

    func test_compiler_inserts_idt_and_odt_for_rec709_sources() async throws {
        let timeline = Timeline(
            tracks: [
                Track(
                    name: "Video",
                    kind: .video,
                    clips: [
                        Clip(
                            name: "Macbeth",
                            asset: AssetReference(sourceFn: "ligm://fx_macbeth"),
                            startTime: .zero,
                            duration: Time(seconds: 1.0)
                        )
                    ]
                )
            ],
            duration: Time(seconds: 1.0)
        )

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 256, colorDepth: 10)
        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality)

        let shaders = request.graph.nodes.map { $0.shader }

        XCTAssertTrue(shaders.contains("idt_rec709_to_acescg"), "Expected compiler to insert IDT for Rec.709 sources")
        XCTAssertEqual(shaders.filter { $0 == "odt_acescg_to_rec709" }.count, 1, "Expected exactly one ODT at display")

        let root = request.graph.nodes.first { $0.id == request.graph.rootNodeID }
        XCTAssertEqual(root?.shader, "odt_acescg_to_rec709", "Expected ODT to be graph root")
    }

    func test_exr_sources_use_linear_idt() async throws {
        // This is a compile-time contract test: the compiler should select the linear IDT
        // whenever the source is an EXR, regardless of whether the file exists on disk.
        let exr = FileManager.default.temporaryDirectory.appendingPathComponent("metavis_dummy.exr")

        let timeline = Timeline(
            tracks: [
                Track(
                    name: "Video",
                    kind: .video,
                    clips: [
                        Clip(
                            name: "EXR",
                            asset: AssetReference(sourceFn: exr.absoluteURL.absoluteString),
                            startTime: .zero,
                            duration: Time(seconds: 1.0 / 24.0)
                        )
                    ]
                )
            ],
            duration: Time(seconds: 1.0 / 24.0)
        )

        let compiler = TimelineCompiler()
        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 256, colorDepth: 10)
        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality)

        let shaders = request.graph.nodes.map { $0.shader }
        XCTAssertTrue(shaders.contains("idt_linear_rec709_to_acescg"), "Expected EXR sources to use linear IDT")
    }
}
