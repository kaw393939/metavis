import XCTest
import AVFoundation

import MetaVisCore
import MetaVisExport
import MetaVisIngest
import MetaVisQC
import MetaVisSimulation
import MetaVisTimeline

/// Sprint 21: edit-aware A/V sync contract for VFR sources.
///
/// Strategy:
/// - Generate a deterministic VFR MP4 with a single red→green transition at a known time.
/// - Export a timeline containing that VFR clip plus a deterministic audio marker (`ligm://audio/marker`).
/// - Detect the audio marker timestamp from the exported file.
/// - Assert the video is red just before the marker and green just after (within tolerance).
final class VFRSyncContractE2ETests: XCTestCase {

    func test_edits_preserve_av_sync_with_marker_track() async throws {
        try requireTool("ffmpeg")

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("metavis_vfr_sync_fixture_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Generate a deterministic VFR fixture with a single red->green transition.
        let (vfrURL, transitionSeconds) = try generateVFRRedToGreenFixtureMP4(at: tmp, nominalTransitionSeconds: 1.0)

        // Sanity: should be VFR-likely.
        let profile = try await VideoTimingProbe.probe(url: vfrURL)
        XCTAssertTrue(profile.isVFRLikely)

        // Baseline export.
        try await exportAndAssertMarkerAlignsToTransition(
            vfrURL: vfrURL,
            clipOffsetSeconds: 0.0,
            markerAtSeconds: transitionSeconds,
            label: "baseline"
        )

        // "Edit": simulate a trim-in by advancing the source offset.
        // The transition should appear earlier in timeline time by the same amount.
        let trimIn: Double = 0.25
        try await exportAndAssertMarkerAlignsToTransition(
            vfrURL: vfrURL,
            clipOffsetSeconds: trimIn,
            markerAtSeconds: max(0.0, transitionSeconds - trimIn),
            label: "trim_in"
        )
    }

    private func exportAndAssertMarkerAlignsToTransition(
        vfrURL: URL,
        clipOffsetSeconds: Double,
        markerAtSeconds: Double,
        label: String
    ) async throws {
        let duration = Time(seconds: 2.0)

        var video = Clip(
            name: "VFR",
            asset: AssetReference(sourceFn: vfrURL.path),
            startTime: .zero,
            duration: duration
        )
        video.offset = Time(seconds: max(0.0, clipOffsetSeconds))

        let audio = Clip(
            name: "Marker",
            asset: AssetReference(sourceFn: "ligm://audio/marker?at=\(String(format: "%.6f", markerAtSeconds))"),
            startTime: .zero,
            duration: duration
        )

        let timeline = Timeline(
            tracks: [
                Track(name: "V", kind: .video, clips: [video]),
                Track(name: "A", kind: .audio, clips: [audio])
            ],
            duration: duration
        )

        let outURL = TestOutputs.url(for: "vfr_sync_contract_\(label)", quality: "256p_8bit", ext: "mov")
        let quality = QualityProfile(name: "Test", fidelity: .high, resolutionHeight: 256, colorDepth: 8)

        let engine = try MetalSimulationEngine()
        try await engine.configure()
        let exporter = VideoExporter(engine: engine, trace: NoOpTraceSink())

        let fps: Int = 30
        try await exporter.export(
            timeline: timeline,
            to: outURL,
            quality: quality,
            frameRate: fps,
            codec: .hevc,
            audioPolicy: .required,
            governance: .none
        )

        // Prove the deliverable actually contains audio and it isn't silent.
        try await VideoQC.assertHasAudioTrack(at: outURL)
        try await VideoQC.assertAudioNotSilent(at: outURL, sampleSeconds: 1.5, minPeak: 0.01)

        // Detect the marker time from the exported audio track.
        let markerTime = try await detectFirstAudioPeakTimeSeconds(movieURL: outURL, threshold: 0.05)

        // Sync contract: at (markerTime - tol) we should still be red; at (markerTime + tol) we should be green.
        let tolSeconds = max(0.08, 3.0 / Double(fps))
        let tBefore = max(0.0, markerTime - tolSeconds)
        let tAfter = markerTime + tolSeconds

        let stats = try await VideoContentQC.validateColorStats(
            movieURL: outURL,
            samples: [
                .init(timeSeconds: tBefore, label: "before", minMeanLuma: 0.0, maxMeanLuma: 1.0, maxChannelDelta: 1.0, minLowLumaFraction: 0.0, minHighLumaFraction: 0.0),
                .init(timeSeconds: tAfter, label: "after", minMeanLuma: 0.0, maxMeanLuma: 1.0, maxChannelDelta: 1.0, minLowLumaFraction: 0.0, minHighLumaFraction: 0.0)
            ]
        )

        guard stats.count == 2 else {
            XCTFail("Expected 2 color stats samples")
            return
        }

        let before = stats[0].meanRGB
        let after = stats[1].meanRGB

        XCTAssertTrue(isRedDominant(before), "Expected red-dominant frame before marker at t=\(tBefore). meanRGB=\(before)")
        XCTAssertTrue(isGreenDominant(after), "Expected green-dominant frame after marker at t=\(tAfter). meanRGB=\(after)")
    }

    private func isRedDominant(_ rgb: SIMD3<Float>) -> Bool {
        (rgb.x > rgb.y + 0.05) && (rgb.x > rgb.z + 0.05)
    }

    private func isGreenDominant(_ rgb: SIMD3<Float>) -> Bool {
        (rgb.y > rgb.x + 0.05) && (rgb.y > rgb.z + 0.05)
    }

    private func generateVFRRedToGreenFixtureMP4(at tmp: URL, nominalTransitionSeconds: Double) throws -> (URL, Double) {
        let framesDir = tmp.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let red = framesDir.appendingPathComponent("red.png")
        let green = framesDir.appendingPathComponent("green.png")

        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=red:s=320x180:r=60",
                "-frames:v", "1",
                red.path
            ]
        )
        try run(
            "/usr/bin/env",
            [
                "ffmpeg", "-nostdin", "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=green:s=320x180:r=60",
                "-frames:v", "1",
                green.path
            ]
        )

