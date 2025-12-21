import Foundation
import simd

/// The root object of the Semantic Manifest (Video DOM) - V5.1 Spec
/// See: SPEC_05_SEMANTIC_MANIFEST.md
public struct RenderManifest: Codable {
    public let manifestId: String?
    public let version: String?
    public let metadata: ManifestMetadata
    
    public let scene: SceneDefinition
    public let camera: CameraDefinition
    public let postProcessing: PostProcessDefinition
    
    public let elements: [ManifestElement]
    
    enum CodingKeys: String, CodingKey {
        case manifestId
        case version
        case metadata
        case scene
        case camera
        case postProcessing = "post_processing"
        case elements
    }
}

public struct ManifestMetadata: Codable {
    public let title: String
    public let durationSeconds: Float
    public let targetAspectRatio: String
    public let intendedQualityProfile: String
    public let cinematicPresetId: String?
    
    enum CodingKeys: String, CodingKey {
        case title
        case durationSeconds = "duration_seconds"
        case targetAspectRatio = "target_aspect_ratio"
        case intendedQualityProfile = "intended_quality_profile"
        case cinematicPresetId = "cinematic_preset_id"
    }
}

// MARK: - Scene Definition

public struct SceneDefinition: Codable {
    public let lighting: LightingDefinition
    public let atmosphere: AtmosphereDefinition
    public let background: BackgroundDefinition?
}

public struct BackgroundDefinition: Codable {
    public let type: String // "SOLID", "GRADIENT", "STARFIELD"
    public let color: String? // V6.3: Single color for SOLID
    public let colorTop: String?
    public let colorBottom: String?
    public let starDensity: Int?
    
    enum CodingKeys: String, CodingKey {
        case type
        case color
        case colorTop = "color_top"
        case colorBottom = "color_bottom"
        case starDensity = "star_density"
    }
}

public struct LightingDefinition: Codable {
    public let ambientIntensity: Float? // Made optional to allow preset override
    public let directionalLight: DirectionalLightDefinition?
    public let preset: String? // V6.3
    
    enum CodingKeys: String, CodingKey {
        case ambientIntensity = "ambient_intensity"
        case directionalLight = "directional_light"
        case preset
    }
}

public struct DirectionalLightDefinition: Codable {
    public let color: String // Hex
    public let direction: [Float] // [x, y, z]
}

public struct AtmosphereDefinition: Codable {
    public let volumetricsEnabled: Bool
    public let density: Float
    public let fogStartDistance: Float
    public let volumetricColor: String
    
    // New V5.7 Parameters
    public let decay: Float?
    public let weight: Float?
    public let exposure: Float?
    
    enum CodingKeys: String, CodingKey {
        case volumetricsEnabled = "volumetrics_enabled"
        case density
        case fogStartDistance = "fog_start_distance"
        case volumetricColor = "volumetric_color"
        case decay, weight, exposure
    }
}

// MARK: - Camera Definition

public struct CameraDefinition: Codable {
    public let keyframes: [CameraKeyframe]
}

public struct CameraKeyframe: Codable {
    public let timeSeconds: Float
    public let position: [Float]
    public let target: [Float]
    public let fov: Float
    
    // New V5.7 Parameters
    public let distortionK1: Float?
    public let distortionK2: Float?
    public let chromaticAberration: Float?
    
    // New V5.8 Parameters (Focus Control)
    public let focusDistance: Float?
    public let fStop: Float?
    
    enum CodingKeys: String, CodingKey {
        case timeSeconds = "time_seconds"
        case position
        case target
        case fov
        case distortionK1 = "distortion_k1"
        case distortionK2 = "distortion_k2"
        case chromaticAberration = "chromatic_aberration"
        case focusDistance = "focus_distance"
        case fStop = "f_stop"
    }
}

// MARK: - Post Processing

public struct PostProcessDefinition: Codable {
    public let colorPipeline: String
    public let lookUpTable: String?
    public let halation: HalationDefinition?
    public let depthOfField: DepthOfFieldDefinition?
    public let bloom: BloomDefinition?
    public let filmGrain: FilmGrainDefinition?
    public let vignette: VignetteDefinition?
    public let shimmer: ShimmerDefinition? // V6.0
    public let lensDistortion: LensDistortionDefinition? // V6.3
    
    enum CodingKeys: String, CodingKey {
        case colorPipeline = "color_pipeline"
        case lookUpTable = "look_up_table"
        case halation
        case depthOfField = "depth_of_field"
        case bloom
        case filmGrain = "film_grain"
        case vignette
        case shimmer
        case lensDistortion = "lens_distortion"
    }
}

public struct LensDistortionDefinition: Codable {
    public let enabled: Bool
    public let intensity: Float?
}

public struct ShimmerDefinition: Codable {
    public let enabled: Bool
    public let intensity: Float?
    public let speed: Float?
    public let width: Float?
    public let angle: Float?
}

