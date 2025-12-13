import XCTest
@testable import MetaVisSimulation

final class FeatureManifestCompilationTests: XCTestCase {
    func test_compileNodes_compiles_multi_pass_blur() async throws {
        let sourceID = UUID()
        let result = try await StandardFeatures.blurGaussian.compileNodes(externalInputs: ["source": sourceID])

        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertEqual(result.nodes.first?.shader, "fx_blur_h")
        XCTAssertEqual(result.nodes.last?.shader, "fx_blur_v")

        for node in result.nodes {
            guard case .float(let radius)? = node.parameters["radius"] else {
                XCTFail("Expected radius float parameter")
                return
            }
            XCTAssertEqual(radius, 10.0)
        }
    }
}
