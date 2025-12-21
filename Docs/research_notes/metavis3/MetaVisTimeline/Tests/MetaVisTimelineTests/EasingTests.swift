import XCTest
@testable import MetaVisTimeline

final class EasingTests: XCTestCase {
    
    func testLinear() {
        XCTAssertEqual(Easing.linear.apply(0.0), 0.0)
        XCTAssertEqual(Easing.linear.apply(0.5), 0.5)
        XCTAssertEqual(Easing.linear.apply(1.0), 1.0)
    }
    
    func testEaseInQuad() {
        XCTAssertEqual(Easing.easeInQuad.apply(0.0), 0.0)
        XCTAssertEqual(Easing.easeInQuad.apply(0.5), 0.25)
        XCTAssertEqual(Easing.easeInQuad.apply(1.0), 1.0)
    }
    
    func testEaseOutQuad() {
        XCTAssertEqual(Easing.easeOutQuad.apply(0.0), 0.0)
        XCTAssertEqual(Easing.easeOutQuad.apply(0.5), 0.75) // 0.5 * (2 - 0.5) = 0.5 * 1.5 = 0.75
        XCTAssertEqual(Easing.easeOutQuad.apply(1.0), 1.0)
    }
    
    func testEaseInOutQuad() {
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.0), 0.0)
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.25), 0.125) // 2 * 0.25^2 = 2 * 0.0625 = 0.125
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.5), 0.5) // Boundary
        XCTAssertEqual(Easing.easeInOutQuad.apply(0.75), 0.875) // -1 + (4 - 1.5) * 0.75 = -1 + 2.5 * 0.75 = -1 + 1.875 = 0.875
        XCTAssertEqual(Easing.easeInOutQuad.apply(1.0), 1.0)
    }
    
    func testEaseInCubic() {
        XCTAssertEqual(Easing.easeInCubic.apply(0.5), 0.125)
    }
    
    func testEaseOutCubic() {
        XCTAssertEqual(Easing.easeOutCubic.apply(0.5), 0.875)
    }
    
    func testEaseInOutCubic() {
        XCTAssertEqual(Easing.easeInOutCubic.apply(0.5), 0.5)
    }
    
    func testEaseOutBack() {
        XCTAssertEqual(Easing.easeOutBack.apply(0.0), 0.0, accuracy: 1e-10)
        XCTAssertEqual(Easing.easeOutBack.apply(1.0), 1.0, accuracy: 1e-10)
        // Check overshoot
        // t=0.5 -> t1=-0.5. 1 + 2.70158*(-0.125) + 1.70158*(0.25)
        // 1 - 0.3376975 + 0.425395 = 1.087...
        XCTAssertGreaterThan(Easing.easeOutBack.apply(0.5), 1.0)
    }
    
    func testEaseOutElastic() {
        XCTAssertEqual(Easing.easeOutElastic.apply(0.0), 0.0)
        XCTAssertEqual(Easing.easeOutElastic.apply(1.0), 1.0)
    }
}
