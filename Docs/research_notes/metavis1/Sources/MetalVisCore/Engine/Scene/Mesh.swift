import Metal
import simd
import Shared

public class Mesh {
    public var vertexBuffer: MTLBuffer
    public var indexBuffer: MTLBuffer
    public var indexCount: Int
    public var transform: matrix_float4x4 = matrix_identity_float4x4
    
    /// Optional base color for unlit rendering (e.g. validation charts)
    public var color: SIMD3<Float>?
    
    /// PBR Material Parameters (V6.0)
    public var material: PBRMaterial?
    
    /// Optional texture for unlit rendering
    public var texture: MTLTexture?
    
    // Simple motion for validation
    public var initialPosition: SIMD3<Float> = .zero
    public var velocity: SIMD3<Float> = .zero
    
    // Animation Support
    public var animation: AnimationDefinition?
    public var baseTransform: TransformDefinition?
    public var activeTime: (start: Float, end: Float)?
    
    // Post-Processing Support (V5.7)
    public var postProcessFX: PostProcessFXDefinition?
    
    // Rendering Flags
    public var isTransparent: Bool = false
    public var twinkleStrength: Float = 0.0
    
    public init(device: MTLDevice, vertices: [Float], indices: [UInt16]) {
        self.vertexBuffer = device.makeBuffer(bytes: vertices,
                                              length: vertices.count * MemoryLayout<Float>.size,
                                              options: .storageModeShared)!
        self.indexBuffer = device.makeBuffer(bytes: indices,
                                             length: indices.count * MemoryLayout<UInt16>.size,
                                             options: .storageModeShared)!
        self.indexCount = indices.count
    }
    
    public func update(time: Float) {
        // Check active time
        if let active = activeTime {
            if time < active.start || time > active.end {
                // Hide mesh by scaling to zero
                self.transform = matrix_float4x4(diagonal: SIMD4<Float>(0,0,0,1))
                return
            }
        }
        
        guard let base = baseTransform else {
            // Legacy behavior
            let currentPos = initialPosition + (velocity * time)
            var newTransform = matrix_identity_float4x4
            newTransform.columns.3 = SIMD4<Float>(currentPos.x, currentPos.y, currentPos.z, 1.0)
            self.transform = newTransform
            return
        }
        
        // Calculate Base Matrix
        var currentScale = base.scale ?? 1.0
        
        // Apply Animation
        if let anim = animation {
            if time >= anim.start && time <= anim.end {
                let progress = (time - anim.start) / (anim.end - anim.start)
                
                if anim.type == "SCALE_IN" {
                    currentScale *= progress
                } else if anim.type == "LOGO_FORM_FROM_FIRE" {
                    // Scale up from 0 to 1
                    currentScale *= progress
                }
            } else if time < anim.start {
                if anim.type == "SCALE_IN" || anim.type == "LOGO_FORM_FROM_FIRE" {
                    currentScale = 0
                }
            }
        }
        
        // Reconstruct Matrix
        // 1. Scale
        let s = currentScale
        let scaleMat = matrix_float4x4(diagonal: SIMD4<Float>(s, s, s, 1))
        
        // 2. Rotation (Euler XYZ)
        let rotDeg = base.rotationDegrees ?? [0.0, 0.0, 0.0]
        let radX = rotDeg[0] * .pi / 180.0
        let radY = rotDeg[1] * .pi / 180.0
        let radZ = rotDeg[2] * .pi / 180.0
        
        let rotX = matrix_float4x4(rows: [
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(radX), -sin(radX), 0),
            SIMD4<Float>(0, sin(radX), cos(radX), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ])
        
        let rotY = matrix_float4x4(rows: [
            SIMD4<Float>(cos(radY), 0, sin(radY), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(-sin(radY), 0, cos(radY), 0),
            SIMD4<Float>(0, 0, 0, 1)
        ])
        
        let rotZ = matrix_float4x4(rows: [
            SIMD4<Float>(cos(radZ), -sin(radZ), 0, 0),
            SIMD4<Float>(sin(radZ), cos(radZ), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ])
        
        let rotation = rotZ * rotY * rotX
        
        // 3. Translation
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4<Float>(base.position[0], base.position[1], base.position[2], 1)
        
        self.transform = translation * rotation * scaleMat
    }
    
    // Helper to load from the simple JSON format used in the project (logo_mesh.json)
    // This would be expanded in a real loader
}

// MARK: - Material Types

public struct PBRMaterial {
    public var baseColor: SIMD3<Float>
    public var metallic: Float
    public var roughness: Float
    public var specular: Float
    public var specularTint: Float
    public var sheen: Float
    public var sheenTint: Float
    public var clearcoat: Float
    public var clearcoatGloss: Float
    public var ior: Float
    public var transmission: Float
    
    // Emissive Parameters (V6.4)
    public var emissiveColor: SIMD3<Float>
    public var emissiveIntensity: Float
    
    // Procedural Map Flags
    public var roughnessMapType: Int32
    public var normalMapType: Int32
    public var metallicMapType: Int32
    public var hasBaseColorMap: Int32 // 0 = False, 1 = True
    
    // Procedural Map Parameters
    public var mapFrequency: Float
    public var mapStrength: Float
    
    // Padding to match Metal alignment (64 bytes total?)
    // float3 (16) + 10 floats (40) + 3 ints (12) + 2 floats (8) = 76 bytes?
    // Let's check alignment carefully.
    // Metal struct:
    // float3 baseColor; (16 bytes aligned)
    // float metallic; (4)
    // float roughness; (4)
    // float specular; (4)
    // float specularTint; (4)
    // float sheen; (4)
    // float sheenTint; (4)
    // float clearcoat; (4)
    // float clearcoatGloss; (4)
    // float ior; (4)
    // float transmission; (4)
    // int roughnessMapType; (4)
    // int normalMapType; (4)
    // int metallicMapType; (4)
    // float mapFrequency; (4)
    // float mapStrength; (4)
    
    public init(baseColor: SIMD3<Float> = SIMD3<Float>(1,1,1),
                metallic: Float = 0.0,
                roughness: Float = 0.5,
                specular: Float = 0.5,
                specularTint: Float = 0.0,
                sheen: Float = 0.0,
                sheenTint: Float = 0.0,
                clearcoat: Float = 0.0,
                clearcoatGloss: Float = 1.0,
                ior: Float = 1.45,
                transmission: Float = 0.0,
                emissiveColor: SIMD3<Float> = SIMD3<Float>(0,0,0),
                emissiveIntensity: Float = 0.0) {
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.specular = specular
        self.specularTint = specularTint
        self.sheen = sheen
        self.sheenTint = sheenTint
        self.clearcoat = clearcoat
        self.clearcoatGloss = clearcoatGloss
        self.ior = ior
        self.transmission = transmission
        self.emissiveColor = emissiveColor
        self.emissiveIntensity = emissiveIntensity
        
        self.roughnessMapType = 0
        self.normalMapType = 0
        self.metallicMapType = 0
        self.hasBaseColorMap = 0
        self.mapFrequency = 1.0
        self.mapStrength = 1.0
    }
}
