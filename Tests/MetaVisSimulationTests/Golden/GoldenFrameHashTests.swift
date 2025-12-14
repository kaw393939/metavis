import XCTest
import MetaVisCore
import MetaVisSimulation

final class GoldenFrameHashTests: XCTestCase {

    private func draft256() -> QualityProfile {
        QualityProfile(name: "Draft 256", fidelity: .draft, resolutionHeight: 256, colorDepth: 16)
    }

    private func renderSingleNode(shader: String, timeSeconds: Double = 0) async throws -> (hash: String, width: Int, height: Int) {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let node = RenderNode(
            name: "Golden_\(shader)",
            shader: shader,
            parameters: shader == "fx_zone_plate" ? ["time": .float(timeSeconds)] : [:]
        )
        let graph = RenderGraph(nodes: [node], rootNodeID: node.id)

        let request = RenderRequest(
            graph: graph,
            time: Time(seconds: timeSeconds),
            quality: draft256(),
            assets: [:]
        )

        let result = try await engine.render(request: request)
        guard let data = result.imageBuffer else {
            throw XCTSkip("No imageBuffer produced: \(result.metadata)")
        }

        let width = 256
        let height = 256
        let hash = FrameHashing.sha256DownsampledRGBA8Hex(
            floatRGBAData: data,
            width: width,
            height: height,
            downsampleTo: 64
        )
        return (hash, width, height)
    }

    func test_smpte_frame_hash() async throws {
        let got = try await renderSingleNode(shader: "fx_smpte_bars")
        let expected = "538a74dc4ac42a1f316f55aeeccaddc98f19c0d1d19e755cb04e713cbbb9a895"
        XCTAssertEqual(got.hash, expected, "Update expected hash to: \(got.hash)")
    }

    func test_zone_plate_hash() async throws {
        let got = try await renderSingleNode(shader: "fx_zone_plate", timeSeconds: 0)
        let expected = "20c7c53ebd28e9b805a4ef82b5d5ee2c04930e4cba0de8d197d857016d8e3850"
        XCTAssertEqual(got.hash, expected, "Update expected hash to: \(got.hash)")
    }
}
