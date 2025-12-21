// Keyframe.swift
// MetaVisRender
//
// Created for Sprint 05: Timeline & Animation
// Generic keyframe type for animating any property

import Foundation
import simd
import CoreGraphics

// MARK: - Keyframe

/// A keyframe defines a value at a specific point in time.
/// Used for animating any property in the render manifest.
/// Uses the existing Interpolatable protocol from Animation/Tween.swift
public struct Keyframe<T: Interpolatable & Sendable>: Sendable {
    /// Time in seconds when this keyframe occurs
    public let time: Double
    
    /// The value at this keyframe
    public let value: T
    
    /// Optional tangent for bezier interpolation (used for in-tangent)
    public let inTangent: T?
    
    /// Optional tangent for bezier interpolation (used for out-tangent)
    public let outTangent: T?
    
    public init(time: Double, value: T, inTangent: T? = nil, outTangent: T? = nil) {
        self.time = time
        self.value = value
        self.inTangent = inTangent
        self.outTangent = outTangent
    }
}

// MARK: - KeyframeTrack

/// A track contains multiple keyframes for a single property
public struct KeyframeTrack<T: Interpolatable & Sendable>: Sendable {
    /// The keyframes, sorted by time
    public private(set) var keyframes: [Keyframe<T>]
    
    /// The interpolation curve to use between keyframes
    public let interpolation: InterpolationType
    
    /// Optional: Extrapolation behavior before first keyframe
    public let preExtrapolation: ExtrapolationType
    
    /// Optional: Extrapolation behavior after last keyframe
    public let postExtrapolation: ExtrapolationType
    
    public init(
        keyframes: [Keyframe<T>],
        interpolation: InterpolationType = .linear,
        preExtrapolation: ExtrapolationType = .hold,
        postExtrapolation: ExtrapolationType = .hold
    ) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
        self.interpolation = interpolation
        self.preExtrapolation = preExtrapolation
        self.postExtrapolation = postExtrapolation
    }
    
    /// Add a keyframe, maintaining sorted order
    public mutating func addKeyframe(_ keyframe: Keyframe<T>) {
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }
    
    /// Remove keyframe at index
    public mutating func removeKeyframe(at index: Int) {
        guard keyframes.indices.contains(index) else { return }
        keyframes.remove(at: index)
    }
    
    /// Evaluate the track at a given time
    public func evaluate(at time: Double) -> T {
        guard !keyframes.isEmpty else {
            fatalError("Cannot evaluate empty keyframe track")
        }
        
        // Single keyframe - return its value
        if keyframes.count == 1 {
            return keyframes[0].value
        }
        
        // Before first keyframe
        if time <= keyframes[0].time {
            return extrapolate(time: time, direction: .pre)
        }
        
        // After last keyframe
        if time >= keyframes[keyframes.count - 1].time {
            return extrapolate(time: time, direction: .post)
        }
        
        // Find surrounding keyframes
        var lowerIndex = 0
        for i in 0..<keyframes.count - 1 {
            if time >= keyframes[i].time && time < keyframes[i + 1].time {
                lowerIndex = i
                break
            }
        }
        
        let k0 = keyframes[lowerIndex]
        let k1 = keyframes[lowerIndex + 1]
        
        // Calculate normalized time between keyframes
        let duration = k1.time - k0.time
        let t = duration > 0 ? (time - k0.time) / duration : 0
        
        // Apply easing curve
        let easedT = interpolation.apply(t: t)
        
        // Interpolate value
        return T.interpolate(from: k0.value, to: k1.value, t: easedT)
    }
    
    private enum ExtrapolationDirection {
        case pre, post
    }
    
    private func extrapolate(time: Double, direction: ExtrapolationDirection) -> T {
        let extrapolation = direction == .pre ? preExtrapolation : postExtrapolation
        
        switch extrapolation {
        case .hold:
            return direction == .pre ? keyframes[0].value : keyframes[keyframes.count - 1].value
            
        case .linear:
            if keyframes.count < 2 {
                return keyframes[0].value
            }
            
            if direction == .pre {
                let k0 = keyframes[0]
                let k1 = keyframes[1]
                let slope = (time - k0.time) / (k1.time - k0.time)
                return T.interpolate(from: k0.value, to: k1.value, t: slope)
            } else {
                let k0 = keyframes[keyframes.count - 2]
                let k1 = keyframes[keyframes.count - 1]
                let slope = (time - k0.time) / (k1.time - k0.time)
                return T.interpolate(from: k0.value, to: k1.value, t: slope)
            }
            
        case .loop:
            let duration = keyframes[keyframes.count - 1].time - keyframes[0].time
            guard duration > 0 else { return keyframes[0].value }
            
            var loopedTime = time - keyframes[0].time
            loopedTime = loopedTime.truncatingRemainder(dividingBy: duration)
            if loopedTime < 0 { loopedTime += duration }
            loopedTime += keyframes[0].time
            
            return evaluate(at: loopedTime)
            
        case .pingPong:
            let duration = keyframes[keyframes.count - 1].time - keyframes[0].time
            guard duration > 0 else { return keyframes[0].value }
            
            var offset = time - keyframes[0].time
            let cycles = abs(offset / duration)
            let isReversed = Int(cycles) % 2 == 1
            
            offset = offset.truncatingRemainder(dividingBy: duration)
            if offset < 0 { offset += duration }
            
            let normalizedTime = isReversed ? duration - offset : offset
            return evaluate(at: keyframes[0].time + normalizedTime)
        }
    }
    
    /// Get the duration of this track (from first to last keyframe)
    public var duration: Double {
        guard keyframes.count > 1 else { return 0 }
        return keyframes[keyframes.count - 1].time - keyframes[0].time
    }
    
    /// Get the start time
    public var startTime: Double {
        keyframes.first?.time ?? 0
    }
    
    /// Get the end time
    public var endTime: Double {
        keyframes.last?.time ?? 0
    }
}

