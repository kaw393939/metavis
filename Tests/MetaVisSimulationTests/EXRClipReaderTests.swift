import XCTest
import Metal
@testable import MetaVisSimulation

final class EXRClipReaderTests: XCTestCase {
    func testLoadsEXRViaFFmpeg() async throws {
        // Skip if ffmpeg isn't available.
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

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available")
        }

        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets")
            .appendingPathComponent("exr")
            .appendingPathComponent("AllHalfValues.exr")

        if !FileManager.default.fileExists(atPath: url.path) {
            throw XCTSkip("Missing test asset: \(url.path)")
        }

        let reader = ClipReader(device: device, maxCachedFrames: 4)
        let tex = try await reader.texture(assetURL: url, timeSeconds: 0.0, width: 256, height: 256)
        XCTAssertEqual(tex.width, 256)
        XCTAssertEqual(tex.height, 256)
        XCTAssertEqual(tex.pixelFormat, .rgba16Float)
    }
}