        // Build a concat list that is reliably detected as VFR-likely by `VideoTimingProbe`.
        // We reuse the known-good pattern from `VFRGeneratedFixtureTests`.
        let dA = 0.033
        let dB = 0.050
        let avg = 0.5 * (dA + dB)
        let redCount = max(2, Int((nominalTransitionSeconds / avg).rounded(.toNearestOrAwayFromZero)))
        let totalCount = max(80, redCount * 2)

        // Compute the transition time we are encoding into the concat list (deterministic).
        let aCount = (redCount + 1) / 2
        let bCount = redCount / 2
        let transitionSeconds = Double(aCount) * dA + Double(bCount) * dB

        let list = tmp.appendingPathComponent("list.txt")
        var listText = ""
        for i in 0..<totalCount {
            let frameURL = (i < redCount) ? red : green
            let dur = (i % 2 == 0) ? dA : dB
            listText += "file '\(frameURL.path)'\n"
            listText += String(format: "duration %.3f\n", dur)
        }
        listText += "file '\(green.path)'\n"
        try listText.write(to: list, atomically: true, encoding: .utf8)

        let out = tmp.appendingPathComponent("vfr_red_green.mp4")
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
        return (out, transitionSeconds)
    }

    private func detectFirstAudioPeakTimeSeconds(movieURL: URL, threshold: Float) async throws -> Double {
        let asset = AVURLAsset(url: movieURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw NSError(domain: "MetaVisTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track"])
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(domain: "MetaVisTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output"])
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "MetaVisTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed"])
        }

        var sampleRate: Double = 48_000
        var channels: Int = 2

        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds

            if let desc = CMSampleBufferGetFormatDescription(sample) {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    if asbd.mSampleRate.isFinite, asbd.mSampleRate > 0 {
                        sampleRate = asbd.mSampleRate
                    }
                    channels = Int(asbd.mChannelsPerFrame)
                }
            }

            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if status != kCMBlockBufferNoErr { continue }
            guard let dataPointer else { continue }

            let floatCount = length / MemoryLayout<Float>.size
            let floats = dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
                UnsafeBufferPointer(start: ptr, count: floatCount)
            }

            let frames = CMSampleBufferGetNumSamples(sample)
            let ch = max(1, channels)

            if frames > 0, floatCount >= frames * ch {
                for i in 0..<frames {
                    var peak: Float = 0
                    for c in 0..<ch {
                        let v = floats[i * ch + c]
                        let a = abs(v)
                        if a > peak { peak = a }
                    }
                    if peak >= threshold {
                        return pts + (Double(i) / sampleRate)
                    }
                }
            }
        }

        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "MetaVisTest", code: 4, userInfo: [NSLocalizedDescriptionKey: "Audio reader failed"])
        }

        throw NSError(domain: "MetaVisTest", code: 5, userInfo: [NSLocalizedDescriptionKey: "No audio peak >= \(threshold) found"])
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
            throw NSError(domain: "MetaVisTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Command failed: \(args.joined(separator: " "))\n\(text)"])
        }
    }
}
