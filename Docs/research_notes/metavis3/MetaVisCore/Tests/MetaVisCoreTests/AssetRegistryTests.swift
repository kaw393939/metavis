import XCTest
@testable import MetaVisCore

final class AssetRegistryTests: XCTestCase {
    
    func testRegisterAndRetrieve() {
        var registry = AssetRegistry()
        let asset = Asset(
            name: "Test Video",
            url: URL(fileURLWithPath: "/tmp/video.mp4"),
            type: .video,
            duration: RationalTime(value: 100, timescale: 30)
        )
        
        registry.register(asset)
        
        let retrieved = registry.asset(for: asset.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Test Video")
    }
    
    func testRemove() {
        var registry = AssetRegistry()
        let asset = Asset(
            name: "Test Image",
            url: URL(fileURLWithPath: "/tmp/image.jpg"),
            type: .image,
            duration: .zero
        )
        
        registry.register(asset)
        XCTAssertNotNil(registry.asset(for: asset.id))
        
        registry.remove(id: asset.id)
        XCTAssertNil(registry.asset(for: asset.id))
    }
    
    func testAllAssets() {
        var registry = AssetRegistry()
        let a1 = Asset(name: "A1", url: URL(fileURLWithPath: "/a"), type: .image, duration: .zero)
        let a2 = Asset(name: "A2", url: URL(fileURLWithPath: "/b"), type: .image, duration: .zero)
        
        registry.register(a1)
        registry.register(a2)
        
        XCTAssertEqual(registry.allAssets.count, 2)
    }
    
    func testCodable() throws {
        var registry = AssetRegistry()
        let asset = Asset(
            name: "Persisted Asset",
            url: URL(fileURLWithPath: "/tmp/p.mov"),
            type: .video,
            duration: .zero
        )
        registry.register(asset)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(registry)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AssetRegistry.self, from: data)
        
        XCTAssertNotNil(decoded.asset(for: asset.id))
        XCTAssertEqual(decoded.asset(for: asset.id)?.name, "Persisted Asset")
    }
}
