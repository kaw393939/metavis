// AnimationCurve.swift
// MetaVisRender
//
// Created for Sprint 05: Timeline & Animation
// Pre-defined and custom animation curves

import Foundation
import CoreGraphics

// MARK: - AnimationCurve

/// Represents a complete animation curve with optional custom bezier control points
public struct AnimationCurve: Codable, Sendable, Equatable {
    /// The base interpolation type
    public let type: InterpolationType
    
    /// Custom bezier control points (only used when type is .bezier)
    public let controlPoints: BezierControlPoints?
    
    /// Tension parameter for Catmull-Rom splines (default 0.5)
    public let tension: Double?
    
    public init(type: InterpolationType, controlPoints: BezierControlPoints? = nil, tension: Double? = nil) {
        self.type = type
        self.controlPoints = controlPoints
        self.tension = tension
    }
    
    /// Evaluate the curve at time t (0-1)
    public func evaluate(t: Double) -> Double {
        switch type {
        case .bezier:
            if let cp = controlPoints {
                return cubicBezierY(t: t, x1: cp.x1, y1: cp.y1, x2: cp.x2, y2: cp.y2)
            }
            return type.apply(t: t)
        default:
            return type.apply(t: t)
        }
    }
    
    /// Solve cubic bezier for y given t
    /// Uses Newton-Raphson iteration for accurate results
    private func cubicBezierY(t: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        // For a cubic bezier defined by (0,0), (x1,y1), (x2,y2), (1,1)
        // First solve for parameter u where bezierX(u) = t
        // Then return bezierY(u)
        
        let u = solveBezierT(x: t, x1: x1, x2: x2)
        return bezierY(u: u, y1: y1, y2: y2)
    }
    
    /// Solve for bezier parameter u given x coordinate
    private func solveBezierT(x: Double, x1: Double, x2: Double) -> Double {
        // Newton-Raphson iteration
        var u = x  // Initial guess
        
        for _ in 0..<8 {
            let currentX = bezierX(u: u, x1: x1, x2: x2)
            let dx = bezierXDerivative(u: u, x1: x1, x2: x2)
            
            guard abs(dx) > 1e-10 else { break }
            
            let error = currentX - x
            guard abs(error) > 1e-10 else { break }
            
            u -= error / dx
            u = max(0, min(1, u))
        }
        
        return u
    }
    
    /// Bezier X coordinate
    private func bezierX(u: Double, x1: Double, x2: Double) -> Double {
        let oneMinusU = 1.0 - u
        return 3.0 * oneMinusU * oneMinusU * u * x1 +
               3.0 * oneMinusU * u * u * x2 +
               u * u * u
    }
    
    /// Bezier X derivative
    private func bezierXDerivative(u: Double, x1: Double, x2: Double) -> Double {
        let oneMinusU = 1.0 - u
        return 3.0 * oneMinusU * oneMinusU * x1 +
               6.0 * oneMinusU * u * (x2 - x1) +
               3.0 * u * u * (1.0 - x2)
    }
    
    /// Bezier Y coordinate
    private func bezierY(u: Double, y1: Double, y2: Double) -> Double {
        let oneMinusU = 1.0 - u
        return 3.0 * oneMinusU * oneMinusU * u * y1 +
               3.0 * oneMinusU * u * u * y2 +
               u * u * u
    }
}

// MARK: - BezierControlPoints

/// Control points for cubic bezier curve
/// Defines the curve from (0,0) through (x1,y1), (x2,y2) to (1,1)
public struct BezierControlPoints: Codable, Sendable, Equatable {
    /// First control point X (0-1)
    public let x1: Double
    /// First control point Y
    public let y1: Double
    /// Second control point X (0-1)
    public let x2: Double
    /// Second control point Y
    public let y2: Double
    
    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = max(0, min(1, x1))
        self.y1 = y1
        self.x2 = max(0, min(1, x2))
        self.y2 = y2
    }
}

// MARK: - Preset Curves

extension AnimationCurve {
    // MARK: Standard Easing
    
    /// Linear interpolation (no easing)
    public static let linear = AnimationCurve(type: .linear)
    
    /// Quadratic ease-in
    public static let easeIn = AnimationCurve(type: .easeIn)
    
    /// Quadratic ease-out
    public static let easeOut = AnimationCurve(type: .easeOut)
    
