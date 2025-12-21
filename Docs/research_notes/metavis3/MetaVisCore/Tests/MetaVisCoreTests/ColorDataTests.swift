import XCTest
@testable import MetaVisCore

final class ColorDataTests: XCTestCase {
    
    func testColorProfileEquality() {
        let p1 = ColorProfile(primaries: .rec709, transferFunction: .sRGB)
        let p2 = ColorProfile.sRGB
        let p3 = ColorProfile(primaries: .rec2020, transferFunction: .pq)
        
        XCTAssertEqual(p1, p2)
        XCTAssertNotEqual(p1, p3)
    }
    
    func testWhitePointAssociation() {
        // Verify standard associations
        XCTAssertEqual(ColorPrimaries.rec709.whitePoint, .d65)
        XCTAssertEqual(ColorPrimaries.rec2020.whitePoint, .d65)
        XCTAssertEqual(ColorPrimaries.p3d65.whitePoint, .d65)
        
        // Verify ACES associations
        XCTAssertEqual(ColorPrimaries.acescg.whitePoint, .d60)
        XCTAssertEqual(ColorPrimaries.aces2065_1.whitePoint, .d60)
    }
    
    func testCodable() throws {
        let profile = ColorProfile.appleLog
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ColorProfile.self, from: data)
        
        XCTAssertEqual(profile, decoded)
        XCTAssertEqual(decoded.primaries, .rec2020)
        XCTAssertEqual(decoded.transferFunction, .appleLog)
    }
    
    func testAssetIntegration() {
        let profile = ColorProfile.acescg
        let asset = Asset(
            name: "Test Asset",
            url: URL(fileURLWithPath: "/tmp/test.exr"),
            type: .image,
            duration: .zero,
            colorProfile: profile
        )
        
        XCTAssertNotNil(asset.colorProfile)
        XCTAssertEqual(asset.colorProfile?.primaries, .acescg)
        XCTAssertEqual(asset.colorProfile?.transferFunction, .linear)
    }
}
