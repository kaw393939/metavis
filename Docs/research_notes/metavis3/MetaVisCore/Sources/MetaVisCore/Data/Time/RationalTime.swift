import Foundation

/// Represents a point in time or a duration as a rational number (fraction).
/// This ensures precise timing for both audio and video without floating-point drift.
/// Modeled after CMTime but platform-independent.
public struct RationalTime: Codable, Equatable, Comparable, Sendable, Hashable {
    /// The numerator of the rational time (the number of time units).
    public let value: Int64
    
    /// The denominator of the rational time (the number of time units per second).
    public let timescale: Int32
    
    public init(value: Int64, timescale: Int32) {
        self.value = value
        self.timescale = timescale
    }
    
    /// Creates a time from a Double (seconds). Note: May lose precision.
    public init(seconds: Double, preferredTimescale: Int32 = 60000) {
        self.value = Int64(seconds * Double(preferredTimescale))
        self.timescale = preferredTimescale
    }
    
    /// The time value in seconds as a Double.
    public var seconds: Double {
        return Double(value) / Double(timescale)
    }
    
    // MARK: - Equatable
    
    public static func == (lhs: RationalTime, rhs: RationalTime) -> Bool {
        // Semantic equality: 1/2 == 2/4
        if lhs.timescale == rhs.timescale {
            return lhs.value == rhs.value
        }
        
        // Simplify both to compare
        // Note: This is safer than cross-multiplication which might overflow Int64
        let lhsSimple = lhs.simplified()
        let rhsSimple = rhs.simplified()
        
        return lhsSimple.value == rhsSimple.value && lhsSimple.timescale == rhsSimple.timescale
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        // Must be consistent with ==
        let simple = self.simplified()
        hasher.combine(simple.value)
        hasher.combine(simple.timescale)
    }
    
    // MARK: - Common Constants
    
    public static let zero = RationalTime(value: 0, timescale: 1)
    public static let indefinite = RationalTime(value: 0, timescale: 0) // Sentinel
    
    // MARK: - Comparable
    
    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        // Cross-multiply to compare: a/b < c/d  <=>  ad < bc
        // Note: This can overflow Int64 if values are huge.
        
        if lhs.timescale == rhs.timescale {
            return lhs.value < rhs.value
        }
        
        // Use Euclidean algorithm to compare fractions without overflow
        // a/b < c/d
        let a = lhs.value
        let b = Int64(lhs.timescale)
        let c = rhs.value
        let d = Int64(rhs.timescale)
        
