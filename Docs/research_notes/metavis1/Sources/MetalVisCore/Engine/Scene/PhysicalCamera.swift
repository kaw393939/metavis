import Foundation
import simd

public struct CameraUniforms {
    public var viewMatrix: matrix_float4x4
    public var projectionMatrix: matrix_float4x4
    public var viewProjectionMatrix: matrix_float4x4
    public var position: SIMD3<Float>
    public var padding: Float = 0.0
}

/// A physically-based camera model for the MetalVis engine.
/// Operates in Linear ACEScg space.
/// See: SPEC_01_PHYSICAL_CAMERA.md
public struct PhysicalCamera: Codable {
    
    // MARK: - Transform
    
    public var position: SIMD3<Float> = .zero
    public var orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    
    // MARK: - Physical Parameters
    
    /// Width of the digital sensor in millimeters. Default is Full Frame (36mm).
    public var sensorWidth: Float = 36.0
    
    /// Focal length in millimeters. Determines FOV.
    public var focalLength: Float = 50.0
    
    /// Aperture f-number (N = f/D). Controls Depth of Field.
    public var fStop: Float = 2.8
    
    /// Distance to the plane of perfect focus in meters.
    public var focusDistance: Float = 2.0
    
    /// Shutter angle in degrees. Controls motion blur duration.
    /// 180.0 is standard cinematic motion blur.
    public var shutterAngle: Float = 180.0
    
    /// Sensor sensitivity. Drives noise/grain intensity.
    public var iso: Float = 800.0
    
    // MARK: - Lens Distortion
    
    public var distortionK1: Float = 0.0
    public var distortionK2: Float = 0.0
    public var chromaticAberration: Float = 0.0
    
    // MARK: - Shutter Configuration
    
    public enum ShutterEfficiency: String, Codable {
        case box        // Instant open/close (Ideal)
        case trapezoidal // Mechanical
        case gaussian   // Electronic/Smooth
    }
    
    public var shutterEfficiency: ShutterEfficiency = .box
    
    // MARK: - Motion Control
    
    public enum CameraMotionMode: String, Codable {
        case `static`
        case dollyIn = "slow_dolly_in"
        case truckRight = "truck_right"
    }
    
    public var motionMode: CameraMotionMode = .static
    public var initialPosition: SIMD3<Float> = .zero
    
    // MARK: - Initialization
    
    public init(sensorWidth: Float = 36.0,
                focalLength: Float = 50.0,
                fStop: Float = 2.8,
                focusDistance: Float = 2.0,
                shutterAngle: Float = 180.0,
                iso: Float = 800.0) {
        self.sensorWidth = sensorWidth
        self.focalLength = focalLength
        self.fStop = fStop
        self.focusDistance = focusDistance
        self.shutterAngle = shutterAngle
        self.iso = iso
    }
    
    // MARK: - Codable Implementation
    
    enum CodingKeys: String, CodingKey {
        case position, orientation, sensorWidth, focalLength, fStop, focusDistance, shutterAngle, iso, distortionK1, distortionK2, chromaticAberration, shutterEfficiency
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        position = try container.decode(SIMD3<Float>.self, forKey: .position)
        
        let quatArray = try container.decode([Float].self, forKey: .orientation)
        if quatArray.count == 4 {
            orientation = simd_quatf(ix: quatArray[0], iy: quatArray[1], iz: quatArray[2], r: quatArray[3])
        } else {
            orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        
        sensorWidth = try container.decode(Float.self, forKey: .sensorWidth)
        focalLength = try container.decode(Float.self, forKey: .focalLength)
        fStop = try container.decode(Float.self, forKey: .fStop)
        focusDistance = try container.decode(Float.self, forKey: .focusDistance)
        shutterAngle = try container.decode(Float.self, forKey: .shutterAngle)
        iso = try container.decode(Float.self, forKey: .iso)
        distortionK1 = try container.decode(Float.self, forKey: .distortionK1)
        distortionK2 = try container.decode(Float.self, forKey: .distortionK2)
        chromaticAberration = try container.decode(Float.self, forKey: .chromaticAberration)
        shutterEfficiency = try container.decode(ShutterEfficiency.self, forKey: .shutterEfficiency)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(position, forKey: .position)
        
        let quatArray = [orientation.vector.x, orientation.vector.y, orientation.vector.z, orientation.vector.w]
        try container.encode(quatArray, forKey: .orientation)
        
        try container.encode(sensorWidth, forKey: .sensorWidth)
        try container.encode(focalLength, forKey: .focalLength)
        try container.encode(fStop, forKey: .fStop)
        try container.encode(focusDistance, forKey: .focusDistance)
        try container.encode(shutterAngle, forKey: .shutterAngle)
        try container.encode(iso, forKey: .iso)
        try container.encode(distortionK1, forKey: .distortionK1)
        try container.encode(distortionK2, forKey: .distortionK2)
        try container.encode(chromaticAberration, forKey: .chromaticAberration)
        try container.encode(shutterEfficiency, forKey: .shutterEfficiency)
    }
    
    // MARK: - Derived Calculations
    
    /// Horizontal Field of View in radians.
    /// Formula: 2 * atan(sensorWidth / (2 * focalLength))
    public var fieldOfView: Float {
        return 2.0 * atan(sensorWidth / (2.0 * focalLength))
    }
    
