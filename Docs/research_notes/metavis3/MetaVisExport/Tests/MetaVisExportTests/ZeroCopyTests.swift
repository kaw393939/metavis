import XCTest
import Metal
import CoreVideo
@testable import MetaVisExport

final class ZeroCopyTests: XCTestCase {
    
    func testInitialization() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal is not supported on this device")
            return
        }
        
        do {
            let converter = try ZeroCopyConverter(device: device)
            XCTAssertNotNil(converter, "ZeroCopyConverter should be initialized")
        } catch {
            XCTFail("Failed to initialize ZeroCopyConverter: \(error)")
        }
    }
    
    func testShaderLoading() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        
        // This will trigger the loadShader() method
        let converter = try ZeroCopyConverter(device: device)
        
        // We can't easily inspect private properties, but if init succeeds, shader loaded.
        // Let's try to create a pixel buffer pool to verify that part too.
        let pool = converter.createPixelBufferPool(width: 1920, height: 1080)
        XCTAssertNotNil(pool, "PixelBufferPool should be created")
    }
}
