import XCTest
import Metal
import MetaVisCore
@testable import MetaVisSimulation

final class MultiPassBlurRenderTests: XCTestCase {
    func test_multiPassBlur_matchesGoldenOrRecords() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        // Source: deterministic GPU test pattern (0-1 range)
        let sourceNode = RenderNode(
            name: "Source",
            shader: "source_test_color",
            inputs: [:],
            parameters: [:]
        )

        // Compile multi-pass blur feature into nodes
        let (blurNodes, blurRootID) = try await StandardFeatures.blurGaussian.compileNodes(
            externalInputs: ["source": sourceNode.id],
            parameterOverrides: ["radius": .float(8.0)]
        )

        let nodes = [sourceNode] + blurNodes
        let graph = RenderGraph(nodes: nodes, rootNodeID: blurRootID)
        let request = RenderRequest(
            graph: graph,
            time: .zero,
            quality: QualityProfile(name: "MultiPassBlur", fidelity: .draft, resolutionHeight: 256, colorDepth: 32)
        )

        let result = try await engine.render(request: request)
        guard let output = result.imageBuffer else {
            XCTFail("No output")
            return
        }

        let width = 256
        let height = 256
        let expectedCount = width * height * 4
        let floats: [Float] = output.withUnsafeBytes { ptr in
            let base = ptr.bindMemory(to: Float.self)
            return Array(base.prefix(expectedCount))
        }
        XCTAssertEqual(floats.count, expectedCount)

        let helper = SnapshotHelper()
        let goldenName = "Golden_MultiPass_BlurGaussian"

        if let golden = try helper.loadGolden(name: goldenName) {
            let compare = ImageComparator.compare(bufferA: floats, bufferB: golden)
            switch compare {
            case .match:
                XCTAssertTrue(true)
            case .different(let maxDelta, let avgDelta):
                if SnapshotHelper.shouldRecordGoldens {
                    let url = try helper.saveGolden(name: goldenName, buffer: floats, width: width, height: height)
                    print("Updated Golden: \(url.path)")
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    return
                } else {
                    XCTFail("Blur output differs from golden. max=\(maxDelta) avg=\(avgDelta) (set RECORD_GOLDENS=1 to update)")
                }
            }
        } else {
            if SnapshotHelper.shouldRecordGoldens {
                let url = try helper.saveGolden(name: goldenName, buffer: floats, width: width, height: height)
                print("Generated Golden: \(url.path)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                return
            } else {
                XCTFail("Missing golden \(goldenName).exr (re-run with RECORD_GOLDENS=1 to record)")
            }
        }
    }
}
