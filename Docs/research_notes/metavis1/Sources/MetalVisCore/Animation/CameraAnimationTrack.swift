import Foundation
import simd

/// Catmull-Rom spline for smooth camera paths
/// Interpolates through all control points with C1 continuity
public struct CatmullRomSpline {
    private let controlPoints: [SIMD3<Float>]

    /// Create spline from control points
    /// - Parameter controlPoints: Points to interpolate through (minimum 2, ideally 4+)
    public init(controlPoints: [SIMD3<Float>]) {
        self.controlPoints = controlPoints
    }

    /// Evaluate spline at normalized time t (0.0 to 1.0)
    /// Returns interpolated position along the spline
    public func evaluate(at t: Double) -> SIMD3<Float> {
        let t = max(0.0, min(1.0, t))

        guard controlPoints.count >= 2 else {
            return controlPoints.first ?? .zero
        }

        // For 2-3 points, use linear/quadratic interpolation
        if controlPoints.count == 2 {
            return controlPoints[0] + (controlPoints[1] - controlPoints[0]) * Float(t)
        }

        if controlPoints.count == 3 {
            // Quadratic interpolation
            if t < 0.5 {
                let localT = Float(t * 2.0)
                return controlPoints[0] * (1.0 - localT) * (1.0 - localT) +
                    controlPoints[1] * 2.0 * localT * (1.0 - localT) +
                    controlPoints[1] * localT * localT
            } else {
                let localT = Float((t - 0.5) * 2.0)
                return controlPoints[1] * (1.0 - localT) * (1.0 - localT) +
                    controlPoints[2] * 2.0 * localT * (1.0 - localT) +
                    controlPoints[2] * localT * localT
            }
        }

        // Catmull-Rom for 4+ points
        // We interpolate between points 1 and n-2 (using points 0 and n-1 for tangents)
        let numSegments = controlPoints.count - 3
        let segmentIndex = min(Int(t * Double(numSegments)), numSegments - 1)
        let segmentT = Float(t * Double(numSegments) - Double(segmentIndex))

        let p0 = controlPoints[segmentIndex]
        let p1 = controlPoints[segmentIndex + 1]
        let p2 = controlPoints[segmentIndex + 2]
        let p3 = controlPoints[segmentIndex + 3]

        return catmullRomInterpolate(p0: p0, p1: p1, p2: p2, p3: p3, t: segmentT)
    }

    /// Catmull-Rom interpolation between p1 and p2, using p0 and p3 for tangents
    private func catmullRomInterpolate(
        p0: SIMD3<Float>,
        p1: SIMD3<Float>,
        p2: SIMD3<Float>,
        p3: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        let t2 = t * t
        let t3 = t2 * t

        // Catmull-Rom basis matrix coefficients
        let c0 = -0.5 * t3 + t2 - 0.5 * t
        let c1 = 1.5 * t3 - 2.5 * t2 + 1.0
        let c2 = -1.5 * t3 + 2.0 * t2 + 0.5 * t
        let c3 = 0.5 * t3 - 0.5 * t2

        return p0 * c0 + p1 * c1 + p2 * c2 + p3 * c3
    }
}

// MARK: - CameraAnimationTrack

/// Animation track for camera movement using splines
public struct CameraAnimationTrack: Sendable {
    private let keyframes: [Keyframe<CameraState>]
    private let useSpline: Bool

    /// Duration of the track
    public var duration: Double {
        keyframes.last?.time ?? 0.0
    }

    /// Create camera track with keyframes
    /// - Parameters:
    ///   - keyframes: Camera state keyframes
    ///   - useSpline: If true, use Catmull-Rom spline for position interpolation (smoother curves)
    public init(keyframes: [Keyframe<CameraState>], useSpline: Bool = false) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
        self.useSpline = useSpline
    }

    /// Evaluate camera state at normalized time (0.0 to 1.0)
    public func evaluate(at time: Double) -> CameraState {
        guard !keyframes.isEmpty else {
            return .zero
        }

        // Single keyframe - constant state
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

        // Use spline interpolation if enabled and we have enough points
        if useSpline && keyframes.count >= 3 {
            return evaluateWithSpline(at: time)
        }

        // Find keyframe segment and interpolate
        for i in 0 ..< (keyframes.count - 1) {
            let current = keyframes[i]
            let next = keyframes[i + 1]

            if time >= current.time && time <= next.time {
                let segmentDuration = next.time - current.time
                let t = (time - current.time) / segmentDuration
                let easedT = next.easing.evaluate(t)

                return current.value.interpolate(to: next.value, at: easedT)
            }
        }

        return keyframes.last!.value
    }

    /// Evaluate using Catmull-Rom spline for smooth position interpolation
    private func evaluateWithSpline(at time: Double) -> CameraState {
        // Build spline for positions
        let positions = keyframes.map { $0.value.position }
        let spline = CatmullRomSpline(controlPoints: positions)

        // Build spline for lookAt points
        let lookAts = keyframes.map { $0.value.lookAt }
        let lookAtSpline = CatmullRomSpline(controlPoints: lookAts)

        // Normalize time to 0-1 for spline
        let normalizedT = time / duration

        // Interpolate other properties linearly between nearest keyframes
        var nearestPrev = keyframes[0]
        var nearestNext = keyframes[keyframes.count - 1]

        for i in 0 ..< (keyframes.count - 1) {
            if time >= keyframes[i].time && time <= keyframes[i + 1].time {
                nearestPrev = keyframes[i]
                nearestNext = keyframes[i + 1]
                break
            }
        }

        let segmentDuration = nearestNext.time - nearestPrev.time
        let t = segmentDuration > 0 ? (time - nearestPrev.time) / segmentDuration : 0.0
        let easedT = nearestNext.easing.evaluate(t)

        return CameraState(
            position: spline.evaluate(at: normalizedT),
            lookAt: lookAtSpline.evaluate(at: normalizedT),
            up: nearestPrev.value.up.interpolate(to: nearestNext.value.up, at: easedT),
            fov: nearestPrev.value.fov.interpolate(to: nearestNext.value.fov, at: easedT),
            roll: nearestPrev.value.roll.interpolate(to: nearestNext.value.roll, at: easedT)
        )
    }
}

// MARK: - AnimationTrack Conformance

extension CameraAnimationTrack: AnimationTrack {
    // Already implements evaluate(at:) -> CameraState
}
