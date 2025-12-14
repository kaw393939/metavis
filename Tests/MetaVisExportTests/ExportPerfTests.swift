import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisSimulation

final class ExportPerfTests: XCTestCase {

    private func perf360p() -> QualityProfile {
        QualityProfile(name: "Perf 360p", fidelity: .high, resolutionHeight: 360, colorDepth: 10)
    }

    func test_export_clip_budget_and_no_cpu_readback() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let exporter = VideoExporter(engine: engine)

        let duration = Time(seconds: 1.0)
        let timeline = Timeline(
            tracks: [
                Track(
                    name: "V",
                    kind: .video,
                    clips: [
                        Clip(
                            name: "SMPTE",
                            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
                            startTime: .zero,
                            duration: duration
                        )
                    ]
                )
            ],
            duration: duration
        )

        let outputURL = TestOutputs.url(for: "perf_export_short_clip", quality: "360p")

        MetalSimulationDiagnostics.reset()

        let clock = ContinuousClock()
        let start = clock.now
        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: perf360p(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )
        let elapsed = clock.now - start

        XCTAssertEqual(MetalSimulationDiagnostics.cpuReadbackCount, 0, "Export path should not require CPU readback")

        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetSeconds = Double(ProcessInfo.processInfo.environment["METAVIS_EXPORT_BUDGET_SECONDS"] ?? "") ?? (isCI ? 60.0 : 30.0)
        XCTAssertLessThanOrEqual(seconds, budgetSeconds, String(format: "Export %.2fs exceeded budget %.2fs", seconds, budgetSeconds))

        // Basic sanity: file exists and is non-empty.
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0)
    }
}
