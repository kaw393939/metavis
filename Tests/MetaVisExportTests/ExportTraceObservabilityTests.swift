import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisExport
import MetaVisSimulation

final class ExportTraceObservabilityTests: XCTestCase {

    func testExporterEmitsRenderCompileAndDispatchTrace() async throws {
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let trace = InMemoryTraceSink()
        let exporter = VideoExporter(engine: engine, trace: trace)

        // Use the same baseline as other E2E exports to avoid exercising untested
        // shader/resource combinations (Metal can assert on mismatched mips).
        var timeline = GodTestBuilder.build()
        timeline.duration = Time(seconds: 2.0) // 48 frames @ 24fps

        let outputURL = TestOutputs.url(for: "trace_export", quality: "4K_10bit")
        let quality = QualityProfile(name: "Master 4K", fidelity: .master, resolutionHeight: 2160, colorDepth: 10)

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .auto,
            governance: .none
        )

        let events = await trace.snapshot()
        let names = events.map { $0.name }

        XCTAssertTrue(names.contains("export.begin"))
        XCTAssertTrue(names.contains("render.video.begin"))
        XCTAssertTrue(names.contains("render.compile.begin"))
        XCTAssertTrue(names.contains("render.compile.end"))
        XCTAssertTrue(names.contains("render.dispatch.begin"))
        XCTAssertTrue(names.contains("render.dispatch.end"))
        XCTAssertTrue(names.contains("render.video.end"))
        XCTAssertTrue(names.contains("export.end"))

        XCTAssertLessThan(names.firstIndex(of: "export.begin") ?? Int.max,
                         names.firstIndex(of: "export.end") ?? Int.min)
    }
}
