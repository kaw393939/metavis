import XCTest
@testable import MetaVisTimeline

final class InterpolationTests: XCTestCase {
    
    func testFloatInterpolation() {
        XCTAssertEqual(Float.interpolate(from: 0, to: 10, t: 0.5), 5.0)
        XCTAssertEqual(Float.interpolate(from: 0, to: 10, t: 0.0), 0.0)
        XCTAssertEqual(Float.interpolate(from: 0, to: 10, t: 1.0), 10.0)
    }
    
    func testDoubleInterpolation() {
        XCTAssertEqual(Double.interpolate(from: 0, to: 10, t: 0.5), 5.0)
    }
    
    func testCGFloatInterpolation() {
        XCTAssertEqual(CGFloat.interpolate(from: 0, to: 10, t: 0.5), 5.0)
    }
    
    func testCGPointInterpolation() {
        let p1 = CGPoint(x: 0, y: 0)
        let p2 = CGPoint(x: 10, y: 20)
        let mid = CGPoint.interpolate(from: p1, to: p2, t: 0.5)
        
        XCTAssertEqual(mid.x, 5.0)
        XCTAssertEqual(mid.y, 10.0)
    }
    
    func testBoolInterpolation() {
        XCTAssertFalse(Bool.interpolate(from: false, to: true, t: 0.4))
        XCTAssertTrue(Bool.interpolate(from: false, to: true, t: 0.5))
        XCTAssertTrue(Bool.interpolate(from: false, to: true, t: 0.6))
    }
    
    func testCubicInterpolation() {
        // Simple linear case with 0 tangents
        // h1=0.5, h2=0.125, h3=0.5, h4=-0.125
        // 0 + 0 + 10*0.5 + 0 = 5.0
        let val = Double.interpolateCubic(from: 0, outTangent: 0, to: 10, inTangent: 0, t: 0.5)
        XCTAssertEqual(val, 5.0)
        
        // Case with tangents
        // from=0, to=10. Linear slope is 10.
        // If tangents are 10, it should be exactly linear.
        let linearVal = Double.interpolateCubic(from: 0, outTangent: 10, to: 10, inTangent: 10, t: 0.5)
        XCTAssertEqual(linearVal, 5.0, accuracy: 0.0001)
    }
}
