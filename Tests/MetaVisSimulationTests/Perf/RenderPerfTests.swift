import XCTest
import CoreVideo
import MetaVisCore
import MetaVisSimulation

final class RenderPerfTests: XCTestCase {

    private func perf360p() -> QualityProfile {
        QualityProfile(name: "Perf 360p", fidelity: .high, resolutionHeight: 360, colorDepth: 10)
    }

    func test_render_frame_budget() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let src = RenderNode(name: "SMPTE", shader: "fx_smpte_bars")
        let graph = RenderGraph(nodes: [src], rootNodeID: src.id)

        let quality = perf360p()
        let width = quality.resolutionHeight * 16 / 9
        let height = quality.resolutionHeight

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_64RGBAHalf,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_64RGBAHalf, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            throw XCTSkip("Failed to create CVPixelBuffer (status=\(status))")
        }

        let request = RenderRequest(graph: graph, time: .zero, quality: quality)

        // Warm up pipelines + pool.
        try await engine.render(request: request, to: pb)
        try await engine.render(request: request, to: pb)

        let frames = 12
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<frames {
            let t = Time(seconds: Double(i) / 24.0)
            let req = RenderRequest(graph: graph, time: t, quality: quality)
            try await engine.render(request: req, to: pb)
        }
        let elapsed = clock.now - start
        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        let avgMs = (seconds / Double(frames)) * 1000.0

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_RENDER_FRAME_BUDGET_MS"] ?? "") ?? (isCI ? 800.0 : 400.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg render %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }
}
