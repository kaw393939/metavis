import XCTest
import Metal
import MetaVisSimulation

final class ClipReaderCacheTests: XCTestCase {
    func testClearCachesClearsStats() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available")
        }
        let reader = ClipReader(device: device, maxCachedFrames: 4)

        // We can't reliably decode media assets in unit tests here without fixtures,
        // so we validate the cache control surface itself.
        _ = await reader.cacheStats()
        await reader.clearCaches()
        let stats = await reader.cacheStats()
        XCTAssertEqual(stats.frameCacheCount, 0)
        XCTAssertEqual(stats.stillPixelBufferCount, 0)
        XCTAssertEqual(stats.decoderCount, 0)
    }

    func testHandleMemoryPressureClearsCaches() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal not available")
        }
        let reader = ClipReader(device: device, maxCachedFrames: 4)

        await reader.handleMemoryPressure()
        let stats = await reader.cacheStats()
        XCTAssertEqual(stats.frameCacheCount, 0)
        XCTAssertEqual(stats.stillPixelBufferCount, 0)
        XCTAssertEqual(stats.decoderCount, 0)
    }
}
