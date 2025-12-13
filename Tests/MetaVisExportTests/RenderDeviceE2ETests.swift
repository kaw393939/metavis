import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

final class RenderDeviceE2ETests: XCTestCase {

    func testExportViaDeviceCatalog() async throws {
        DotEnvLoader.loadIfPresent()

        // Timeline: deterministic procedural video+audio
        var timeline = GodTestBuilder.build()
        timeline.duration = Time(seconds: 2.0)

        // Device selection
        let engine = try MetalSimulationEngine()
        try await engine.configure()

        let catalog = RenderDeviceCatalog()
        let device = catalog.makeDevice(kind: .metalLocal, engine: engine)

        let exporter = VideoExporter(device: device)

        let outputURL = TestOutputs.url(for: "device_catalog_export", quality: "4K_10bit")
        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160,
            colorDepth: 10
        )

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: 24,
            codec: AVVideoCodecType.hevc,
            audioPolicy: .auto
        )

        _ = try await VideoQC.validateMovie(
            at: outputURL,
            expectations: .hevc4K24fps(durationSeconds: 2.0)
        )

        // Ensure audio path remains intact for device-based export.
        try await VideoQC.assertHasAudioTrack(at: outputURL)
        try await VideoQC.assertAudioNotSilent(at: outputURL)
    }
}
