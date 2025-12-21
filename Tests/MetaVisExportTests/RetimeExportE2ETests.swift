import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisQC
import MetaVisSimulation

final class RetimeExportE2ETests: XCTestCase {

    private func smallDraft() -> QualityProfile {
        QualityProfile(name: "Draft 240p", fidelity: .draft, resolutionHeight: 240, colorDepth: 10)
    }

    func test_export_retimeChangesVideoFingerprint() async throws {
        DotEnvLoader.loadIfPresent()

        // Skip if ffmpeg isn't available (we generate a deterministic moving source clip).
        do {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["ffmpeg", "-version"]
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw XCTSkip("ffmpeg not available")
            }
        } catch {
            throw XCTSkip("ffmpeg not available")
        }

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let duration = Time(seconds: 2.0)

        // Source needs to be longer than the timeline when retimed faster.
        let sourceURL = TestOutputs.url(for: "retime_source_testsrc2", quality: "src_4s", ext: "mp4")
        do {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [
                "ffmpeg",
                "-y",
                "-f", "lavfi",
                "-i", "testsrc2=size=320x240:rate=24:duration=4",
                "-pix_fmt", "yuv420p",
                "-c:v", "libx264",
                "-crf", "18",
                "-preset", "ultrafast",
                sourceURL.path
            ]
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                throw XCTSkip("ffmpeg failed to generate testsrc2 fixture")
            }
        }

        func makeTimeline(retimeFactor: Double?) -> Timeline {
            var clip = Clip(
                name: "TestSrc2",
                asset: AssetReference(sourceFn: sourceURL.path),
                startTime: .zero,
                duration: duration
            )
            if let f = retimeFactor {
                clip.effects = [FeatureApplication(id: "mv.retime", parameters: ["factor": .float(f)])]
            }

            let track = Track(name: "V", kind: .video, clips: [clip])
            return Timeline(tracks: [track], duration: duration)
        }

        let outputA = TestOutputs.url(for: "e2e_retime_baseline", quality: "240p")
        let outputB = TestOutputs.url(for: "e2e_retime_factor_2x", quality: "240p")

        try await exporter.export(
            timeline: makeTimeline(retimeFactor: nil),
            to: outputA,
            quality: smallDraft(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        try await exporter.export(
            timeline: makeTimeline(retimeFactor: 2.0),
            to: outputB,
            quality: smallDraft(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        // Compare downsampled luma signatures; this is sensitive to retime changing
        // which source moment maps to a given output time.
        let samples: [VideoContentQC.Sample] = [
            .init(timeSeconds: 0.25, label: "t=0.25"),
            .init(timeSeconds: 0.50, label: "t=0.50"),
            .init(timeSeconds: 0.75, label: "t=0.75"),
            .init(timeSeconds: 1.00, label: "t=1.00"),
            .init(timeSeconds: 1.25, label: "t=1.25"),
            .init(timeSeconds: 1.50, label: "t=1.50")
        ]
        let sA = try await VideoContentQC.lumaSignatures(movieURL: outputA, samples: samples, dimension: 32)
        let sB = try await VideoContentQC.lumaSignatures(movieURL: outputB, samples: samples, dimension: 32)

        var maxMAD: Double = 0
        for i in 0..<samples.count {
            let a = try XCTUnwrap(sA[safe: i]?.1)
            let b = try XCTUnwrap(sB[safe: i]?.1)
            maxMAD = max(maxMAD, a.meanAbsDiff(to: b))
        }

        XCTAssertGreaterThan(
            maxMAD,
            0.75,
            "Expected retime to change frame content; max downsampled-luma MAD was too small: \(maxMAD)"
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