    public func getUniforms(aspectRatio: Float, apertureSample: SIMD2<Float> = .zero) -> CameraUniforms {
        // apertureSample is in normalized [-1, 1] disk space
        
        // 1. Calculate lens offset in meters
        // apertureDiameter is in mm, convert to meters
        let diameterMeters = apertureDiameter / 1000.0
        let radiusMeters = diameterMeters / 2.0
        
        // Scale sample by radius
        let lensOffsetCameraSpace = SIMD3<Float>(apertureSample.x * radiusMeters, apertureSample.y * radiusMeters, 0)
        
        // 2. Calculate new camera position in World Space
        // We need the camera's basis vectors
        let rotation = matrix_float4x4(orientation)
        let right = SIMD3<Float>(rotation.columns.0.x, rotation.columns.0.y, rotation.columns.0.z)
        let up = SIMD3<Float>(rotation.columns.1.x, rotation.columns.1.y, rotation.columns.1.z)
        
        let lensOffsetWorld = right * lensOffsetCameraSpace.x + up * lensOffsetCameraSpace.y
        let newPosition = position + lensOffsetWorld
        
        // 3. Calculate new View Matrix
        // The camera is moved, so we translate by -newPosition
        // The orientation remains the same (sensor plane is parallel to main lens plane)
        let translationMat = matrix_float4x4(translation: newPosition)
        let transform = translationMat * rotation
        let viewMatrix = transform.inverse
        
        // 4. Calculate new Projection Matrix (Off-axis)
        // We need to shift the frustum so that the focus plane aligns
        
        let fov = fieldOfView // Horizontal FOV
        let near: Float = 0.1
        let far: Float = 1000.0
        
        // Since fov is Horizontal, we calculate xScale first
        let xScale = 1.0 / tan(fov * 0.5)
        let yScale = xScale * aspectRatio
        
        let zScale = far / (near - far)
        let zTrans = (near * far) / (near - far)
        
        // Calculate shear to keep focus plane stationary
        // shearX = -lensOffset.x / focusDistance
        // Note: We do NOT multiply by xScale here because the shear matrix multiplication
        // will apply the scaling from the projection matrix.
        let p20 = -lensOffsetCameraSpace.x / focusDistance
        let p21 = -lensOffsetCameraSpace.y / focusDistance
        
        // Standard Metal Reverse-Z Perspective Projection
        // Column-major format: each SIMD4 is a column
        var projectionMatrix = matrix_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),       // Column 0
            SIMD4<Float>(0, yScale, 0, 0),       // Column 1
            SIMD4<Float>(0, 0, zScale, -1),      // Column 2
            SIMD4<Float>(0, 0, zTrans, 0)        // Column 3
        )
        
        // Apply DOF shear if aperture sampling is enabled
        // Shear shifts the projection center to keep focus plane stationary
        if apertureSample != .zero {
            // Shear matrix: shifts X and Y based on lens offset
            // Column 0, Row 2 = p20 (X shear)
            // Column 1, Row 2 = p21 (Y shear)
            var shearMatrix = matrix_identity_float4x4
            shearMatrix[2][0] = p20  // Shear X (column 0, row 2)
            shearMatrix[2][1] = p21  // Shear Y (column 1, row 2)
            projectionMatrix = projectionMatrix * shearMatrix
        }
        
        return CameraUniforms(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            viewProjectionMatrix: projectionMatrix * viewMatrix,
            position: newPosition
        )
    }
    
    /// Physical diameter of the aperture in millimeters.
    /// Formula: D = f / N
    public var apertureDiameter: Float {
        return focalLength / fStop
    }
    
    /// Calculates the Circle of Confusion (CoC) diameter in millimeters for a point at a given distance.
    /// - Parameter distance: Distance to the object in meters.
    /// - Returns: Diameter of the CoC in millimeters.
    public func circleOfConfusion(at distance: Float) -> Float {
        // Convert all to meters for calculation
        let f = focalLength / 1000.0
        let A = f / fStop
        let z = distance
        let z_focus = focusDistance
        
        // Avoid division by zero
        if z == 0 || (z_focus - f) == 0 { return 0.0 }
        
        // CoC Formula: A * (|z - z_focus| / z) * (f / (z_focus - f))
        let term1 = abs(z - z_focus) / z
        let term2 = f / (z_focus - f)
        let cocMeters = A * term1 * term2
        
        return cocMeters * 1000.0 // Convert back to mm
    }
    
    /// Calculates the exposure time in seconds for a given frame rate.
    /// - Parameter fps: Frames per second.
    /// - Returns: Exposure duration in seconds.
    public func exposureDuration(fps: Float) -> Float {
        let frameDuration = 1.0 / fps
        return frameDuration * (shutterAngle / 360.0)
    }
    
    /// Calculates the length of motion blur in pixels for an object moving at a given velocity.
    /// - Parameters:
    ///   - velocityPxPerSec: Velocity of the object in pixels per second.
    ///   - fps: Frames per second.
    /// - Returns: Length of the blur streak in pixels.
    public func motionBlurLength(velocityPxPerSec: Float, fps: Float) -> Float {
        return velocityPxPerSec * exposureDuration(fps: fps)
    }
}

extension matrix_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3.x = translation.x
        columns.3.y = translation.y
        columns.3.z = translation.z
    }
}
