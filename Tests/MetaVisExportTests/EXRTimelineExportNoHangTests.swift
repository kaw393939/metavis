import XCTest
import AVFoundation
@testable import MetaVisExport
import MetaVisCore
import MetaVisTimeline
@testable import MetaVisSimulation

final class EXRTimelineExportNoHangTests: XCTestCase {
    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(
                    domain: "MetaVisTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Timed out after \(seconds)s"]
                )
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
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

    func testEXRRenderToPixelBufferNotBlack() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let exrDir = root.appendingPathComponent("assets").appendingPathComponent("exr")
        let exr1 = exrDir.appendingPathComponent("AllHalfValues.exr")
        guard FileManager.default.fileExists(atPath: exr1.path) else {
            throw XCTSkip("Missing test asset: \(exr1.path)")
        }

        let clip = Clip(
            name: "00_AllHalfValues",
            asset: AssetReference(sourceFn: exr1.absoluteURL.absoluteString),
            startTime: .zero,
            duration: Time(seconds: 1.0 / 24.0),
            offset: .zero,
            transitionIn: nil,
            transitionOut: nil,
            effects: [.init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])]
        )

        let timeline = Timeline(
            tracks: [Track(name: "EXR", kind: .video, clips: [clip])],
            duration: Time(seconds: 1.0 / 24.0)
        )

        let quality = QualityProfile(name: "EXRTest", fidelity: .high, resolutionHeight: 256, colorDepth: 10)
        let compiler = TimelineCompiler()
        let request = try await compiler.compile(timeline: timeline, at: .zero, quality: quality)

        let width = quality.resolutionHeight * 16 / 9
        let height = quality.resolutionHeight

        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pixelBuffer = pb else {
            XCTFail("Failed to create CVPixelBuffer: \(status)")
            return
        }

        let engine = try MetalSimulationEngine()
        try await engine.render(request: request, to: pixelBuffer, watermark: nil)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            XCTFail("Missing pixel buffer base address")
            return
        }
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let samplePoints = [
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1),
            (width / 2, height / 2),
            (width / 4, height / 4),
            (3 * width / 4, height / 4),
            (width / 4, 3 * height / 4),
            (3 * width / 4, 3 * height / 4)
        ]

        var sawNonBlack = false
        for (x, y) in samplePoints {
            let px = max(0, min(width - 1, x))
            let py = max(0, min(height - 1, y))
            let p = base.advanced(by: py * bpr + px * 4).assumingMemoryBound(to: UInt8.self)
            let b = Int(p[0])
            let g = Int(p[1])
            let r = Int(p[2])
            if (r + g + b) > 3 {
                sawNonBlack = true
                break
            }
        }

        XCTAssertTrue(sawNonBlack, "Rendered sampled pixels are all black")
    }

    func testEXRClipReaderTextureNotBlack() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let exrDir = root.appendingPathComponent("assets").appendingPathComponent("exr")
        let exr1 = exrDir.appendingPathComponent("AllHalfValues.exr")
        guard FileManager.default.fileExists(atPath: exr1.path) else {
            throw XCTSkip("Missing test asset: \(exr1.path)")
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal unavailable")
        }

        let reader = ClipReader(device: device)
        let width = 256 * 16 / 9
        let height = 256
        let tex = try await reader.texture(assetURL: exr1, timeSeconds: 0.0, width: width, height: height)

        let samplePoints = [
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1),
            (width / 2, height / 2),
            (width / 4, height / 4),
            (3 * width / 4, height / 4),
            (width / 4, 3 * height / 4),
            (3 * width / 4, 3 * height / 4)
        ]

        var sawNonBlack = false
        for (x, y) in samplePoints {
            var pixel = [UInt8](repeating: 0, count: 4)
            let px = max(0, min(width - 1, x))
            let py = max(0, min(height - 1, y))
            tex.getBytes(
                &pixel,
                bytesPerRow: 4,
                from: MTLRegionMake2D(px, py, 1, 1),
                mipmapLevel: 0
            )
            let b = Int(pixel[0])
            let g = Int(pixel[1])
            let r = Int(pixel[2])
            if (r + g + b) > 3 {
                sawNonBlack = true
                break
            }
        }

        XCTAssertTrue(sawNonBlack, "ClipReader sampled texels are all black")
    }

    func testEXRTimelineExportProducesProbeableMovie() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let exrDir = root.appendingPathComponent("assets").appendingPathComponent("exr")

        let exr1 = exrDir.appendingPathComponent("AllHalfValues.exr")
        let exr2 = exrDir.appendingPathComponent("BrightRingsNanInf.exr")

        guard FileManager.default.fileExists(atPath: exr1.path) else {
            throw XCTSkip("Missing test asset: \(exr1.path)")
        }
        guard FileManager.default.fileExists(atPath: exr2.path) else {
            throw XCTSkip("Missing test asset: \(exr2.path)")
        }

        let dur = 1.0 / 24.0
        let clips: [Clip] = [
            Clip(
                name: "00_AllHalfValues",
                asset: AssetReference(sourceFn: exr1.absoluteURL.absoluteString),
                startTime: .zero,
                duration: Time(seconds: dur),
                offset: .zero,
                transitionIn: nil,
                transitionOut: nil,
                effects: [.init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])]
            ),
            Clip(
                name: "01_BrightRingsNanInf",
                asset: AssetReference(sourceFn: exr2.absoluteURL.absoluteString),
                startTime: Time(seconds: dur),
                duration: Time(seconds: dur),
                offset: .zero,
                transitionIn: nil,
                transitionOut: nil,
                effects: [.init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])]
            )
        ]

        let timeline = Timeline(
            tracks: [Track(name: "EXR", kind: .video, clips: clips)],
            duration: Time(seconds: dur * Double(clips.count))
        )

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let outURL = tmp.appendingPathComponent("exr_timeline_test.mov")

        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine)
        let quality = QualityProfile(name: "EXRTest", fidelity: .high, resolutionHeight: 256, colorDepth: 10)

        try await withTimeout(seconds: 60.0) {
            try await exporter.export(
                timeline: timeline,
                to: outURL,
                quality: quality,
                frameRate: 24,
                codec: .hevc,
                audioPolicy: .forbidden,
                governance: .none
            )
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Expected non-empty movie")

        // Ensure container is readable (catches 0-byte / missing moov atom issues).
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = [
            "ffprobe",
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            outURL.path
        ]
        let outPipe = Pipe()
        probe.standardOutput = outPipe
        try probe.run()
        probe.waitUntilExit()
        XCTAssertEqual(probe.terminationStatus, 0, "ffprobe failed")

        let durationStr = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertFalse(durationStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        // Sanity: first frame should not be entirely black.
        // (This catches EXR alpha/premultiply issues that yield black renders.)
        let black = Process()
        black.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        black.arguments = [
            "ffmpeg",
            "-v", "info",
            "-i", outURL.path,
            "-vf", "blackframe=98:32",
            "-frames:v", "1",
            "-f", "null",
            "-"
        ]
        let blackErr = Pipe()
        black.standardError = blackErr
        try black.run()
        black.waitUntilExit()
        XCTAssertEqual(black.terminationStatus, 0, "ffmpeg blackframe probe failed")

        let blackText = String(data: blackErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertFalse(blackText.contains("pblack:100"), "First frame is 100% black")
    }

    func testEXRTimelineExportWithCrossfadesProducesMovie() async throws {
        try requireTool("ffmpeg")
        try requireTool("ffprobe")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let exrDir = root.appendingPathComponent("assets").appendingPathComponent("exr")

        let exr1 = exrDir.appendingPathComponent("AllHalfValues.exr")
        let exr2 = exrDir.appendingPathComponent("BrightRingsNanInf.exr")

        guard FileManager.default.fileExists(atPath: exr1.path) else {
            throw XCTSkip("Missing test asset: \(exr1.path)")
        }
        guard FileManager.default.fileExists(atPath: exr2.path) else {
            throw XCTSkip("Missing test asset: \(exr2.path)")
        }

        let fps: Int32 = 24
        let secondsPer: Double = 1.0
        let transition = Transition.crossfade(duration: Time(seconds: 0.25), easing: .linear)

        // Overlap clips by transition duration so the compiler sees multiple active clips.
        let t0 = Time.zero
        let t1 = Time(seconds: max(0.0, secondsPer - transition.duration.seconds))

        let clips: [Clip] = [
            Clip(
                name: "00_AllHalfValues",
                asset: AssetReference(sourceFn: exr1.absoluteURL.absoluteString),
                startTime: t0,
                duration: Time(seconds: secondsPer),
                offset: .zero,
                transitionIn: nil,
                transitionOut: transition,
                effects: [.init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])]
            ),
            Clip(
                name: "01_BrightRingsNanInf",
                asset: AssetReference(sourceFn: exr2.absoluteURL.absoluteString),
                startTime: t1,
                duration: Time(seconds: secondsPer),
                offset: .zero,
                transitionIn: transition,
                transitionOut: nil,
                effects: [.init(id: "com.metavis.fx.tonemap.aces", parameters: ["exposure": .float(1.0)])]
            )
        ]

        let timeline = Timeline(
            tracks: [Track(name: "EXR", kind: .video, clips: clips)],
            duration: t1 + Time(seconds: secondsPer)
        )

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("metavis_tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let outURL = tmp.appendingPathComponent("exr_timeline_crossfade_test.mov")

        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine)
        let quality = QualityProfile(name: "EXRTest", fidelity: .high, resolutionHeight: 256, colorDepth: 10)

        try await withTimeout(seconds: 60.0) {
            try await exporter.export(
                timeline: timeline,
                to: outURL,
                quality: quality,
                frameRate: fps,
                codec: .hevc,
                audioPolicy: .forbidden,
                governance: .none
            )
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertGreaterThan(size, 0, "Expected non-empty movie")

        // Basic probe: ensure duration is present.
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        probe.arguments = [
            "ffprobe",
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            outURL.path
        ]
        let out = Pipe()
        probe.standardOutput = out
        try probe.run()
        probe.waitUntilExit()
        XCTAssertEqual(probe.terminationStatus, 0)
    }
}
