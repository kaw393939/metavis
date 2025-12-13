import Foundation

/// Represents a rational number (fraction) for precise time calculations.
public struct Rational: Codable, Sendable, Equatable, Comparable {
    public let numerator: Int64
    public let denominator: Int64
    
    public init(_ numerator: Int64, _ denominator: Int64) {
        // Find GCD for simplification
        func gcd(_ a: Int64, _ b: Int64) -> Int64 {
            let r = a % b
            return r != 0 ? gcd(b, r) : b
        }
        
        // Ensure denominator is positive
        let common = gcd(abs(numerator), abs(denominator))
        if denominator < 0 {
            self.numerator = -numerator / common
            self.denominator = -denominator / common
        } else {
            self.numerator = numerator / common
            self.denominator = denominator / common
        }
    }
    
    public static func < (lhs: Rational, rhs: Rational) -> Bool {
        return (Double(lhs.numerator) / Double(lhs.denominator)) < (Double(rhs.numerator) / Double(rhs.denominator))
    }
    
    public static func + (lhs: Rational, rhs: Rational) -> Rational {
        let a = lhs.numerator
        let b = lhs.denominator
        let c = rhs.numerator
        let d = rhs.denominator
        
        // a/b + c/d = (ad + bc) / bd
        let num = (a * d) + (b * c)
        let den = b * d
        return Rational(num, den)
    }
    
    public static func - (lhs: Rational, rhs: Rational) -> Rational {
        let a = lhs.numerator
        let b = lhs.denominator
        let c = rhs.numerator
        let d = rhs.denominator
        
        // a/b - c/d = (ad - bc) / bd
        let num = (a * d) - (b * c)
        let den = b * d
        return Rational(num, den)
    }
}

/// Represents a point in time with high precision.
public struct Time: Codable, Sendable, Equatable, Comparable {
    public let value: Rational
    
    public init(_ value: Rational) {
        self.value = value
    }
    
    public init(seconds: Double) {
        // Convert to 1/60000 precision
        let scale: Int64 = 60000
        let num = Int64(seconds * Double(scale))
        self.value = Rational(num, scale)
    }
    
    public static let zero = Time(Rational(0, 1))
    
    // MARK: - Comparable
    public static func < (lhs: Time, rhs: Time) -> Bool {
        return lhs.value < rhs.value
    }
    
    // MARK: - Arithmetic
    public static func + (lhs: Time, rhs: Time) -> Time {
        // a/b + c/d = (ad + bc) / bd
        let a = lhs.value.numerator
        let b = lhs.value.denominator
        let c = rhs.value.numerator
        let d = rhs.value.denominator
        
        let num = (a * d) + (b * c)
        let den = b * d
        return Time(Rational(num, den))
    }
    
    public static func - (lhs: Time, rhs: Time) -> Time {
        let a = lhs.value.numerator
        let b = lhs.value.denominator
        let c = rhs.value.numerator
        let d = rhs.value.denominator
        
        let num = (a * d) - (b * c)
        let den = b * d
        return Time(Rational(num, den))
    }
    
    public var seconds: Double {
        return Double(value.numerator) / Double(value.denominator)
    }
}

/// Represents a span of time.
public struct TimeRange: Codable, Sendable, Equatable {
    public let start: Time
    public let duration: Time
    
    public var end: Time {
        return start + duration
    }
    
    public init(start: Time, duration: Time) {
        self.start = start
        self.duration = duration
    }
    
    public func contains(_ time: Time) -> Bool {
        return time >= start && time < end
    }
}
