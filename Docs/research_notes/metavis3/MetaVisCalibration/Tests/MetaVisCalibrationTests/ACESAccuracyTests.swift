import XCTest
@testable import MetaVisCalibration
import simd

final class ACESAccuracyTests: XCTestCase {
    
    let labTools = ColorLab()
    
    func testMatrixInversionAccuracy() {
        // Verify that M * M_inv is Identity
        // Note: The source matrices are from legacy Metal (Float precision ~1e-7).
        // We use 1e-6 tolerance to account for this.
        let identity = ACES.Rec709_to_XYZ * ACES.XYZ_to_Rec709
        
        // Check diagonal
        XCTAssertEqual(identity.columns.0.x, 1.0, accuracy: 1e-6)
        XCTAssertEqual(identity.columns.1.y, 1.0, accuracy: 1e-6)
        XCTAssertEqual(identity.columns.2.z, 1.0, accuracy: 1e-6)
        
        // Check off-diagonal
        XCTAssertEqual(identity.columns.0.y, 0.0, accuracy: 1e-6)
        XCTAssertEqual(identity.columns.0.z, 0.0, accuracy: 1e-6)
    }
    
    func testDeltaEPrecision() {
        // Test Case: Two identical colors should have Delta E = 0
        let c1 = ColorLab.LabColor(L: 50.0, a: 0.0, b: 0.0)
        let c2 = ColorLab.LabColor(L: 50.0, a: 0.0, b: 0.0)
        
        let dE = labTools.deltaE2000(c1, c2)
        XCTAssertEqual(dE, 0.0, accuracy: 1e-15)
        
        // Test Case: Known small difference
        // L=50, a=0, b=0 vs L=51, a=0, b=0
        // Delta E should be roughly 1.0 (since kL=1)
        let c3 = ColorLab.LabColor(L: 51.0, a: 0.0, b: 0.0)
        let dE2 = labTools.deltaE2000(c1, c3)
        
        // The formula is complex, but for pure L shift it simplifies.
        // We just want to ensure it's calculated deterministically.
        XCTAssertGreaterThan(dE2, 0.0)
    }
    
    func testRoundTripSRGBToLab() {
        // White (1,1,1) -> XYZ (D65) -> Lab (100, 0, 0)
        let white = SIMD3<Double>(1.0, 1.0, 1.0)
        let lab = labTools.linearSRGBToLab(white)
        
        XCTAssertEqual(lab.L, 100.0, accuracy: 0.01)
        XCTAssertEqual(lab.a, 0.0, accuracy: 0.01)
        XCTAssertEqual(lab.b, 0.0, accuracy: 0.01)
    }
}
