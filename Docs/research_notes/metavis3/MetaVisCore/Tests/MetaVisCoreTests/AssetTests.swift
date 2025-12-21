import XCTest
@testable import MetaVisCore

final class AssetTests: XCTestCase {
    
    func testAssetInitialization_Local() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let asset = Asset(
            name: "Test Video",
            status: .local,
            url: url,
            type: .video,
            duration: RationalTime(value: 100, timescale: 24)
        )
        
        XCTAssertEqual(asset.name, "Test Video")
        XCTAssertEqual(asset.status, .local)
        XCTAssertEqual(asset.url, url)
        XCTAssertNil(asset.generativeMetadata)
    }
    
    func testAssetInitialization_Generative() {
        let genMeta = GenerativeMetadata(prompt: "A futuristic city", providerId: "google-veo")
        let asset = Asset(
            name: "Gen Video",
            status: .generating,
            generativeMetadata: genMeta,
            type: .video,
            duration: RationalTime(value: 0, timescale: 24) // Unknown duration initially
        )
        
        XCTAssertEqual(asset.status, .generating)
        XCTAssertNil(asset.url)
        XCTAssertEqual(asset.generativeMetadata?.prompt, "A futuristic city")
    }
    
    func testAssetCodable() throws {
        let genMeta = GenerativeMetadata(prompt: "A futuristic city", providerId: "google-veo")
        let asset = Asset(
            name: "Gen Video",
            status: .generating,
            generativeMetadata: genMeta,
            type: .video,
            duration: RationalTime(value: 0, timescale: 24)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(asset)
        
        let decoder = JSONDecoder()
        let decodedAsset = try decoder.decode(Asset.self, from: data)
        
        XCTAssertEqual(decodedAsset.id, asset.id)
        XCTAssertEqual(decodedAsset.status, .generating)
        XCTAssertEqual(decodedAsset.generativeMetadata?.providerId, "google-veo")
    }
    
    func testAssetPerformance_LargeCollection() {
        // Performance test for encoding/decoding a large number of assets
        let assets = (0..<1000).map { i in
            Asset(
                name: "Asset \(i)",
                status: .local,
                url: URL(fileURLWithPath: "/tmp/\(i).mov"),
                type: .video,
                duration: RationalTime(value: Int64(i * 100), timescale: 24)
            )
        }
        
        measure {
            do {
                let data = try JSONEncoder().encode(assets)
                let _ = try JSONDecoder().decode([Asset].self, from: data)
            } catch {
                XCTFail("Encoding/Decoding failed: \(error)")
            }
        }
    }
    
    func testEdgeCase_MissingURLForReadyAsset() {
        // Ideally, a 'ready' asset should have a URL. 
        // This test documents current behavior (it allows it) or enforces validation if we add it.
        let asset = Asset(
            name: "Broken Asset",
            status: .ready,
            url: nil, // Should probably be invalid in a stricter system
            type: .image,
            duration: .zero
        )
        
        XCTAssertNil(asset.url)
        XCTAssertEqual(asset.status, .ready)
    }
    
    func testAssetWithMetadata() {
        let coordinate = GeoCoordinate(latitude: 37.7749, longitude: -122.4194)
        let place = PlaceInfo(name: "San Francisco", country: "USA")
        let spatial = SpatialContext(coordinate: coordinate, place: place, sceneType: .urban)
        
        let segmentation = SegmentationLayer(
            label: "Person",
            confidence: 0.9,
            bounds: Rect(x: 0, y: 0, width: 0.5, height: 1.0)
        )
        let visual = VisualAnalysis(segmentation: [segmentation])
        
        var asset = Asset(
            name: "Metadata Asset",
            status: .local,
            url: URL(fileURLWithPath: "/tmp/meta.jpg"),
            type: .image,
            duration: .zero,
            spatial: spatial,
            visual: visual
        )
        
        XCTAssertNotNil(asset.spatial)
        XCTAssertEqual(asset.spatial?.coordinate?.latitude, 37.7749)
        XCTAssertEqual(asset.spatial?.place?.name, "San Francisco")
        XCTAssertEqual(asset.spatial?.sceneType, .urban)
        
        XCTAssertNotNil(asset.visual)
        XCTAssertEqual(asset.visual?.segmentation.count, 1)
        XCTAssertEqual(asset.visual?.segmentation.first?.label, "Person")
    }
}
