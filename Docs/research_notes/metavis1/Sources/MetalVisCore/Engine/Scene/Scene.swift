import Foundation
import simd
import Shared

/// The container for all physical objects in the virtual world.
/// This data structure is passed to the Render Graph to drive the frame generation.
public class Scene {
    
    // MARK: - Camera
    
    /// The main camera rig used for rendering.
    public var camera: PhysicalCamera
    
    /// Keyframes for camera animation
    public var cameraKeyframes: [CameraKeyframe] = []
    
    // MARK: - Lighting
    
    /// Collection of light sources in the scene.
    public var lights: [LightSource]
    
    /// Global ambient light color (Linear ACEScg).
    public var ambientLight: SIMD3<Float>
    
    /// Global volumetric density multiplier.
    public var volumetricDensity: Float = 1.0
    
    /// Background Configuration (V5.8)
    public var background: BackgroundDefinition?
    
    /// Focus Zones for Selective Focus (V5.8)
    public var focusZones: [FocusZoneDefinition] = []
    
    // MARK: - Geometry
    
    /// Collection of renderable meshes in the scene.
    public var meshes: [Mesh]
    
    // MARK: - Initialization
    
    public init(camera: PhysicalCamera = PhysicalCamera(),
                lights: [LightSource] = [],
                meshes: [Mesh] = [],
                ambientLight: SIMD3<Float> = .zero) {
        self.camera = camera
        self.lights = lights
        self.meshes = meshes
        self.ambientLight = ambientLight
    }
    
    // MARK: - Helpers
    
    /// Adds a light to the scene.
    public func addLight(_ light: LightSource) {
        lights.append(light)
    }
    
    /// Adds a mesh to the scene.
    public func addMesh(_ mesh: Mesh) {
        meshes.append(mesh)
    }
    
    /// Returns all lights that cast volumetric rays.
    public var volumetricLights: [LightSource] {
        return lights.filter { $0.isVolumetric }
    }
    
    /// Updates the scene state to the given time.
    public func update(time: Float) {
        // Camera Animation
        if !cameraKeyframes.isEmpty {
            updateCameraFromKeyframes(time: time)
        } else {
            // Legacy Motion
            switch camera.motionMode {
            case .dollyIn:
                camera.position = camera.initialPosition + SIMD3<Float>(0, 0, -1.0 * time)
            case .truckRight:
                camera.position = camera.initialPosition + SIMD3<Float>(1.0 * time, 0, 0)
            case .static:
                break
            }
        }
        
        for mesh in meshes {
            mesh.update(time: time)
        }
    }
    
    private func updateCameraFromKeyframes(time: Float) {
        let sortedKeys = cameraKeyframes.sorted { $0.timeSeconds < $1.timeSeconds }
        
        guard let first = sortedKeys.first, let last = sortedKeys.last else { return }
        
        if time <= first.timeSeconds {
            applyKeyframe(first)
            return
        }
        
        if time >= last.timeSeconds {
            applyKeyframe(last)
            return
        }
        
        for i in 0..<(sortedKeys.count - 1) {
            let k1 = sortedKeys[i]
            let k2 = sortedKeys[i+1]
            
            if time >= k1.timeSeconds && time < k2.timeSeconds {
                let t = (time - k1.timeSeconds) / (k2.timeSeconds - k1.timeSeconds)
                interpolateCamera(k1, k2, t: t)
                return
            }
        }
    }
    
    private func applyKeyframe(_ k: CameraKeyframe) {
        camera.position = SIMD3<Float>(k.position[0], k.position[1], k.position[2])
        let target = SIMD3<Float>(k.target[0], k.target[1], k.target[2])
        lookAt(from: camera.position, to: target)
        
        let fovRad = k.fov * .pi / 180.0
        camera.focalLength = camera.sensorWidth / (2.0 * tan(fovRad / 2.0))
        
        // Apply V5.7/V5.8 Parameters
        if let k1 = k.distortionK1 { camera.distortionK1 = k1 }
        if let k2 = k.distortionK2 { camera.distortionK2 = k2 }
        if let ca = k.chromaticAberration { camera.chromaticAberration = ca }
        if let fd = k.focusDistance { camera.focusDistance = fd }
        if let fs = k.fStop { camera.fStop = fs }
    }
    
    private func interpolateCamera(_ k1: CameraKeyframe, _ k2: CameraKeyframe, t: Float) {
        let p1 = SIMD3<Float>(k1.position[0], k1.position[1], k1.position[2])
        let p2 = SIMD3<Float>(k2.position[0], k2.position[1], k2.position[2])
        camera.position = mix(p1, p2, t: t)
        
        let t1 = SIMD3<Float>(k1.target[0], k1.target[1], k1.target[2])
        let t2 = SIMD3<Float>(k2.target[0], k2.target[1], k2.target[2])
        let currentTarget = mix(t1, t2, t: t)
        
        lookAt(from: camera.position, to: currentTarget)
        
        let fov1 = k1.fov
        let fov2 = k2.fov
        let currentFov = fov1 + (fov2 - fov1) * t
        let fovRad = currentFov * .pi / 180.0
        camera.focalLength = camera.sensorWidth / (2.0 * tan(fovRad / 2.0))
        
        // Interpolate V5.7/V5.8 Parameters
        // Use 0.0 as default for effects, and current camera values for physics if missing (or sensible defaults)
        let dK1_1 = k1.distortionK1 ?? 0.0
        let dK1_2 = k2.distortionK1 ?? 0.0
        camera.distortionK1 = dK1_1 + (dK1_2 - dK1_1) * t
        
        let dK2_1 = k1.distortionK2 ?? 0.0
        let dK2_2 = k2.distortionK2 ?? 0.0
        camera.distortionK2 = dK2_1 + (dK2_2 - dK2_1) * t
        
        let ca1 = k1.chromaticAberration ?? 0.0
        let ca2 = k2.chromaticAberration ?? 0.0
        camera.chromaticAberration = ca1 + (ca2 - ca1) * t
        
        // For Focus/FStop, if missing in keyframe, we ideally want to hold the previous value.
        // But here we only have k1 and k2. We'll assume if k1 has it, we start there.
        // If k1 is missing, we default to standard values (2.0m, f/2.8)
        let fd1 = k1.focusDistance ?? 2.0
        let fd2 = k2.focusDistance ?? fd1 // If k2 missing, hold k1
        camera.focusDistance = fd1 + (fd2 - fd1) * t
        
        let fs1 = k1.fStop ?? 2.8
        let fs2 = k2.fStop ?? fs1
        camera.fStop = fs1 + (fs2 - fs1) * t
    }
    
    private func lookAt(from pos: SIMD3<Float>, to target: SIMD3<Float>) {
        let forward = normalize(target - pos) // This is actually -Z in camera space if we want to look at target
        // Wait, standard LookAt:
        // Camera looks down -Z.
        // So if we want -Z to point to target, then +Z points (pos - target).
        
        let zAxis = normalize(pos - target) // +Z
        let up = SIMD3<Float>(0, 1, 0)
        let xAxis = normalize(cross(up, zAxis)) // +X
        let yAxis = cross(zAxis, xAxis) // +Y
        
        let rotationMatrix = matrix_float3x3(columns: (xAxis, yAxis, zAxis))
        camera.orientation = simd_quatf(rotationMatrix)
    }
}
