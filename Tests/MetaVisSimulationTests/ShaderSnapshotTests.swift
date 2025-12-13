import XCTest
import MetaVisCore
import simd

final class ShaderSnapshotTests: XCTestCase {
    
    // Generates a Golden Image for the ACES Tonemapper using the CPU Reference.
    func testGenerateGolden_ACESTonemap() throws {
        let width = 256
        let height = 64
        let pixelCount = width * height
        
        var buffer = [Float](repeating: 0, count: pixelCount * 4)
        
        for i in 0..<pixelCount {
            let x = i % width
            // 0 to 5.0 exposure ramp
            let u = (Float(x) / Float(width)) * 5.0
            
            let linearIn = SIMD3<Float>(u, u, u) // Grayscale ramp
            
            // Apply Tone Map
            let tonemapped = ColorScienceReference.acesFilm(linearIn)
            
            let offset = i * 4
            buffer[offset + 0] = tonemapped.x
            buffer[offset + 1] = tonemapped.y
            buffer[offset + 2] = tonemapped.z
            buffer[offset + 3] = 1.0
        }
        
        let helper = SnapshotHelper()
        let goldenName = "Golden_Reference_ACES"

        if let existing = try helper.loadGolden(name: goldenName) {
            // Allow tiny floating-point deltas from EXR encode/decode and platform math.
            let compare = ImageComparator.compare(bufferA: buffer, bufferB: existing, tolerance: 1e-6)
            switch compare {
            case .match:
                XCTAssertTrue(true)
            case .different(let maxDelta, let avgDelta):
                if SnapshotHelper.shouldRecordGoldens {
                    let url = try helper.saveGolden(name: goldenName, buffer: buffer, width: width, height: height)
                    print("Updated Golden: \(url.path)")
                    throw XCTSkip("Golden updated; re-run to verify")
                } else {
                    XCTFail("Golden mismatch for \(goldenName).exr max=\(maxDelta) avg=\(avgDelta) (set RECORD_GOLDENS=1 to update)")
                }
            }
        } else {
            if SnapshotHelper.shouldRecordGoldens {
                let url = try helper.saveGolden(name: goldenName, buffer: buffer, width: width, height: height)
                print("Generated Golden: \(url.path)")
                throw XCTSkip("Golden recorded; re-run to verify")
            } else {
                XCTFail("Missing golden \(goldenName).exr (re-run with RECORD_GOLDENS=1 to record)")
            }
        }
    }
}
