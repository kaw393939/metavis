import XCTest
@testable import MetaVisSimulation
@testable import MetaVisCore

final class MultiPassFeatureCompilerTests: XCTestCase {
    func test_compiles_multi_pass_feature_into_multiple_nodes() async throws {
        let manifest = FeatureManifest(
            id: "blurGaussian",
            version: "1.0.0",
            name: "Gaussian Blur",
            category: .blur,
            inputs: [PortDefinition(name: "source", type: .image)],
            parameters: [ParameterDefinition.float(name: "radius", min: 0, max: 64, default: 4)],
            kernelName: "fx_blur_v",
            passes: [
                FeaturePass(logicalName: "blur_h", function: "fx_blur_h", inputs: ["source"], output: "tmp"),
                FeaturePass(logicalName: "blur_v", function: "fx_blur_v", inputs: ["tmp"], output: "output")
            ]
        )

        let compiler = MultiPassFeatureCompiler()
        let sourceNodeID = UUID()
        let result = try await compiler.compile(manifest: manifest, externalInputs: ["source": sourceNodeID])
        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.nodes.first?.shader, "fx_blur_h")
        XCTAssertEqual(result.nodes.last?.shader, "fx_blur_v")
        XCTAssertEqual(result.rootNodeID, result.nodes.last?.id)
    }
}
