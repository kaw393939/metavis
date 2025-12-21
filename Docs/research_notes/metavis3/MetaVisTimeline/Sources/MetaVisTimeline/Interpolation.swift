import Foundation
import CoreGraphics
import simd

/// Protocol for types that can be interpolated between two values.
/// Used for animation and keyframing.
public protocol Interpolatable {
    /// Interpolates between `from` and `to` based on factor `t` (0.0 to 1.0).
    static func interpolate(from: Self, to: Self, t: Double) -> Self
    
    /// Interpolates using a cubic Hermite spline.
    /// - Parameters:
    ///   - from: The starting value (t=0).
    ///   - outTangent: The tangent/velocity at the start.
    ///   - to: The ending value (t=1).
    ///   - inTangent: The tangent/velocity at the end.
    ///   - t: The interpolation factor (0.0 to 1.0).
    static func interpolateCubic(from: Self, outTangent: Self, to: Self, inTangent: Self, t: Double) -> Self
}

public extension Interpolatable {
    static func interpolateCubic(from: Self, outTangent: Self, to: Self, inTangent: Self, t: Double) -> Self {
        // Fallback to linear if not implemented
        return interpolate(from: from, to: to, t: t)
    }
}

// MARK: - Standard Type Conformances

extension Float: Interpolatable {
    public static func interpolate(from: Float, to: Float, t: Double) -> Float {
        return from + (to - from) * Float(t)
    }
    
    public static func interpolateCubic(from: Float, outTangent: Float, to: Float, inTangent: Float, t: Double) -> Float {
        let t2 = Float(t * t)
        let t3 = Float(t * t * t)
        
        let h1 = 2*t3 - 3*t2 + 1
        let h2 = t3 - 2*t2 + Float(t)
        let h3 = -2*t3 + 3*t2
        let h4 = t3 - t2
        
        return h1*from + h2*outTangent + h3*to + h4*inTangent
    }
}

extension Double: Interpolatable {
    public static func interpolate(from: Double, to: Double, t: Double) -> Double {
        return from + (to - from) * t
    }
    
    public static func interpolateCubic(from: Double, outTangent: Double, to: Double, inTangent: Double, t: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        
        let h1 = 2*t3 - 3*t2 + 1
        let h2 = t3 - 2*t2 + t
        let h3 = -2*t3 + 3*t2
        let h4 = t3 - t2
        
        return h1*from + h2*outTangent + h3*to + h4*inTangent
    }
}

extension CGFloat: Interpolatable {
    public static func interpolate(from: CGFloat, to: CGFloat, t: Double) -> CGFloat {
        return from + (to - from) * CGFloat(t)
    }
    
    public static func interpolateCubic(from: CGFloat, outTangent: CGFloat, to: CGFloat, inTangent: CGFloat, t: Double) -> CGFloat {
        let t2 = CGFloat(t * t)
        let t3 = CGFloat(t * t * t)
        
        let h1 = 2*t3 - 3*t2 + 1
        let h2 = t3 - 2*t2 + CGFloat(t)
        let h3 = -2*t3 + 3*t2
        let h4 = t3 - t2
        
        return h1*from + h2*outTangent + h3*to + h4*inTangent
    }
}

extension CGPoint: Interpolatable {
    public static func interpolate(from: CGPoint, to: CGPoint, t: Double) -> CGPoint {
        return CGPoint(
            x: CGFloat.interpolate(from: from.x, to: to.x, t: t),
            y: CGFloat.interpolate(from: from.y, to: to.y, t: t)
        )
    }
}

extension Bool: Interpolatable {
    public static func interpolate(from: Bool, to: Bool, t: Double) -> Bool {
        // Boolean interpolation is always a step function.
        // Usually < 0.5 is from, >= 0.5 is to.
        return t < 0.5 ? from : to
    }
}

extension SIMD2<Float>: Interpolatable {
    public static func interpolate(from: SIMD2<Float>, to: SIMD2<Float>, t: Double) -> SIMD2<Float> {
        return from + (to - from) * Float(t)
    }
    
    public static func interpolateCubic(from: SIMD2<Float>, outTangent: SIMD2<Float>, to: SIMD2<Float>, inTangent: SIMD2<Float>, t: Double) -> SIMD2<Float> {
        let t2 = Float(t * t)
        let t3 = Float(t * t * t)
        
        let h1 = 2*t3 - 3*t2 + 1
        let h2 = t3 - 2*t2 + Float(t)
        let h3 = -2*t3 + 3*t2
        let h4 = t3 - t2
        
        return h1*from + h2*outTangent + h3*to + h4*inTangent
    }
}

extension SIMD3<Float>: Interpolatable {
    public static func interpolate(from: SIMD3<Float>, to: SIMD3<Float>, t: Double) -> SIMD3<Float> {
        return from + (to - from) * Float(t)
    }
    
    public static func interpolateCubic(from: SIMD3<Float>, outTangent: SIMD3<Float>, to: SIMD3<Float>, inTangent: SIMD3<Float>, t: Double) -> SIMD3<Float> {
        let t2 = Float(t * t)
        let t3 = Float(t * t * t)
        
        let h1 = 2*t3 - 3*t2 + 1
        let h2 = t3 - 2*t2 + Float(t)
        let h3 = -2*t3 + 3*t2
        let h4 = t3 - t2
        
        return h1*from + h2*outTangent + h3*to + h4*inTangent
    }
}

extension SIMD4<Float>: Interpolatable {
    public static func interpolate(from: SIMD4<Float>, to: SIMD4<Float>, t: Double) -> SIMD4<Float> {
        return from + (to - from) * Float(t)
    }
    
    public static func interpolateCubic(from: SIMD4<Float>, outTangent: SIMD4<Float>, to: SIMD4<Float>, inTangent: SIMD4<Float>, t: Double) -> SIMD4<Float> {
        let t2 = Float(t * t)
        let t3 = Float(t * t * t)
        
        let h1 = 2*t3 - 3*t2 + 1
        let h2 = t3 - 2*t2 + Float(t)
        let h3 = -2*t3 + 3*t2
        let h4 = t3 - t2
        
        return h1*from + h2*outTangent + h3*to + h4*inTangent
    }
}
