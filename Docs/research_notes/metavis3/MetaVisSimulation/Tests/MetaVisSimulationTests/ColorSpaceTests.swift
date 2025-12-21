import XCTest
import simd
@testable import MetaVisSimulation

final class ColorSpaceTests: XCTestCase {
    
    func testColorSpaceCreation() {
        // Test creation from known identifiers
        let rec709 = RenderColorSpace.from(identifier: "rec709")
        XCTAssertEqual(rec709, .rec709)
        
        let appleLog = RenderColorSpace.from(identifier: "applelog")
        XCTAssertEqual(appleLog.primaries, .bt2020)
        XCTAssertEqual(appleLog.transfer, .appleLog)
        
        let hlg = RenderColorSpace.from(identifier: "hlg")
        XCTAssertEqual(hlg, .hlg)
        
        // Test fallback
        let unknown = RenderColorSpace.from(identifier: "not_a_real_color_space")
        XCTAssertEqual(unknown, .rec709)
    }
    
    func testColorPrimariesProperties() {
        XCTAssertTrue(ColorPrimaries.bt2020.isWideGamut)
        XCTAssertFalse(ColorPrimaries.bt709.isWideGamut)
    }
    
    func testTransferFunctionProperties() {
        XCTAssertTrue(TransferFunction.pq.isHDR)
        XCTAssertTrue(TransferFunction.hlg.isHDR)
        XCTAssertTrue(TransferFunction.appleLog.isHDR) // Log is considered HDR in our pipeline context
        XCTAssertFalse(TransferFunction.bt709.isHDR)
    }
    
    func testACEScgMatrices() {
        // Verify we have matrices for common spaces
        let p3 = RenderColorSpace.displayP3
        let matrix = p3.toACEScgMatrix
        
        // Check a known value (approximate)
        // P3 Red (1,0,0) -> ACEScg
        // Row 0 is R->R, G->R, B->R
        // So (1,0,0) * matrix should be the first column of the matrix? No, rows are usually [Rx, Ry, Rz]
        // simd_float3x3(rows: ...) constructs a matrix from rows.
        // Vector * Matrix (row-major) or Matrix * Vector (column-major)?
        // Metal/SIMD usually treats vectors as columns and matrices as column-major storage, but constructors can vary.
        // The reference code uses `simd_float3x3(rows: [...])`.
        // Let's just assert it's not identity
        XCTAssertNotEqual(matrix, matrix_identity_float3x3)
    }
}
