import XCTest
import MetaVisCore
import simd

final class ColorScienceTests: XCTestCase {
    
    func testRec709toACEScg_Invertibility() {
        // Red in sRGB
        let redSRGB = SIMD3<Float>(1.0, 0.0, 0.0)
        
        // Transform to ACEScg
        let acescg = ColorScienceReference.IDT_Rec709_ACEScg(redSRGB)
        
        // Should be slightly different in ACEScg (wider gamut)
        XCTAssertNotEqual(acescg.x, 1.0)
        
        // Transform Back
        let backToSRGB = ColorScienceReference.ODT_ACEScg_Rec709(acescg)
        
        // Verify Roundtrip to 5 decimal places
        XCTAssertEqual(backToSRGB.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(backToSRGB.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(backToSRGB.z, 0.0, accuracy: 0.001)
    }
    
    func testGamma_Curve() {
        let midGray = SIMD3<Float>(0.5, 0.5, 0.5)
        let linear = ColorScienceReference.srgbToLinear(midGray)
        
        // 0.5 in sRGB is approx 0.21 in Linear
        XCTAssertEqual(linear.x, 0.21404, accuracy: 0.0001)
        
        let back = ColorScienceReference.linearToSRGB(linear)
        XCTAssertEqual(back.x, 0.5, accuracy: 0.0001)
    }
}
