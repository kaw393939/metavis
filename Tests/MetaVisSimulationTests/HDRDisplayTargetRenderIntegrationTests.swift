import XCTest
import Metal
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSimulation

final class HDRDisplayTargetRenderIntegrationTests: XCTestCase {

    func test_hdrPQ1000_displayTarget_renders_endToEnd() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Metal not available")
        }

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
        let quality = QualityProfile(name: "HDR", fidelity: .draft, resolutionHeight: 256, colorDepth: 16)
        let request = try await compiler.compile(
            timeline: timeline,
            at: .zero,
            quality: quality,
            displayTarget: .hdrPQ1000
        )

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let result = try await engine.render(request: request)
        guard let output = result.imageBuffer else {
            XCTFail("Expected output buffer")
            return
        }

        // Sanity: data exists and is non-trivial. (We do not assert correctness here; Sprint 24k validators will.)
        XCTAssertGreaterThan(output.count, 0)

        // Draft mode uses 256x256 for deterministic verification.
        let width = 256
        let height = 256
        let expectedCount = width * height * 4
        let floats: [Float] = output.withUnsafeBytes { ptr in
            let base = ptr.bindMemory(to: Float.self)
            return Array(base.prefix(expectedCount))
        }
        XCTAssertEqual(floats.count, expectedCount)

        // PQ values should typically lie in [0,1]. Allow slight overshoot due to FP precision.
        let minV = floats.min() ?? 0
        let maxV = floats.max() ?? 0
        XCTAssertGreaterThanOrEqual(minV, -0.001)
        XCTAssertLessThanOrEqual(maxV, 1.001)
        XCTAssertGreaterThan(maxV - minV, 0.01, "Expected non-trivial HDR output range")
    }
}
