import XCTest
import MetaVisCore

final class SnapshotVerificationTests: XCTestCase {
    
    func testSnapshotRoundtrip() throws {
        let width = 64
        let height = 64
        let pixelCount = width * height
        
        // 1. Create Synthetic Image (Red Gradient)
        var originalBuffer = [Float](repeating: 0, count: pixelCount * 4)
        for i in 0..<pixelCount {
            let offset = i * 4
            let u = Float(i % width) / Float(width)
            originalBuffer[offset + 0] = u         // R
            originalBuffer[offset + 1] = 0.0       // G
            originalBuffer[offset + 2] = 0.0       // B
            originalBuffer[offset + 3] = 1.0       // A
        }
        
        let helper = SnapshotHelper()

        let goldenName = "Test_RedGradient"
        if let loadedBuffer = try helper.loadGolden(name: goldenName) {
            let result = ImageComparator.compare(bufferA: originalBuffer, bufferB: loadedBuffer, tolerance: 1e-4)
            switch result {
            case .match:
                XCTAssertTrue(true)
            case .different(let maxDelta, let avgDelta):
                if SnapshotHelper.shouldRecordGoldens {
                    let url = try helper.saveGolden(name: goldenName, buffer: originalBuffer, width: width, height: height)
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    return
                } else {
                    XCTFail("Roundtrip golden mismatch for \(goldenName).exr max=\(maxDelta) avg=\(avgDelta) (set RECORD_GOLDENS=1 to update)")
                }
            }
        } else {
            if SnapshotHelper.shouldRecordGoldens {
                let url = try helper.saveGolden(name: goldenName, buffer: originalBuffer, width: width, height: height)
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                return
            } else {
                XCTFail("Missing golden \(goldenName).exr (re-run with RECORD_GOLDENS=1 to record)")
            }
        }
    }
}
