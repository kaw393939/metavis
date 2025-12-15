import XCTest
import Metal
@testable import MetaVisSimulation

private enum TestTimeout: Error {
    case timedOut
}

private func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0.0, seconds) * 1_000_000_000.0))
            throw TestTimeout.timedOut
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

final class EXRDecodeNoHangTests: XCTestCase {
    private func requireFFmpeg() throws {
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
    }

    func testDecodeDoesNotHang_onBrightRingsNanInf() async throws {
        try requireFFmpeg()

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available")
        }

        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets")
            .appendingPathComponent("exr")
            .appendingPathComponent("BrightRingsNanInf.exr")

        if !FileManager.default.fileExists(atPath: url.path) {
            throw XCTSkip("Missing test asset: \(url.path)")
        }

        let reader = ClipReader(device: device, maxCachedFrames: 4)

        do {
            _ = try await withTimeout(seconds: 15.0) {
                try await reader.texture(assetURL: url, timeSeconds: 0.0, width: 256, height: 256)
            }
        } catch TestTimeout.timedOut {
            XCTFail("EXR decode hung (likely ffmpeg stdout/stderr pipe deadlock)")
        }
    }
}
