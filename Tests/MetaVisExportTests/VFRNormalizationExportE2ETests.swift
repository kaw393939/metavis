import XCTest
import AVFoundation

import MetaVisCore
import MetaVisExport
import MetaVisIngest
import MetaVisSimulation
import MetaVisTimeline

/// Sprint 21: end-to-end export normalization contract.
///
/// Note: this test is gated on `ffmpeg` being available locally/CI.
final class VFRNormalizationExportE2ETests: XCTestCase {

    func test_export_normalizes_vfr_to_target_cfr_timebase() async throws {
        try requireTool("ffmpeg")

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("metavis_vfr_export_fixture_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let vfrURL = try generateVFRFixtureMP4(at: tmp)

        // Sanity check: fixture should be detected as VFR-likely.
        let inputProfile = try await VideoTimingProbe.probe(url: vfrURL)
        XCTAssertTrue(inputProfile.isVFRLikely, "Expected generated fixture to be detected as VFR-likely")

        // Export at a target CFR.
        let clipDuration = Time(seconds: 2.5)
        let timeline = Timeline(
            tracks: [
                Track(
                    name: "Video",
                    kind: .video,
                    clips: [
                        Clip(
                            name: "VFR Fixture",
                            asset: AssetReference(sourceFn: vfrURL.path),
                            startTime: .zero,
                            duration: clipDuration
                        )
                    ]
                )
            ],
            duration: clipDuration
        )

        let outURL = TestOutputs.url(for: "vfr_normalization_export", quality: "256p_8bit", ext: "mov")

        let targetFPS: Double = 30
        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 256, colorDepth: 8)
        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine, trace: NoOpTraceSink())

        let exportFPS: Int = 30

        try await exporter.export(
            timeline: timeline,
            to: outURL,
            quality: quality,
            frameRate: exportFPS,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        // Contract: output should look CFR to the probe.
        let outputProfile = try await VideoTimingProbe.probe(
            url: outURL,
            config: .init(sampleLimit: 240, minSamplesForDecision: 30)
        )

        XCTAssertFalse(outputProfile.isVFRLikely, "Expected exported deliverable to be CFR-like (not VFR-likely)")

        if let deltas = outputProfile.deltas {
            XCTAssertGreaterThanOrEqual(deltas.sampleCount, 30)
            XCTAssertLessThan(deltas.distinctDeltaCount, 3)
            XCTAssertLessThan(deltas.stdDevSeconds, 0.002)
        } else {
            XCTFail("Expected delta stats for exported deliverable")
        }

        if let estimated = outputProfile.estimatedFPS {
            XCTAssertEqual(estimated, targetFPS, accuracy: 1.0)
        }
    }

    private func generateVFRFixtureMP4(at tmp: URL) throws -> URL {
        let framesDir = tmp.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let f1 = framesDir.appendingPathComponent("f1.png")
        let f2 = framesDir.appendingPathComponent("f2.png")

        // Two deterministic stills.
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=red:s=320x180:r=60",
                "-frames:v", "1",
                f1.path
            ]
        )
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=320x180:r=60",
                "-frames:v", "1",
                f2.path
            ]
        )

        // Concat list with alternating durations to force VFR-like PTS deltas.
        let list = tmp.appendingPathComponent("list.txt")
        var listText = ""
        // 80 entries => 79 deltas (>= 30) and ~3.3s duration.
        for i in 0..<80 {
            let frameURL = (i % 2 == 0) ? f1 : f2
            let dur = (i % 2 == 0) ? 0.033 : 0.050
            listText += "file '\(frameURL.path)'\n"
            listText += String(format: "duration %.3f\n", dur)
        }
        listText += "file '\(f2.path)'\n"
        try listText.write(to: list, atomically: true, encoding: .utf8)

        let out = tmp.appendingPathComponent("vfr.mp4")
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "concat", "-safe", "0", "-i", list.path,
                "-vsync", "vfr",
                "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                out.path
            ]
        )
        return out
    }

    private func requireTool(_ name: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [name, "-version"]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw XCTSkip("\(name) not available")
        }
    }

    private func run(_ executablePath: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "MetaVisTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Command failed: \(args.joined(separator: " "))\n\(text)"]
            )
        }
    }
}
