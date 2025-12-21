import Foundation
import simd

/// A physically-based virtual camera for the MetaVis Director system.
/// Unifies perspective and orthographic projections with physical lens parameters.
public struct VirtualCamera: Sendable {
    
    // MARK: - Transform
    
    /// Position of the camera in World Space
    public var position: SIMD3<Float>
    
    /// Target point the camera is looking at
    public var target: SIMD3<Float>
    
    /// Up vector (usually 0,1,0)
    public var up: SIMD3<Float>
    
    // MARK: - Lens
    
    /// Vertical Field of View in degrees
    public var fov: Float
    
    /// Near clipping plane
    public var near: Float
    
    /// Far clipping plane
    public var far: Float
    
    /// Focal length in millimeters (35mm equivalent).
    /// If set, overrides FOV based on sensor size.
    public var focalLength: Float?
    
    /// Aperture (f-stop) for Depth of Field calculations
    public var aperture: Float
    
    /// Focus distance in world units
    public var focusDistance: Float
    
    // MARK: - Initialization
    
    public init(
        position: SIMD3<Float> = SIMD3(0, 0, 1000),
        target: SIMD3<Float> = SIMD3(0, 0, 0),
        up: SIMD3<Float> = SIMD3(0, 1, 0),
        fov: Float = 60.0,
        near: Float = 0.1,
        far: Float = 10000.0,
        focalLength: Float? = nil,
        aperture: Float = 2.8,
        focusDistance: Float = 1000.0
    ) {
        self.position = position
        self.target = target
        self.up = up
        self.fov = fov
        self.near = near
        self.far = far
        self.focalLength = focalLength
        self.aperture = aperture
        self.focusDistance = focusDistance
    }
    
    // MARK: - Matrices
    
    /// Calculates the View Matrix (World -> Camera)
    public var viewMatrix: matrix_float4x4 {
        return makeLookAtMatrix(eye: position, target: target, up: up)
    }
    
    /// Calculates the Projection Matrix (Camera -> Clip)
    public func projectionMatrix(aspectRatio: Float) -> matrix_float4x4 {
        // TODO: Implement focal length -> FOV conversion if focalLength is set
        return makePerspectiveMatrix(
            fovyRadians: degreesToRadians(fov),
            aspect: aspectRatio,
            nearZ: near,
            farZ: far
        )
    }
    
    // MARK: - Helpers
    
    private func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * .pi / 180.0
    }
    
    private func makeLookAtMatrix(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        
        return matrix_float4x4(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
    
    private func makePerspectiveMatrix(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
        let ys = 1 / tanf(fovyRadians * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        
        return matrix_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }
}
