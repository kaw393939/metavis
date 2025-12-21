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
        try await device.warmUp(kind: .foreground)
        _ = try await device.generateMask(in: frame, kind: .foreground)

        let iterations = Int(ProcessInfo.processInfo.environment["METAVIS_MASKDEVICE_PERF_ITERS"] ?? "") ?? 12

        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations {
            _ = try await device.generateMask(in: frame, kind: .foreground)
        }
        let elapsed = clock.now - start
        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        let avgMs = (seconds / Double(iterations)) * 1000.0

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
        _ = try await device.track(in: frame)

        let iterations = Int(ProcessInfo.processInfo.environment["METAVIS_TRACKSDEVICE_PERF_ITERS"] ?? "") ?? 24

        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations {
            _ = try await device.track(in: frame)
        }
        let elapsed = clock.now - start
        let c = elapsed.components
        let seconds = Double(c.seconds) + (Double(c.attoseconds) / 1_000_000_000_000_000_000.0)
        let avgMs = (seconds / Double(iterations)) * 1000.0

        let isCI = ProcessInfo.processInfo.environment["CI"] == "true"
        let budgetMs = Double(ProcessInfo.processInfo.environment["METAVIS_TRACKSDEVICE_FRAME_BUDGET_MS"] ?? "")
            ?? (isCI ? 600.0 : 150.0)

        XCTAssertLessThanOrEqual(avgMs, budgetMs, String(format: "Avg TracksDevice %.2fms exceeded budget %.2fms", avgMs, budgetMs))
    }
}
