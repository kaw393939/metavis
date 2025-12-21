import XCTest
@testable import MetaVisCore

final class VisualAnalysisTests: XCTestCase {
    
    func testInitialization() {
        let rect = Rect(x: 0, y: 0, width: 0.5, height: 0.5)
        let seg = SegmentationLayer(label: "Person", confidence: 0.9, bounds: rect)
        let obj = DetectedObject(label: "Car", confidence: 0.8, bounds: rect)
        let sal = SaliencyRegion(bounds: rect, value: 1.0)
        
        let analysis = VisualAnalysis(
            segmentation: [seg],
            objects: [obj],
            saliency: [sal],
            engineVersion: "2.0"
        )
        
        XCTAssertEqual(analysis.segmentation.count, 1)
        XCTAssertEqual(analysis.objects.first?.label, "Car")
        XCTAssertEqual(analysis.engineVersion, "2.0")
    }
    
    func testCodable() throws {
        let rect = Rect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let obj = DetectedObject(label: "Dog", confidence: 0.95, bounds: rect)
        let analysis = VisualAnalysis(objects: [obj])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(analysis)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VisualAnalysis.self, from: data)
        
        XCTAssertEqual(decoded.objects.first?.label, "Dog")
        XCTAssertEqual(decoded.objects.first?.bounds.width, 0.8)
    }
    
    func testEquality() {
        let a1 = VisualAnalysis(engineVersion: "1.0")
        let a2 = VisualAnalysis(engineVersion: "1.0")
        let a3 = VisualAnalysis(engineVersion: "1.1")
        
        XCTAssertEqual(a1, a2)
        XCTAssertNotEqual(a1, a3)
    }
}
