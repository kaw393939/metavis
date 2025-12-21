import XCTest
import AVFoundation
import MetaVisCore
import MetaVisTimeline
import MetaVisExport
import MetaVisQC
import MetaVisSimulation

final class TransitionDipWipeE2ETests: XCTestCase {

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

    private func draft360p() -> QualityProfile {
        QualityProfile(name: "Draft 360p", fidelity: .draft, resolutionHeight: 360, colorDepth: 10)
    }

    private func expectations(height: Int, durationSeconds: Double, fps: Double) -> VideoQC.Expectations {
        let tol = max(0.10, min(0.50, durationSeconds * 0.02))
        let expectedFrames = Int((durationSeconds * fps).rounded())
        return VideoQC.Expectations(
            minDurationSeconds: durationSeconds - tol,
            maxDurationSeconds: durationSeconds + tol,
            expectedWidth: height * 16 / 9,
            expectedHeight: height,
            expectedNominalFrameRate: fps,
            minVideoSampleCount: max(1, Int(Double(expectedFrames) * 0.80))
        )
    }

    private func genAIInputs() throws -> (a: URL, b: URL) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dir = root.appendingPathComponent("Tests").appendingPathComponent("Assets").appendingPathComponent("genai")
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw XCTSkip("Missing test assets directory: \(dir.path)")
        }

        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard urls.count >= 2 else {
            throw XCTSkip("Expected at least 2 mp4 files in \(dir.path), found \(urls.count)")
        }

        return (urls[0], urls[1])
    }

    private func makeTwoClipTimeline(
        urlA: URL,
        urlB: URL,
        transitionOut: Transition,
        transitionIn: Transition
    ) -> Timeline {
        // Clip A: 0.0s..2.0s
        // Clip B: starts at 1.0s so we have a 1.0s overlap window.
        // Midpoint of overlap is 1.5s, which aligns to 24fps exactly.
        let clipADuration = Time(seconds: 2.0)
        let clipBDuration = Time(seconds: 2.0)
        let clipBStart = Time(seconds: 1.0)

        var clipA = Clip(
            name: "A",
            asset: AssetReference(sourceFn: urlA.absoluteURL.absoluteString),
            startTime: .zero,
            duration: clipADuration
        )
        clipA.transitionOut = transitionOut

        var clipB = Clip(
            name: "B",
            asset: AssetReference(sourceFn: urlB.absoluteURL.absoluteString),
            startTime: clipBStart,
            duration: clipBDuration
        )
        clipB.transitionIn = transitionIn

        let track = Track(name: "V", kind: .video, clips: [clipA, clipB])
        let duration = clipBStart + clipBDuration
        return Timeline(tracks: [track], duration: duration)
    }

    func test_dipToBlack_midpointIsNearBlack() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        DotEnvLoader.loadIfPresent()

        let inputs = try genAIInputs()
        let fade = Time(seconds: 1.0)

        let timeline = makeTwoClipTimeline(
            urlA: inputs.a,
            urlB: inputs.b,
            transitionOut: .dipToBlack(duration: fade),
            transitionIn: .dipToBlack(duration: fade)
        )

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let outputURL = TestOutputs.url(for: "transition_dip_to_black", quality: "360p")

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: draft360p(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        _ = try await VideoQC.validateMovie(
            at: outputURL,
            expectations: expectations(height: 360, durationSeconds: timeline.duration.seconds, fps: 24.0)
        )

        // Midpoint of overlap for this construction is 1.5s.
        // At progress=0.5, compositor_dip is exactly dipColor (black).
        _ = try await VideoContentQC.validateColorStats(
            movieURL: outputURL,
            samples: [
                .init(
                    timeSeconds: 1.5,
                    label: "dip_mid",
                    minMeanLuma: 0.0,
                    maxMeanLuma: 0.02,
                    maxChannelDelta: 0.02,
                    minLowLumaFraction: 0.90,
                    minHighLumaFraction: 0.0
                )
            ]
        )
    }

    func test_wipeLeftToRight_midpointHasDifferentLeftRightRegions() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        DotEnvLoader.loadIfPresent()

        let inputs = try genAIInputs()
        let fade = Time(seconds: 1.0)

        let timeline = makeTwoClipTimeline(
            urlA: inputs.a,
            urlB: inputs.b,
            transitionOut: Transition(type: .wipe(direction: .leftToRight), duration: fade, easing: .linear),
            transitionIn: Transition(type: .wipe(direction: .leftToRight), duration: fade, easing: .linear)
        )

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine)

        let outputURL = TestOutputs.url(for: "transition_wipe_l2r", quality: "360p")

        try await exporter.export(
            timeline: timeline,
            to: outputURL,
            quality: draft360p(),
            frameRate: 24,
            codec: .hevc,
            audioPolicy: .forbidden,
            governance: .none
        )

        _ = try await VideoQC.validateMovie(
            at: outputURL,
            expectations: expectations(height: 360, durationSeconds: timeline.duration.seconds, fps: 24.0)
        )

        let (left, right) = try meanLumaLeftRight(movieURL: outputURL, atSeconds: 1.5)
        let d = abs(left - right)

        // Very tolerant threshold: just prove it's spatially not-uniform at the transition midpoint.
        XCTAssertGreaterThan(d, 0.02, "Expected a wipe to create different left/right regions at midpoint; got left=\(left), right=\(right), |d|=\(d)")
    }

    private func meanLumaLeftRight(movieURL: URL, atSeconds t: Double) throws -> (left: Double, right: Double) {
        let asset = AVURLAsset(url: movieURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(seconds: t, preferredTimescale: 600)
        var actual = CMTime.zero
        let cg = try generator.copyCGImage(at: time, actualTime: &actual)

        // AVAssetImageGenerator may return 16bpc/float formats; normalize by drawing into 8bpc RGBA.
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "MetaVisTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create RGBA8 context"])
        }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerPixel = 4

        let xMid = width / 2
        let sampleStride = 4

        func luma(r: UInt8, g: UInt8, b: UInt8) -> Double {
            // Rec.709-ish weights (good enough for a relative region difference test).
            (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
        }

        var leftSum = 0.0
        var rightSum = 0.0
        var leftCount = 0
        var rightCount = 0

        for y in Swift.stride(from: 0, to: height, by: sampleStride) {
            let rowBase = y * bytesPerRow
            for x in Swift.stride(from: 0, to: width, by: sampleStride) {
                let i = rowBase + x * bytesPerPixel
                if i + 2 >= bytes.count { continue }

                // Treat as BGRA/ARGB interchangeably by sampling the three channels that are present.
                let c0 = bytes[i]
                let c1 = bytes[i + 1]
                let c2 = bytes[i + 2]

                // RGBA8 (byteOrder32Big + premultipliedLast).
                let lum = luma(r: c0, g: c1, b: c2)

                if x < xMid {
                    leftSum += lum
                    leftCount += 1
                } else {
                    rightSum += lum
                    rightCount += 1
                }
            }
        }

        let leftMean = leftCount > 0 ? (leftSum / Double(leftCount)) : 0
        let rightMean = rightCount > 0 ? (rightSum / Double(rightCount)) : 0
        return (leftMean, rightMean)
    }
}