public struct HalationDefinition: Codable {
    public let enabled: Bool
    public let magnitude: Float?
    public let ditheringEnabled: Bool?
    public let tint: String? // Hex color
    public let radialFalloff: Bool? // V6.3
    public let threshold: Float? // V6.0
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case magnitude
        case ditheringEnabled = "dithering_enabled"
        case tint
        case radialFalloff = "radial_falloff"
        case threshold
    }
}

public struct DepthOfFieldDefinition: Codable {
    public let enabled: Bool
    public let focalDistanceM: Float?
    public let apertureFstop: Float?
    public let focusZones: [FocusZoneDefinition]?
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case focalDistanceM = "focal_distance_m"
        case apertureFstop = "aperture_fstop"
        case focusZones = "focus_zones"
    }
}

public struct FocusZoneDefinition: Codable {
    public let zMin: Float
    public let zMax: Float
    public let focalDistanceM: Float
    public let apertureFstop: Float
    
    enum CodingKeys: String, CodingKey {
        case zMin = "z_min"
        case zMax = "z_max"
        case focalDistanceM = "focal_distance_m"
        case apertureFstop = "aperture_fstop"
    }
}

public struct BloomDefinition: Codable {
    public let enabled: Bool
    public let intensity: Float?
    public let threshold: Float?
    public let radius: Float?
    public let preservation: Float?
    public let knee: Float?
    public let clampMax: Float? // V6.0: Firefly reduction
    
    enum CodingKeys: String, CodingKey {
        case enabled, intensity, threshold, radius, preservation, knee
        case clampMax = "clamp_max"
    }
}

public struct FilmGrainDefinition: Codable {
    public let enabled: Bool
    public let intensity: Float?
    public let size: Float? // V6.3
    public let shadowBoost: Float? // V6.3
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case intensity
        case size
        case shadowBoost = "shadow_boost"
    }
}

public struct VignetteDefinition: Codable {
    public let enabled: Bool
    public let intensity: Float?
    public let smoothness: Float? // V6.3
    public let roundness: Float? // V6.3
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case intensity
        case smoothness
        case roundness
    }
}

// MARK: - Elements

public struct ManifestElement: Codable {
    public let type: String // "text", "particle_system", "logo_element", "media_plane", "credit_roll"
    public let id: String
    
    // Timing (Optional, defaults to full duration if missing)
    public let activeTime: [Float]? // [start, end]
    
    // Transform
    public let worldTransform: TransformDefinition?
    public let position: [Float]? // Legacy/Simple support
    public let scale: Float? // Legacy/Simple support
    
    // Content Specifics
    public let content: String? // For text
    public let style: String? // For text
    public let color: String? // For text/shapes
    public let msdfEnabled: Bool? // For text
    public let softness: Float? // For text
    public let fadeStart: Float? // For text
    public let fadeEnd: Float? // For text
    
    // New Fields for V5.2
    public let fontAssetId: String?
    public let textColor: String?
    public let stylingProfile: StylingProfileDefinition?
    public let screenAlignment: ScreenAlignmentDefinition?
    public let alignment: String?
    public let scrollSpeedNormalized: Float?
    public let tracking: Float? // V6.3
    public let lineItems: [CreditLineItem]?
    public let particlePhysics: ParticlePhysicsDefinition?
    public let assetId: String?
    
    // Unified Procedural Field (V2.0)
    public let proceduralField: ProceduralFieldDefinition?
    public let colorMap: ColorMapDefinition?
    public let assetPath: String?
    public let material: MaterialDefinition?
    public let postProcessFx: PostProcessFXDefinition?
    
    // Animation
    public let animation: AnimationDefinition?
    
    enum CodingKeys: String, CodingKey {
        case type, id
        case activeTime = "active_time"
        case worldTransform = "world_transform"
        case position, scale
        case content, style, color
        case msdfEnabled = "msdf_enabled"
        case softness
        case fadeStart = "fade_start"
        case fadeEnd = "fade_end"
        case animation
        
        // New Keys
        case fontAssetId = "font_asset_id"
        case textColor = "text_color"
        case stylingProfile = "styling_profile"
        case screenAlignment = "screen_alignment"
        case alignment
        case scrollSpeedNormalized = "scroll_speed_normalized"
        case tracking
        case lineItems = "line_items"
        case particlePhysics = "particle_physics"
        case assetId = "asset_id"
        case assetPath = "asset_path"
        case material
        case postProcessFx = "post_process_fx"
        case proceduralField = "procedural_field"
        case colorMap = "color_map"
    }
}

public struct TransformDefinition: Codable {
    public var position: [Float]
    public var rotationDegrees: [Float]?
    public var scale: Float?
    public var billboardMode: String?
    
    enum CodingKeys: String, CodingKey {
        case position
        case rotationDegrees = "rotation_degrees"
        case scale
        case billboardMode = "billboard_mode"
    }
}

public struct AnimationDefinition: Codable {
    public let type: String // "FADE_IN_OUT", "SCALE_IN", "LINEAR_TRANSLATE", etc.
    public let start: Float
    public let end: Float
    public let easeCurve: String?
    public let startPosition: [Float]?
    public let endPosition: [Float]?
    