    /// Quadratic ease-in-out
    public static let easeInOut = AnimationCurve(type: .easeInOut)
    
    /// Step function (no interpolation)
    public static let step = AnimationCurve(type: .step)
    
    // MARK: CSS-style Bezier Curves
    
    /// CSS ease (0.25, 0.1, 0.25, 1.0)
    public static let ease = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
    )
    
    /// CSS ease-in (0.42, 0, 1, 1)
    public static let easeInCubic = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.42, y1: 0, x2: 1.0, y2: 1.0)
    )
    
    /// CSS ease-out (0, 0, 0.58, 1)
    public static let easeOutCubic = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0, y1: 0, x2: 0.58, y2: 1.0)
    )
    
    /// CSS ease-in-out (0.42, 0, 0.58, 1)
    public static let easeInOutCubic = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.42, y1: 0, x2: 0.58, y2: 1.0)
    )
    
    // MARK: Dramatic Curves
    
    /// Bounce effect at the end
    public static let bounceOut = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0)
    )
    
    /// Overshoot then settle
    public static let backOut = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.175, y1: 0.885, x2: 0.32, y2: 1.275)
    )
    
    /// Pull back before moving
    public static let backIn = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.6, y1: -0.28, x2: 0.735, y2: 0.045)
    )
    
    /// Elastic spring effect
    public static let elastic = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.68, y1: -0.55, x2: 0.265, y2: 1.55)
    )
    
    // MARK: Cinematic Curves
    
    /// Slow start for dramatic reveals
    public static let cinematicIn = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.55, y1: 0.055, x2: 0.675, y2: 0.19)
    )
    
    /// Smooth landing for camera moves
    public static let cinematicOut = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.215, y1: 0.61, x2: 0.355, y2: 1.0)
    )
    
    /// Professional camera movement curve
    public static let cinematicInOut = AnimationCurve(
        type: .bezier,
        controlPoints: BezierControlPoints(x1: 0.645, y1: 0.045, x2: 0.355, y2: 1.0)
    )
    
    // MARK: Factory Methods
    
    /// Create a custom bezier curve
    public static func bezier(x1: Double, y1: Double, x2: Double, y2: Double) -> AnimationCurve {
        AnimationCurve(
            type: .bezier,
            controlPoints: BezierControlPoints(x1: x1, y1: y1, x2: x2, y2: y2)
        )
    }
    
    /// Create a Catmull-Rom spline with custom tension
    public static func catmullRom(tension: Double = 0.5) -> AnimationCurve {
        AnimationCurve(type: .catmullRom, tension: tension)
    }
}

// MARK: - AnimatedValue

/// A value that can either be static or animated with keyframes
public enum AnimatedValue<T: Interpolatable & Codable & Sendable>: Sendable {
    /// Static value (no animation)
    case constant(T)
    
    /// Animated value with keyframe track
    case animated(KeyframeTrack<T>)
    
    /// Evaluate the value at a given time
    public func evaluate(at time: Double) -> T {
        switch self {
        case .constant(let value):
            return value
        case .animated(let track):
            return track.evaluate(at: time)
        }
    }
    
    /// Check if this value is animated
    public var isAnimated: Bool {
        if case .animated = self { return true }
        return false
    }
    
    /// Get the static value if not animated
    public var constantValue: T? {
        if case .constant(let value) = self { return value }
        return nil
    }
}

// MARK: - AnimatedValue Codable

extension AnimatedValue: Codable {
    enum CodingKeys: String, CodingKey {
        case keyframes
        case interpolation
        case value
    }
    
    public init(from decoder: Decoder) throws {
        // Try to decode as animated first (has keyframes)
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let keyframes = try? container.decode([Keyframe<T>].self, forKey: .keyframes) {
            let interpolation = try container.decodeIfPresent(InterpolationType.self, forKey: .interpolation) ?? .linear
            self = .animated(KeyframeTrack(keyframes: keyframes, interpolation: interpolation))
        } else {
            // Decode as constant value
            let container = try decoder.singleValueContainer()
            let value = try container.decode(T.self)
            self = .constant(value)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .constant(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .animated(let track):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(track.keyframes, forKey: .keyframes)
            try container.encode(track.interpolation, forKey: .interpolation)
        }
    }
}

extension AnimatedValue: Equatable where T: Equatable {}