// MARK: - Interpolation Types

/// Types of interpolation between keyframes
public enum InterpolationType: String, Codable, Sendable {
    /// Constant speed interpolation
    case linear
    
    /// Start slow, accelerate
    case easeIn = "ease_in"
    
    /// Start fast, decelerate
    case easeOut = "ease_out"
    
    /// Smooth both ends
    case easeInOut = "ease_in_out"
    
    /// Instant jump at keyframe
    case step
    
    /// Custom cubic bezier (control points in keyframe tangents)
    case bezier
    
    /// Catmull-Rom spline through keyframes
    case catmullRom = "catmull_rom"
    
    /// Apply easing function to normalized time t
    func apply(t: Double) -> Double {
        switch self {
        case .linear:
            return t
            
        case .easeIn:
            return t * t
            
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
            
        case .easeInOut:
            return t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2
            
        case .step:
            return t < 1.0 ? 0.0 : 1.0
            
        case .bezier:
            // Default bezier uses ease-in-out curve
            // Actual bezier with custom control points handled separately
            return cubicBezier(t: t, p1: 0.42, p2: 0.0, p3: 0.58, p4: 1.0)
            
        case .catmullRom:
            // For single segment, use smooth approximation
            return t
        }
    }
    
    /// Cubic bezier interpolation
    /// p1, p2 are x,y of first control point
    /// p3, p4 are x,y of second control point
    private func cubicBezier(t: Double, p1: Double, p2: Double, p3: Double, p4: Double) -> Double {
        // Approximate cubic bezier - for production would use Newton-Raphson
        let cx = 3.0 * p1
        let bx = 3.0 * (p3 - p1) - cx
        let ax = 1.0 - cx - bx
        
        let cy = 3.0 * p2
        let by = 3.0 * (p4 - p2) - cy
        let ay = 1.0 - cy - by
        
        // Sample the curve
        let x = ((ax * t + bx) * t + cx) * t
        let y = ((ay * t + by) * t + cy) * t
        
        // Return y value (the eased time)
        _ = x  // x is used for more accurate bezier, simplified here
        return y
    }
}

// MARK: - Extrapolation Types

/// Behavior when evaluating outside keyframe range
public enum ExtrapolationType: String, Codable, Sendable {
    /// Hold the first/last value
    case hold
    
    /// Continue linear extrapolation
    case linear
    
    /// Loop back to start
    case loop
    
    /// Bounce back and forth
    case pingPong = "ping_pong"
}

// MARK: - Additional Interpolatable Conformances
// The base Interpolatable protocol is defined in Animation/Tween.swift
// Here we add conformances for types not covered there

extension Int: Interpolatable {
    public static func interpolate(from: Int, to: Int, t: Double) -> Int {
        Int(Double(from) + Double(to - from) * t)
    }
}

extension SIMD2: Interpolatable where Scalar: BinaryFloatingPoint {
    public static func interpolate(from: SIMD2<Scalar>, to: SIMD2<Scalar>, t: Double) -> SIMD2<Scalar> {
        let scalar = Scalar(t)
        return from + (to - from) * scalar
    }
}

extension SIMD3: Interpolatable where Scalar: BinaryFloatingPoint {
    public static func interpolate(from: SIMD3<Scalar>, to: SIMD3<Scalar>, t: Double) -> SIMD3<Scalar> {
        let scalar = Scalar(t)
        return from + (to - from) * scalar
    }
}

extension CGSize: Interpolatable {
    public static func interpolate(from: CGSize, to: CGSize, t: Double) -> CGSize {
        CGSize(
            width: from.width + (to.width - from.width) * CGFloat(t),
            height: from.height + (to.height - from.height) * CGFloat(t)
        )
    }
}

extension CGRect: Interpolatable {
    public static func interpolate(from: CGRect, to: CGRect, t: Double) -> CGRect {
        CGRect(
            origin: CGPoint.interpolate(from: from.origin, to: to.origin, t: t),
            size: CGSize.interpolate(from: from.size, to: to.size, t: t)
        )
    }
}

// MARK: - Codable Support

extension Keyframe: Codable where T: Codable {
    enum CodingKeys: String, CodingKey {
        case time
        case value
        case inTangent = "in_tangent"
        case outTangent = "out_tangent"
    }
}

extension KeyframeTrack: Codable where T: Codable {
    enum CodingKeys: String, CodingKey {
        case keyframes
        case interpolation
        case preExtrapolation = "pre_extrapolation"
        case postExtrapolation = "post_extrapolation"
    }
}

// MARK: - Equatable Support

extension Keyframe: Equatable where T: Equatable {}
extension KeyframeTrack: Equatable where T: Equatable {}
