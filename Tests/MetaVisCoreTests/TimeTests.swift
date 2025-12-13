import XCTest
@testable import MetaVisCore

final class TimeTests: XCTestCase {
    
    func testRationalReduction() {
        let r = Rational(2, 4)
        XCTAssertEqual(r.numerator, 1)
        XCTAssertEqual(r.denominator, 2)
        
        let r2 = Rational(100, 100)
        XCTAssertEqual(r2.numerator, 1)
        XCTAssertEqual(r2.denominator, 1)
    }
    
    func testRationalArithmetic() {
        let r1 = Rational(1, 2)
        let r2 = Rational(1, 3)
        
        // 1/2 + 1/3 = 5/6
        let sum = r1 + r2
        XCTAssertEqual(sum.numerator, 5)
        XCTAssertEqual(sum.denominator, 6)
    }
    
    func testTimeSeconds() {
        let t = Time(seconds: 1.5)
        XCTAssertEqual(t.seconds, 1.5, accuracy: 0.000001)
        
        // 1.5 * 60000 = 90000 / 60000 = 3/2
        XCTAssertEqual(t.value.numerator, 3)
        XCTAssertEqual(t.value.denominator, 2)
    }
    
    func testTimeAddition() {
        let t1 = Time(seconds: 1.0)
        let t2 = Time(seconds: 0.5)
        let total = t1 + t2
        XCTAssertEqual(total.seconds, 1.5)
    }
}
