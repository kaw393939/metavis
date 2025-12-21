import Foundation

/// Easing functions for smooth animation interpolation
/// Based on Robert Penner's easing equations
public enum Easing: Sendable, Codable, Equatable {
    case linear
    case quadraticIn, quadraticOut, quadraticInOut
    case cubicIn, cubicOut, cubicInOut
    case quarticIn, quarticOut, quarticInOut
    case quinticIn, quinticOut, quinticInOut
    case sineIn, sineOut, sineInOut
    case exponentialIn, exponentialOut, exponentialInOut
    case circularIn, circularOut, circularInOut
    case backIn, backOut, backInOut
    case elasticIn, elasticOut, elasticInOut
    case bounceIn, bounceOut, bounceInOut
    case cubicBezier(Double, Double, Double, Double)

    /// Evaluate easing function at time t (0.0 to 1.0)
    /// Returns interpolated value (typically 0.0 to 1.0, but can overshoot for back/elastic)
    public func evaluate(_ t: Double) -> Double {
        let t = max(0.0, min(1.0, t)) // Clamp to valid range

        switch self {
        case .linear:
            return t

        // MARK: - Quadratic

        case .quadraticIn:
            return EasingFunctions.quadraticIn(t)

        case .quadraticOut:
            return EasingFunctions.quadraticOut(t)

        case .quadraticInOut:
            return EasingFunctions.quadraticInOut(t)

        // MARK: - Cubic

        case .cubicIn:
            return EasingFunctions.cubicIn(t)

        case .cubicOut:
            return EasingFunctions.cubicOut(t)

        case .cubicInOut:
            return EasingFunctions.cubicInOut(t)

        // MARK: - Quartic

        case .quarticIn:
            return EasingFunctions.quarticIn(t)

        case .quarticOut:
            return EasingFunctions.quarticOut(t)

        case .quarticInOut:
            return EasingFunctions.quarticInOut(t)

        // MARK: - Quintic

        case .quinticIn:
            return EasingFunctions.quinticIn(t)

        case .quinticOut:
            return EasingFunctions.quinticOut(t)

        case .quinticInOut:
            return EasingFunctions.quinticInOut(t)

        // MARK: - Sine

        case .sineIn:
            return EasingFunctions.sineIn(t)

        case .sineOut:
            return EasingFunctions.sineOut(t)

        case .sineInOut:
            return EasingFunctions.sineInOut(t)

        // MARK: - Exponential

        case .exponentialIn:
            return EasingFunctions.exponentialIn(t)

        case .exponentialOut:
            return EasingFunctions.exponentialOut(t)

        case .exponentialInOut:
            return EasingFunctions.exponentialInOut(t)

        // MARK: - Circular

        case .circularIn:
            return EasingFunctions.circularIn(t)

        case .circularOut:
            return EasingFunctions.circularOut(t)

        case .circularInOut:
            return EasingFunctions.circularInOut(t)

        // MARK: - Back

        case .backIn:
            return EasingFunctions.backIn(t)

        case .backOut:
            return EasingFunctions.backOut(t)

        case .backInOut:
            return EasingFunctions.backInOut(t)

        // MARK: - Elastic

        case .elasticIn:
            return EasingFunctions.elasticIn(t)

        case .elasticOut:
            return EasingFunctions.elasticOut(t)

        case .elasticInOut:
            return EasingFunctions.elasticInOut(t)

        // MARK: - Bounce

        case .bounceIn:
            return EasingFunctions.bounceIn(t)

        case .bounceOut:
            return EasingFunctions.bounceOut(t)

        case .bounceInOut:
            return EasingFunctions.bounceInOut(t)

        // MARK: - Cubic Bezier

        case let .cubicBezier(x1, y1, x2, y2):
            return EasingFunctions.cubicBezier(t, x1: x1, y1: y1, x2: x2, y2: y2)
        }
    }
}

// MARK: - Interpolation Helper

public extension Easing {
    /// Interpolate between two values using this easing function
    func interpolate(from start: Double, to end: Double, at t: Double) -> Double {
        let easedT = evaluate(t)
        return start + (end - start) * easedT
    }
}

// MARK: - Preset Bezier Curves

public extension Easing {
    /// CSS ease: cubic-bezier(0.25, 0.1, 0.25, 1.0)
    static let ease = Easing.cubicBezier(0.25, 0.1, 0.25, 1.0)

    /// CSS ease-in: cubic-bezier(0.42, 0, 1.0, 1.0)
    static let easeIn = Easing.cubicBezier(0.42, 0.0, 1.0, 1.0)

    /// CSS ease-out: cubic-bezier(0, 0, 0.58, 1.0)
    static let easeOut = Easing.cubicBezier(0.0, 0.0, 0.58, 1.0)

    /// CSS ease-in-out: cubic-bezier(0.42, 0, 0.58, 1.0)
    static let easeInOut = Easing.cubicBezier(0.42, 0.0, 0.58, 1.0)
}

// MARK: - CustomStringConvertible

extension Easing: CustomStringConvertible {
    public var description: String {
        switch self {
        case .linear: return "linear"
        case .quadraticIn: return "quadraticIn"
        case .quadraticOut: return "quadraticOut"
        case .quadraticInOut: return "quadraticInOut"
        case .cubicIn: return "cubicIn"
        case .cubicOut: return "cubicOut"
        case .cubicInOut: return "cubicInOut"
        case .quarticIn: return "quarticIn"
        case .quarticOut: return "quarticOut"
        case .quarticInOut: return "quarticInOut"
        case .quinticIn: return "quinticIn"
        case .quinticOut: return "quinticOut"
        case .quinticInOut: return "quinticInOut"
        case .sineIn: return "sineIn"
        case .sineOut: return "sineOut"
        case .sineInOut: return "sineInOut"
        case .exponentialIn: return "exponentialIn"
        case .exponentialOut: return "exponentialOut"
        case .exponentialInOut: return "exponentialInOut"
        case .circularIn: return "circularIn"
        case .circularOut: return "circularOut"
        case .circularInOut: return "circularInOut"
        case .backIn: return "backIn"
        case .backOut: return "backOut"
        case .backInOut: return "backInOut"
        case .elasticIn: return "elasticIn"
        case .elasticOut: return "elasticOut"
        case .elasticInOut: return "elasticInOut"
        case .bounceIn: return "bounceIn"
        case .bounceOut: return "bounceOut"
        case .bounceInOut: return "bounceInOut"
        case let .cubicBezier(x1, y1, x2, y2):
            return "cubicBezier(\(x1), \(y1), \(x2), \(y2))"
        }
    }
}