        return compareFractions(n1: a, d1: b, n2: c, d2: d)
    }
    
    private static func compareFractions(n1: Int64, d1: Int64, n2: Int64, d2: Int64) -> Bool {
        // Handle signs
        // (Assuming positive timescales for now as per struct definition, but values can be negative)
        // If signs differ, it's easy.
        if n1 < 0 && n2 >= 0 { return true }
        if n1 >= 0 && n2 < 0 { return false }
        if n1 < 0 && n2 < 0 {
            // Both negative: -x < -y <=> x > y
            return compareFractions(n1: -n2, d1: d2, n2: -n1, d2: d1)
        }
        
        // Both positive
        let q1 = n1 / d1
        let q2 = n2 / d2
        
        if q1 != q2 {
            return q1 < q2
        }
        
        let r1 = n1 % d1
        let r2 = n2 % d2
        
        if r2 == 0 { return false } // n2/d2 is integer, n1/d1 >= n2/d2
        if r1 == 0 { return true }  // n1/d1 is integer, n1/d1 < n2/d2
        
        // Compare r1/d1 < r2/d2 <=> d2/r2 < d1/r1
        return compareFractions(n1: d2, d1: r2, n2: d1, d2: r1)
    }
    
    // MARK: - Arithmetic
    
    public static func + (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        if lhs.timescale == rhs.timescale {
            // Check for overflow in simple addition
            let (sum, overflow) = lhs.value.addingReportingOverflow(rhs.value)
            if !overflow {
                return RationalTime(value: sum, timescale: lhs.timescale)
            }
            // Fallback to simplified addition if simple add overflows
        }
        
        // Use LCM to find the common denominator
        let commonDenominator = lcm(Int64(lhs.timescale), Int64(rhs.timescale))
        
        // Check for overflow during scaling
        // value = old_value * (new_denom / old_denom)
        let scaleL = commonDenominator / Int64(lhs.timescale)
        let scaleR = commonDenominator / Int64(rhs.timescale)
        
        let (lhsScaled, overflowL) = lhs.value.multipliedReportingOverflow(by: scaleL)
        let (rhsScaled, overflowR) = rhs.value.multipliedReportingOverflow(by: scaleR)
        
        if overflowL || overflowR {
            // Fallback: Use Double math to approximate
            let sumSeconds = lhs.seconds + rhs.seconds
            
            // Calculate max safe timescale to avoid Int64 overflow
            // value = seconds * timescale <= Int64.max
            // timescale <= Int64.max / seconds
            let maxSafeTimescale = sumSeconds > 0 ? Int64(Double(Int64.max) / sumSeconds) : Int64(Int32.max)
            let targetTimescale = min(min(Int64(Int32.max), commonDenominator), maxSafeTimescale)
            
            // Ensure timescale is at least 1
            let finalTimescale = max(1, Int32(targetTimescale))
            
            return RationalTime(seconds: sumSeconds, preferredTimescale: finalTimescale)
        }
        
        let (newValue, overflowAdd) = lhsScaled.addingReportingOverflow(rhsScaled)
        
        if overflowAdd {
             // Fallback
            let sumSeconds = lhs.seconds + rhs.seconds
            let maxSafeTimescale = sumSeconds > 0 ? Int64(Double(Int64.max) / sumSeconds) : Int64(Int32.max)
            let targetTimescale = min(min(Int64(Int32.max), commonDenominator), maxSafeTimescale)
            let finalTimescale = max(1, Int32(targetTimescale))
            return RationalTime(seconds: sumSeconds, preferredTimescale: finalTimescale)
        }
        
        return RationalTime.createSimplified(value: newValue, timescale: commonDenominator)
    }
    
    public static func - (lhs: RationalTime, rhs: RationalTime) -> RationalTime {
        if lhs.timescale == rhs.timescale {
            return RationalTime(value: lhs.value - rhs.value, timescale: lhs.timescale)
        }
        
        let commonDenominator = lcm(Int64(lhs.timescale), Int64(rhs.timescale))
        let lhsScaled = lhs.value * (commonDenominator / Int64(lhs.timescale))
        let rhsScaled = rhs.value * (commonDenominator / Int64(rhs.timescale))
        
        let newValue = lhsScaled - rhsScaled
        
        return RationalTime.createSimplified(value: newValue, timescale: commonDenominator)
    }
    
    /// Creates a RationalTime by simplifying the given value and timescale.
    /// Handles cases where the input timescale might exceed Int32.max by simplifying first.
    private static func createSimplified(value: Int64, timescale: Int64) -> RationalTime {
        if value == 0 { return RationalTime(value: 0, timescale: 1) }
        
        let common = gcd(abs(value), timescale)
        let simplifiedValue = value / common
        let simplifiedTimescale = timescale / common
        
        // If after simplification it still doesn't fit in Int32, we have to clamp or fail.
        // For a robust system, we might lose precision here.
        guard simplifiedTimescale <= Int32.max else {
            // Fallback: Rescale to fit Int32.max
            // This loses precision but prevents crashing.
            let scale = Double(Int32.max) / Double(simplifiedTimescale)
            let clampedValue = Int64(Double(simplifiedValue) * scale)
            return RationalTime(value: clampedValue, timescale: Int32.max)
        }
        
        return RationalTime(value: simplifiedValue, timescale: Int32(simplifiedTimescale))
    }
    
    /// Returns a simplified version of the fraction (e.g. 2/4 -> 1/2)
    public func simplified() -> RationalTime {
        return RationalTime.createSimplified(value: value, timescale: Int64(timescale))
    }
    
    // MARK: - Helpers
    
    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        let r = a % b
        if r != 0 {
            return gcd(b, r)
        } else {
            return b
        }
    }
    
    private static func lcm(_ a: Int64, _ b: Int64) -> Int64 {
        if a == 0 || b == 0 { return 0 }
        return abs(a * b) / gcd(a, b)
    }
    
    // Instance method wrapper for existing code compatibility if needed, 
    // though static is preferred for internal use.
    private func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        return RationalTime.gcd(a, b)
    }
}

extension RationalTime: CustomStringConvertible {
    public var description: String {
        return "\(value)/\(timescale) (\(String(format: "%.3f", seconds))s)"
    }
}
