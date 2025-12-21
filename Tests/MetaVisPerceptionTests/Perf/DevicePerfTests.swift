import XCTest
import CoreVideo
import MetaVisPerception

final class DevicePerfTests: XCTestCase {

    private func requirePerfEnabled() throws {
        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_DEVICE_PERF_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_DEVICE_PERF_TESTS=1 to enable device perf tests")
        }
    }

    private func assetURL(_ relPath: String) throws -> URL {
        let url = URL(fileURLWithPath: relPath)
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Allow running from repo root with relative Tests/Assets paths.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let alt = cwd.appendingPathComponent(relPath)
        if FileManager.default.fileExists(atPath: alt.path) {
            return alt
        }
        throw XCTSkip("Missing test asset at \(relPath)")
    }

    func test_perf_maskdevice_single_frame_budget() async throws {
        try requirePerfEnabled()

        let url = try assetURL("Tests/Assets/VideoEdit/keith_talk.mov")
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 2.0)
        guard let frame = frames.first else {
            throw XCTSkip("No frames decoded")
        }

        let device = MaskDevice()
        try await device.warmUp()

        let iterations = Int(ProcessInfo.processInfo.environment["METAVIS_MASKDEVICE_PERF_ITERS"] ?? "") ?? 12

        let avgMs = try await PerceptionDeviceHarnessV1.averageInferMillis(
            device: device,
            input: .init(pixelBuffer: frame, kind: .foreground, timeSeconds: 0.0),
            iterations: iterations
        )

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_MASKDEVICE_FRAME_BUDGET_MS"] ?? "")
            ?? (isCI ? 1200.0 : 350.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg MaskDevice %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }

    func test_perf_tracksdevice_single_frame_budget() async throws {
        try requirePerfEnabled()

        let url = try assetURL("Tests/Assets/VideoEdit/keith_talk.mov")
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 2.0)
        guard let frame = frames.first else {
            throw XCTSkip("No frames decoded")
        }

        let device = TracksDevice()
        try await device.warmUp()

        let iterations = Int(ProcessInfo.processInfo.environment["METAVIS_TRACKSDEVICE_PERF_ITERS"] ?? "") ?? 24

        let avgMs = try await PerceptionDeviceHarnessV1.averageInferMillis(
            device: device,
            input: .init(pixelBuffer: frame),
            iterations: iterations
        )

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_TRACKSDEVICE_FRAME_BUDGET_MS"] ?? "")
            ?? (isCI ? 600.0 : 150.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg TracksDevice %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }

    func test_perf_facepartsdevice_single_frame_budget() async throws {
        try requirePerfEnabled()

        let url = try assetURL("Tests/Assets/VideoEdit/keith_talk.mov")
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 2.0)
        guard let frame = frames.first else {
            throw XCTSkip("No frames decoded")
        }

        let device = FacePartsDevice()
        try await device.warmUp()

        let iterations = Int(ProcessInfo.processInfo.environment["METAVIS_FACEPARTS_PERF_ITERS"] ?? "") ?? 24

        let avgMs = try await PerceptionDeviceHarnessV1.averageInferMillis(
            device: device,
            input: .init(pixelBuffer: frame),
            iterations: iterations
        )

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_FACEPARTS_FRAME_BUDGET_MS"] ?? "")
            ?? (isCI ? 900.0 : 200.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg FacePartsDevice %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }

    func test_perf_mobilesam_single_frame_budget_when_enabled() async throws {
        try requirePerfEnabled()

        let env = ProcessInfo.processInfo.environment
        if env["METAVIS_RUN_MOBILESAM_TESTS"] != "1" {
            throw XCTSkip("Set METAVIS_RUN_MOBILESAM_TESTS=1 (and provide models) to enable MobileSAM perf")
        }

        let url = try assetURL("Tests/Assets/VideoEdit/keith_talk.mov")
        let frames = try await VideoFrameReader.readFrames(url: url, maxFrames: 1, maxSeconds: 2.0)
        guard let frame = frames.first else {
            throw XCTSkip("No frames decoded")
        }

        let device = MobileSAMDevice()
        try await device.warmUp()

        // Measure interactive prompting: encode once (warm), then many prompt-only iterations.
        let cacheKey = MobileSAMSegmentationService.CacheKey.make(
            sourceKey: url.standardizedFileURL.absoluteString,
            timeSeconds: 0.0,
            width: CVPixelBufferGetWidth(frame),
            height: CVPixelBufferGetHeight(frame)
        )

        // Prime the encoder cache.
        _ = await device.segment(
            pixelBuffer: frame,
            prompt: .init(pointTopLeft: CGPoint(x: 0.5, y: 0.6), label: 1),
            cacheKey: cacheKey
        )

        let iterations = Int(env["METAVIS_MOBILESAM_PERF_ITERS"] ?? "") ?? 6
        let avgMs = try await averageMobileSAMPromptLoopMillis(
            device: device,
            frame: frame,
            cacheKey: cacheKey,
            iterations: iterations
        )

        let isCI = env["CI"] == "true"
        let budgetMs = Double(env["METAVIS_MOBILESAM_FRAME_BUDGET_MS"] ?? "")
            ?? (isCI ? 6000.0 : 1200.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg MobileSAM %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }

    @available(macOS 13.0, iOS 16.0, *)
    private func averageMobileSAMPromptLoopMillis(
        device: MobileSAMDevice,
        frame: CVPixelBuffer,
        cacheKey: String,
        iterations: Int
    ) async throws -> Double {
        let iters = max(1, iterations)

        // Alternate prompts to better represent interactive clicking/dragging.
        let a = MobileSAMDevice.PointPrompt(pointTopLeft: CGPoint(x: 0.48, y: 0.58), label: 1)
        let b = MobileSAMDevice.PointPrompt(pointTopLeft: CGPoint(x: 0.62, y: 0.58), label: 1)

        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<iters {
            let p = (i % 2 == 0) ? a : b
            _ = await device.segment(pixelBuffer: frame, prompt: p, cacheKey: cacheKey)
        }
        let elapsed = clock.now - start

        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        return (seconds / Double(iters)) * 1000.0
    }
}
