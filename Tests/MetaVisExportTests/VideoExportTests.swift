import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisExport
import MetaVisSimulation
import MetaVisQC

final class VideoExportTests: XCTestCase {
    
    func testGodTestExport() async throws {
        // 1. Setup Engine
        logDebug("🛠 [Test] Initializing Engine...")
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        logDebug("✅ [Test] Engine Configured.")
        
        let exporter = VideoExporter(engine: engine)
        
        // 2. Build Timeline (God Test)
        var timeline = GodTestBuilder.build()
        timeline.duration = Time(seconds: 2.0) // 48 frames @ 24fps
        
        // 3. Output Path
        // Setup export with centralized output location
        let outputURL = TestOutputs.url(for: "god_test", quality: "4K_10bit")
        
        // 4. Quality Profile (4K 10-Bit)
        let quality = QualityProfile(
            name: "Master 4K",
            fidelity: .master,
            resolutionHeight: 2160, // 3840x2160
            colorDepth: 10
        )
        
        logDebug("🎬 Exporting to: \(outputURL.path)")
        
        // 5. Run Export
        let start = Date()
        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: 24, // Cinema Standard
            codec: .hevc // Modern 10-bit codec
        )
        let duration = Date().timeIntervalSince(start)
        logDebug("✅ Export Finished in \(duration)s")

        // 6. Deterministic QC (avoid fragile size-based assertions)
        _ = try await VideoQC.validateMovie(
            at: outputURL,
            expectations: .hevc4K24fps(durationSeconds: 2.0)
        )
    }
    
    private func logDebug(_ msg: String) {
        let str = "\(Date()): \(msg)\n"
        if let data = str.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/metavis_debug.log")) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? str.write(to: URL(fileURLWithPath: "/tmp/metavis_debug.log"), atomically: true, encoding: .utf8)
            }
        }
    }
}