    enum CodingKeys: String, CodingKey {
        case type, start, end
        case easeCurve = "ease_curve"
        case startPosition = "start_position"
        case endPosition = "end_position"
    }
}

// MARK: - New Definitions for V5.2

public struct ParticlePhysicsDefinition: Codable {
    public let mode: String
    public let emissionRate: Float
    public let lifetimeSeconds: Float
    public let temperatureKelvin: Float
    public let blackbodyEmissionEnabled: Bool
    
    // New V6.3 Parameters
    public let preset: String?
    public let turbulence: Float?
    
    enum CodingKeys: String, CodingKey {
        case mode
        case emissionRate = "emission_rate"
        case lifetimeSeconds = "lifetime_seconds"
        case temperatureKelvin = "temperature_kelvin"
        case blackbodyEmissionEnabled = "blackbody_emission_enabled"
        
        // New V6.3 Parameters
        case preset
        case turbulence
    }
}

public struct MaterialDefinition: Codable {
    public let color: String
    public let reflectivity: Float
    public let glowIntensity: Float
    
    // New V6.0 PBR Parameters (Disney Principled BRDF)
    public let metallic: Float?
    public let roughness: Float?
    public let specular: Float?
    public let specularTint: Float?
    public let sheen: Float?
    public let sheenTint: Float?
    public let clearcoat: Float?
    public let clearcoatGloss: Float?
    public let ior: Float?
    public let transmission: Float?
    public let emissiveIntensity: Float?
    
    enum CodingKeys: String, CodingKey {
        case color, reflectivity
        case glowIntensity = "glow_intensity"
        
        // New V6.0 Keys
        case metallic, roughness, specular
        case specularTint = "specular_tint"
        case sheen
        case sheenTint = "sheen_tint"
        case clearcoat
        case clearcoatGloss = "clearcoat_gloss"
        case ior, transmission
        case emissiveIntensity = "emissive_intensity"
    }
}

public struct PostProcessFXDefinition: Codable {
    public let enabled: Bool
    public let volumetricMaskEnabled: Bool?
    public let gaussianBlurRadius: Float?
    public let chromaticAberration: Float?
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case volumetricMaskEnabled = "volumetric_mask_enabled"
        case gaussianBlurRadius = "gaussian_blur_radius"
        case chromaticAberration = "chromatic_aberration"
    }
}

public struct CreditLineItem: Codable {
    public let role: String
    public let name: String
}

public struct StylingProfileDefinition: Codable {
    public let isH1: Bool
    public let hasSoftGlow: Bool
    public let hasOutline: Bool
    
    enum CodingKeys: String, CodingKey {
        case isH1 = "is_h1"
        case hasSoftGlow = "has_soft_glow"
        case hasOutline = "has_outline"
    }
}

public struct ScreenAlignmentDefinition: Codable {
    public let anchor: String
    public let marginNormalized: [Float]
    public let isScreenSpace: Bool
    
    enum CodingKeys: String, CodingKey {
        case anchor
        case marginNormalized = "margin_normalized"
        case isScreenSpace = "is_screen_space"
    }
}

// MARK: - Legacy Types (Preserved for Engine Compatibility)

public struct VisualContent: Codable, Sendable {
    public let type: String
    public let text: String?
    public let style: String?
    public let layout: String?
    public let animation: String?
    public let zDepth: Float?
    public let shape: String?
    public let size: Double?
    public let color: String?
    public let velocity: [Double]?
    public let outlineWidth: Double?
    public let outlineColor: String?
    public let softness: Double?
    public let weight: Double?
    public let maxWidth: Float?
    public let anchor: String?
    public let rotation: [Float]? // Euler degrees [x, y, z]
    public let fadeStart: Float?
    public let fadeEnd: Float?
    public let tracking: Float? // V6.3
    
    public init(
        type: String,
        text: String? = nil,
        style: String? = nil,
        layout: String? = nil,
        animation: String? = nil,
        zDepth: Float? = nil,
        shape: String? = nil,
        size: Double? = nil,
        color: String? = nil,
        velocity: [Double]? = nil,
        outlineWidth: Double? = nil,
        outlineColor: String? = nil,
        softness: Double? = nil,
        weight: Double? = nil,
        maxWidth: Float? = nil,
        anchor: String? = nil,
        rotation: [Float]? = nil,
        fadeStart: Float? = nil,
        fadeEnd: Float? = nil,
        tracking: Float? = nil
    ) {
        self.type = type
        self.text = text
        self.style = style
        self.layout = layout
        self.animation = animation
        self.zDepth = zDepth
        self.shape = shape
        self.size = size
        self.color = color
        self.velocity = velocity
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
        self.softness = softness
        self.weight = weight
        self.maxWidth = maxWidth
        self.anchor = anchor
        self.rotation = rotation
        self.fadeStart = fadeStart
        self.fadeEnd = fadeEnd
        self.tracking = tracking
    }
}

public struct ManifestValidationCheckpoint: Codable, Sendable {
    public let effect: String
    public let checkpoint: String
}
