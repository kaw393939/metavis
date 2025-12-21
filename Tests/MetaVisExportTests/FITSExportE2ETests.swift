import XCTest
import AVFoundation
@testable import MetaVisExport
@testable import MetaVisSimulation
@testable import MetaVisTimeline
@testable import MetaVisCore
import MetaVisQC

final class FITSExportE2ETests: XCTestCase {

    func test_fitsTimelineTurbo_exportsProbeableMovie_andIsNotBlack() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fitsDir = root.appendingPathComponent("Tests").appendingPathComponent("Assets").appendingPathComponent("fits")

        guard FileManager.default.fileExists(atPath: fitsDir.path) else {
            throw XCTSkip("Missing test assets directory: \(fitsDir.path)")
        }

        let urls = try FileManager.default.contentsOfDirectory(at: fitsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "fits" || $0.pathExtension.lowercased() == "fit" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard urls.count >= 4 else {
            throw XCTSkip("Expected at least 4 FITS files in \(fitsDir.path), found \(urls.count)")
        }

        // Keep this test fast: 4 clips x 0.25s @ 24fps = ~24 frames.
        let secondsPerClip = 0.25
        let fps: Int = 24
        let totalSeconds = secondsPerClip * 4.0

        var clips: [Clip] = []
        clips.reserveCapacity(4)

        for (idx, url) in urls.prefix(4).enumerated() {
            let start = Double(idx) * secondsPerClip
            let fx: [FeatureApplication] = [
                .init(
                    id: "com.metavis.fx.false_color.turbo",
                    parameters: [
                        "exposure": .float(0.0),
                        "gamma": .float(1.0)
                    ]
                )
            ]

            clips.append(
                Clip(
                    name: String(format: "%02d_%@", idx, url.deletingPathExtension().lastPathComponent),
                    asset: AssetReference(sourceFn: url.absoluteURL.absoluteString),
                    startTime: Time(seconds: start),
                    duration: Time(seconds: secondsPerClip),
                    offset: .zero,
                    transitionIn: nil,
                    transitionOut: nil,
                    effects: fx
                )
            )
        }

        let timeline = Timeline(
            tracks: [Track(name: "FITS", kind: .video, clips: clips)],
            duration: Time(seconds: totalSeconds)
        )

        XCTAssertEqual(Set(clips.map { $0.asset.sourceFn }).count, 4, "Expected 4 distinct FITS assets in the timeline")

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let outputURL = TestOutputs.url(for: "fits_timeline_turbo", quality: "360p")
        let quality = QualityProfile(name: "FITS E2E", fidelity: .high, resolutionHeight: 360, colorDepth: 10)

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: quality,
            frameRate: fps,
            codec: AVVideoCodecType.hevc,
            audioPolicy: .forbidden
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "Export file should exist")

        let expectations = VideoQC.Expectations(
            minDurationSeconds: 0.85,
            maxDurationSeconds: 1.15,
            expectedWidth: 360 * 16 / 9,
            expectedHeight: 360,
            expectedNominalFrameRate: Double(fps),
            minVideoSampleCount: 20
        )

        _ = try await VideoQC.validateMovie(at: outputURL, expectations: expectations)

        // Not-black QC (tolerant): mean luma must be meaningfully above 0.
        _ = try await VideoContentQC.validateColorStats(
            movieURL: outputURL,
            samples: [
                .init(
                    timeSeconds: 0.10,
                    label: "clip0",
                    minMeanLuma: 0.02,
                    maxMeanLuma: 0.98,
                    maxChannelDelta: 1.0,
                    minLowLumaFraction: 0.0,
                    minHighLumaFraction: 0.0
                )
            ]
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        XCTAssertGreaterThan(fileSize, 50_000, "Export too small; likely missing samples. Got \(fileSize) bytes")
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
}
