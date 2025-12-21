import Foundation
import simd

/// Camera state for 3D visualization
/// Represents position, orientation, and lens properties
public struct CameraState: Sendable {
    // MARK: - Properties

    /// Camera position in world space
    public var position: SIMD3<Float>

    /// Point the camera is looking at
    public var lookAt: SIMD3<Float>

    /// Up vector (typically [0, 1, 0])
    public var up: SIMD3<Float>

    /// Field of view in degrees
    public var fov: Float

    /// Camera roll in radians (rotation around forward axis)
    public var roll: Float

    /// Focus distance in meters
    public var focusDistance: Float

    /// Aperture f-number
    public var fStop: Float

    /// Shutter angle in degrees
    public var shutterAngle: Float

    /// ISO sensitivity
    public var iso: Int

    // MARK: - Computed Properties

    /// Forward direction (normalized)
    public var forward: SIMD3<Float> {
        normalize(lookAt - position)
    }

    /// Right direction (normalized)
    public var right: SIMD3<Float> {
        normalize(cross(forward, up))
    }

    /// Distance from camera to lookAt point
    public var distance: Float {
        simd_length(lookAt - position)
    }

    // MARK: - Initialization

    public init(
        position: SIMD3<Float> = SIMD3<Float>(0, 0, 5),
        lookAt: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
        fov: Float = 60.0,
        roll: Float = 0.0,
        focusDistance: Float = 2.0,
        fStop: Float = 2.8,
        shutterAngle: Float = 180.0,
        iso: Int = 800
    ) {
        self.position = position
        self.lookAt = lookAt
        self.up = up
        self.fov = fov
        self.roll = roll
        self.focusDistance = focusDistance
        self.fStop = fStop
        self.shutterAngle = shutterAngle
        self.iso = iso
    }

    // MARK: - View Matrix

    /// Generate view matrix for Metal rendering
    public func viewMatrix() -> simd_float4x4 {
        let forward = self.forward
        var right = cross(forward, up)
        var actualUp = cross(right, forward)

        // Apply roll rotation
        if roll != 0.0 {
            let cosRoll = cos(roll)
            let sinRoll = sin(roll)
            let rotatedRight = right * cosRoll + actualUp * sinRoll
            actualUp = actualUp * cosRoll - right * sinRoll
            right = rotatedRight
        }

        // Build view matrix (right-handed coordinate system)
        return simd_float4x4(
            SIMD4<Float>(right.x, actualUp.x, -forward.x, 0),
            SIMD4<Float>(right.y, actualUp.y, -forward.y, 0),
            SIMD4<Float>(right.z, actualUp.z, -forward.z, 0),
            SIMD4<Float>(
                -dot(right, position),
                -dot(actualUp, position),
                dot(forward, position),
                1
            )
        )
    }

    // MARK: - Projection Matrix

    /// Generate perspective projection matrix
    public func projectionMatrix(aspectRatio: Float, near: Float = 0.1, far: Float = 1000.0) -> simd_float4x4 {
        let fovRadians = fov * .pi / 180.0
        let ys = 1.0 / tan(fovRadians * 0.5)
        let xs = ys / aspectRatio
        let zs = far / (near - far)

        return simd_float4x4(
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, near * zs, 0)
        )
    }
}

// MARK: - Interpolatable Conformance

extension CameraState: Interpolatable {
    public static var zero: CameraState {
        CameraState(position: .zero, lookAt: .zero, up: SIMD3<Float>(0, 1, 0), fov: 60.0, roll: 0.0)
    }

    public func interpolate(to target: CameraState, at t: Double) -> CameraState {
        let ft = Float(t)

        // Linear interpolation for all properties
        return CameraState(
            position: position + (target.position - position) * ft,
            lookAt: lookAt + (target.lookAt - lookAt) * ft,
            up: normalize(up + (target.up - up) * ft),
            fov: fov + (target.fov - fov) * ft,
            roll: roll + (target.roll - roll) * ft,
            focusDistance: focusDistance + (target.focusDistance - focusDistance) * ft,
            fStop: fStop + (target.fStop - fStop) * ft,
            shutterAngle: shutterAngle + (target.shutterAngle - shutterAngle) * ft,
            iso: Int(Float(iso) + Float(target.iso - iso) * ft)
        )
    }
}

// MARK: - Equatable

extension CameraState: Equatable {
    public static func == (lhs: CameraState, rhs: CameraState) -> Bool {
        simd_distance(lhs.position, rhs.position) < 0.001 &&
            simd_distance(lhs.lookAt, rhs.lookAt) < 0.001 &&
            simd_distance(lhs.up, rhs.up) < 0.001 &&
            abs(lhs.fov - rhs.fov) < 0.001 &&
            abs(lhs.roll - rhs.roll) < 0.001 &&
            abs(lhs.focusDistance - rhs.focusDistance) < 0.001 &&
            abs(lhs.fStop - rhs.fStop) < 0.001 &&
            abs(lhs.shutterAngle - rhs.shutterAngle) < 0.001 &&
            lhs.iso == rhs.iso
    }
}

// MARK: - CustomStringConvertible

extension CameraState: CustomStringConvertible {
    public var description: String {
        """
        CameraState(
            position: [\(position.x), \(position.y), \(position.z)],
            lookAt: [\(lookAt.x), \(lookAt.y), \(lookAt.z)],
            distance: \(String(format: "%.2f", distance)),
            fov: \(String(format: "%.1f", fov))°,
            roll: \(String(format: "%.2f", roll)) rad,
            focus: \(String(format: "%.2f", focusDistance))m,
            fStop: f/\(String(format: "%.1f", fStop)),
            shutter: \(String(format: "%.0f", shutterAngle))°,
            iso: \(iso)
        )
        """
    }
}

// MARK: - Factory Methods

public extension CameraState {
    /// Create camera looking at a specific point from a distance
    static func lookingAt(
        target: SIMD3<Float>,
        distance: Float,
        elevation: Float = 0.0,
        azimuth: Float = 0.0,
        fov: Float = 60.0
    ) -> CameraState {
        // Spherical coordinates to position
        let x = distance * cos(elevation) * sin(azimuth)
        let y = distance * sin(elevation)
        let z = distance * cos(elevation) * cos(azimuth)

        return CameraState(
            position: target + SIMD3<Float>(x, y, z),
            lookAt: target,
            up: SIMD3<Float>(0, 1, 0),
            fov: fov,
            roll: 0.0,
            focusDistance: distance // Default focus to target distance
        )
    }

    /// Create orthographic-style camera (high FOV from far away)
    static func orthographic(
        center: SIMD3<Float>,
        height: Float = 10.0
    ) -> CameraState {
        CameraState(
            position: center + SIMD3<Float>(0, 0, height * 2),
            lookAt: center,
            up: SIMD3<Float>(0, 1, 0),
            fov: 30.0, // Small FOV for minimal perspective
            roll: 0.0,
            focusDistance: height * 2
        )
    }
}
