import Foundation

/// Represents a rational number (fraction) for precise time calculations.
public struct Rational: Codable, Sendable, Equatable, Comparable {
    public let numerator: Int64
    public let denominator: Int64
    
    public init(_ numerator: Int64, _ denominator: Int64) {
        // Ensure denominator is not zero.
        precondition(denominator != 0, "Rational denominator must be non-zero")

        // Fast paths.
        if numerator == 0 {
            self.numerator = 0
            self.denominator = 1
            return
        }
        if denominator == 1 {
            self.numerator = numerator
            self.denominator = 1
            return
        }
        if denominator == -1 {
            self.numerator = -numerator
            self.denominator = 1
            return
        }

        // Iterative Euclidean GCD (faster than recursion for hot paths).
        @inline(__always)
        func gcd(_ aIn: Int64, _ bIn: Int64) -> Int64 {
            var a = aIn
            var b = bIn
            while b != 0 {
                let r = a % b
                a = b
                b = r
            }
            return a == 0 ? 1 : a
        }

        // Ensure denominator is positive.
        let a = numerator
        let b = denominator
        let common = gcd(abs(a), abs(b))
        if b < 0 {
            self.numerator = (-a) / common
            self.denominator = (-b) / common
        } else {
            self.numerator = a / common
            self.denominator = b / common
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

        // Fast path: same denominator (common for fixed-tick timelines).
        if b == d {
            return Rational(a + c, b)
        }
        
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

        // Fast path: same denominator (common for fixed-tick timelines).
        if b == d {
            return Rational(a - c, b)
        }
        
        // a/b - c/d = (ad - bc) / bd
        let num = (a * d) - (b * c)
        let den = b * d
        return Rational(num, den)
    }
}

/// Represents a point in time with high precision.
public struct Time: Codable, Sendable, Equatable, Comparable {
    private enum Storage: Sendable, Equatable {
        case ticks(Int64)        // fixed-point 1/60000s
        case rational(Rational)  // fallback for non-representable values
    }

    private static let tickScale: Int64 = 60000
    private let storage: Storage

    /// Canonical rational value (reduced). Kept for API compatibility and Codable stability.
    public var value: Rational {
        switch storage {
        case .ticks(let t):
            return Rational(t, Self.tickScale)
        case .rational(let r):
            return r
        }
    }

    public init(_ value: Rational) {
        // If the rational can be represented exactly as 1/60000 ticks, keep the fast path.
        let scale = Self.tickScale
        let n = value.numerator
        let d = value.denominator
        // Avoid overflow: prefer dividing first when possible.
        if d != 0 {
            let g = Self.gcd(abs(d), abs(scale))
            let d1 = d / g
            let s1 = scale / g
            if d1 != 0, n % d1 == 0 {
                self.storage = .ticks((n / d1) * s1)
                return
            }
        }
        self.storage = .rational(value)
    }

    public init(seconds: Double) {
        let scale = Self.tickScale
        let num = Int64(seconds * Double(scale))
        self.storage = .ticks(num)
    }

    public static let zero = Time(seconds: 0)

    private static func gcd(_ aIn: Int64, _ bIn: Int64) -> Int64 {
        var a = aIn
        var b = bIn
        while b != 0 {
            let r = a % b
            a = b
            b = r
        }
        return a == 0 ? 1 : a
    }
    
    // MARK: - Comparable
    public static func < (lhs: Time, rhs: Time) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.ticks(let a), .ticks(let b)):
            return a < b
        default:
            return lhs.value < rhs.value
        }
    }
    
    // MARK: - Arithmetic
    public static func + (lhs: Time, rhs: Time) -> Time {
        switch (lhs.storage, rhs.storage) {
        case (.ticks(let a), .ticks(let b)):
            return Time(storage: .ticks(a + b))
        default:
            return Time(lhs.value + rhs.value)
        }
    }
    
    public static func - (lhs: Time, rhs: Time) -> Time {
        switch (lhs.storage, rhs.storage) {
        case (.ticks(let a), .ticks(let b)):
            return Time(storage: .ticks(a - b))
        default:
            return Time(lhs.value - rhs.value)
        }
    }
    
    public var seconds: Double {
        switch storage {
        case .ticks(let t):
            return Double(t) / Double(Self.tickScale)
        case .rational(let r):
            return Double(r.numerator) / Double(r.denominator)
        }
    }

    // MARK: - Codable (preserve existing payload shape)

    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let r = try c.decode(Rational.self, forKey: .value)
        self.init(r)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(self.value, forKey: .value)
    }

    private init(storage: Storage) {
        self.storage = storage
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
