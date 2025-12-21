import Foundation
import simd

/// Defines the type of light source.
public enum LightType: String, Codable {
    case point
    case directional
    case spot
}

/// A physically-based light source for the MetalVis engine.
/// Operates in Linear ACEScg space.
/// See: SPEC_02_LIGHTING_MODEL.md
public struct LightSource: Codable, Identifiable {
    
    public var id: UUID = UUID()
    
    // MARK: - Core Properties
    
    /// World space position (x, y, z).
    public var position: SIMD3<Float>
    
    /// Linear RGB color (Radiometric).
    public var color: SIMD3<Float>
    
    /// Luminous intensity.
    public var intensity: Float
    
    /// The type of light source.
    public var type: LightType
    
    /// (2.5D) The virtual depth plane for compositing.
    public var zDepth: Float = 0.0
    
    // MARK: - Volumetric Properties
    
    /// Whether this light contributes to God Rays.
    public var isVolumetric: Bool = false
    
    /// Controls the step size/density of the raymarch.
    public var volumetricDensity: Float = 1.0
    
    /// How fast the light energy falls off as it travels through the medium.
    public var volumetricDecay: Float = 0.95
    
    /// Global intensity multiplier for the volumetric effect.
    public var volumetricWeight: Float = 0.5
    
    /// Final tone mapping exposure for the rays.
    public var volumetricExposure: Float = 0.2
    
    // MARK: - Lens Flare Properties
    
    /// Whether this light triggers lens artifacts.
    public var castsLensFlares: Bool = false
    
    // MARK: - Initialization
    
    public init(position: SIMD3<Float> = .zero,
                color: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
                intensity: Float = 1.0,
                type: LightType = .point,
                zDepth: Float = 0.0) {
        self.position = position
        self.color = color
        self.intensity = intensity
        self.type = type
        self.zDepth = zDepth
    }
}
