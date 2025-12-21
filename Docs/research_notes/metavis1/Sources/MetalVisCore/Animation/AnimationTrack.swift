import Foundation

/// Protocol for animation tracks that can be evaluated at any point in time
public protocol AnimationTrack<Value> {
    associatedtype Value

    /// Evaluate the track at a specific normalized time (0.0 to 1.0)
    func evaluate(at time: Double) -> Value
}

// MARK: - Keyframe

/// Single keyframe in an animation track
public struct Keyframe<Value>: Sendable where Value: Sendable {
    /// Time position of this keyframe (0.0 to duration)
    public let time: Double

    /// Value at this keyframe
    public let value: Value

    /// Easing function to use when interpolating TO this keyframe
    public let easing: Easing

    public init(time: Double, value: Value, easing: Easing = .linear) {
        self.time = time
        self.value = value
        self.easing = easing
    }
}

// MARK: - KeyframeTrack

/// Animation track using keyframe interpolation
public struct KeyframeTrack<Value>: AnimationTrack where Value: Interpolatable & Sendable {
    private let keyframes: [Keyframe<Value>]

    /// Duration of the track (time of last keyframe)
    public var duration: Double {
        keyframes.last?.time ?? 0.0
    }

    public init(keyframes: [Keyframe<Value>]) {
        // Sort keyframes by time
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public func evaluate(at time: Double) -> Value {
        guard !keyframes.isEmpty else {
            return Value.zero
        }

        // Single keyframe - constant value
        guard keyframes.count > 1 else {
            return keyframes[0].value
        }

        // Before first keyframe
        if time <= keyframes[0].time {
            return keyframes[0].value
        }

        // After last keyframe
        if time >= keyframes[keyframes.count - 1].time {
            return keyframes[keyframes.count - 1].value
        }

        // Find keyframe segment
        for i in 0 ..< (keyframes.count - 1) {
            let current = keyframes[i]
            let next = keyframes[i + 1]

            if time >= current.time && time <= next.time {
                // Interpolate between current and next
                let segmentDuration = next.time - current.time
                let t = (time - current.time) / segmentDuration
                let easedT = next.easing.evaluate(t)

                return current.value.interpolate(to: next.value, at: easedT)
            }
        }

        // Fallback (should never reach here)
        return keyframes.last!.value
    }
}

// MARK: - Interpolatable Protocol

/// Protocol for types that can be interpolated
public protocol Interpolatable {
    /// Zero value for this type
    static var zero: Self { get }

    /// Interpolate from self to target at time t (0.0 to 1.0)
    func interpolate(to target: Self, at t: Double) -> Self
}

// MARK: - Double Interpolation

extension Double: Interpolatable {
    public static var zero: Double { 0.0 }

    public func interpolate(to target: Double, at t: Double) -> Double {
        self + (target - self) * t
    }
}

// MARK: - Float Interpolation

extension Float: Interpolatable {
    public static var zero: Float { 0.0 }

    public func interpolate(to target: Float, at t: Double) -> Float {
        self + (target - self) * Float(t)
    }
}

// MARK: - SIMD3<Float> Interpolation (for positions, colors)

extension SIMD3<Float>: Interpolatable {
    public static var zero: SIMD3<Float> { SIMD3<Float>(0, 0, 0) }

    public func interpolate(to target: SIMD3<Float>, at t: Double) -> SIMD3<Float> {
        self + (target - self) * Float(t)
    }
}

// MARK: - SIMD4<Float> Interpolation (for quaternions, colors with alpha)

extension SIMD4<Float>: Interpolatable {
    public static var zero: SIMD4<Float> { SIMD4<Float>(0, 0, 0, 0) }

    public func interpolate(to target: SIMD4<Float>, at t: Double) -> SIMD4<Float> {
        self + (target - self) * Float(t)
    }
}
