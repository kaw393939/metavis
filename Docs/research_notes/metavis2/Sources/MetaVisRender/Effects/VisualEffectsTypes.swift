import Foundation
import simd

// MARK: - Visual Effects Data Types

/// Video element with visual effects support
public struct VideoElement: Codable, Sendable {
    // Core properties
    public let source: String                    // File path or URL
    public let timeRange: ClosedRange<Double>?  // Optional trim range (seconds)
    
    // Position and size
    public let position: SIMD3<Float>           // x, y, z position
    public let scale: SIMD2<Float>              // Scale factor
    
    // Timing
    public let startTime: Float                 // When video starts playing
    public let duration: Float                  // How long to play (0 = full length)
    
    // Sprint 04: Visual Effects
    public let effect: VideoEffect?             // Primary effect (semantic_key)
    public let semanticKeyConfig: SemanticKeyConfig?  // Config for semantic keying
    public let effects: [SelectiveEffectConfig]?      // Additional selective effects
    
    // Audio
    public let muted: Bool                      // Mute video audio
    public let volume: Float                    // Volume level (0-1)
    
    public init(
        source: String,
        timeRange: ClosedRange<Double>? = nil,
        position: SIMD3<Float> = SIMD3(0, 0, 0),
        scale: SIMD2<Float> = SIMD2(1, 1),
        startTime: Float = 0,
        duration: Float = 0,
        effect: VideoEffect? = nil,
        semanticKeyConfig: SemanticKeyConfig? = nil,
        effects: [SelectiveEffectConfig]? = nil,
        muted: Bool = false,
        volume: Float = 1.0
    ) {
        self.source = source
        self.timeRange = timeRange
        self.position = position
        self.scale = scale
        self.startTime = startTime
        self.duration = duration
        self.effect = effect
        self.semanticKeyConfig = semanticKeyConfig
        self.effects = effects
        self.muted = muted
        self.volume = volume
    }
}

// MARK: - Video Effects

/// Primary video effect types
public enum VideoEffect: String, Codable, CaseIterable, Sendable {
    case semanticKey = "semantic_key"  // Auto-greenscreen using AI segmentation
}

/// Configuration for semantic keying (auto-greenscreen)
public struct SemanticKeyConfig: Codable, Sendable {
    /// Background image/video to replace with
    public let background: String
    /// Edge feathering amount (0.0-1.0)
    public let edgeFeather: Float
    /// Enable spill suppression
    public let spillSuppression: Bool
    /// Quality level ("fast", "balanced", "accurate")
    public let quality: String
    
    public init(
        background: String,
        edgeFeather: Float = 0.02,
        spillSuppression: Bool = true,
        quality: String = "balanced"
    ) {
        self.background = background
        self.edgeFeather = edgeFeather
        self.spillSuppression = spillSuppression
        self.quality = quality
    }
    
    public enum CodingKeys: String, CodingKey {
        case background
        case edgeFeather = "edge_feather"
        case spillSuppression = "spill_suppression"
        case quality
    }
}

/// Configuration for selective effects (blur, desaturate, etc.)
public struct SelectiveEffectConfig: Codable, Sendable {
    /// Effect type
    public let type: SelectiveEffectType
    /// Effect parameters
    public let parameters: [String: Float]
    
    public init(type: SelectiveEffectType, parameters: [String: Float] = [:]) {
        self.type = type
        self.parameters = parameters
    }
}

/// Types of selective effects
public enum SelectiveEffectType: String, Codable, CaseIterable, Sendable {
    case backgroundBlur = "background_blur"
    case backgroundDesaturate = "background_desaturate"
    case foregroundGlow = "foreground_glow"
}

// MARK: - Occlusion Configuration

/// Reference to another element for occlusion
public struct ElementReference: Codable, Sendable {
    /// Type of element ("video", "image")
    public let type: String
    /// Index of the element in the elements array
    public let index: Int?
    /// Optional explicit element ID
    public let id: String?
    
    public init(type: String, index: Int? = nil, id: String? = nil) {
        self.type = type
        self.index = index
        self.id = id
    }
}

/// Configuration for element occlusion
public struct OcclusionConfig: Codable, Sendable {
    /// Which element occludes this one
    public let occludedBy: ElementReference
    /// Edge blending amount
    public let edgeBlend: Float
    
    public init(occludedBy: ElementReference, edgeBlend: Float = 0.01) {
        self.occludedBy = occludedBy
        self.edgeBlend = edgeBlend
    }
    
    public enum CodingKeys: String, CodingKey {
        case occludedBy = "occluded_by"
        case edgeBlend = "edge_blend"
    }
}

// MARK: - Smart Placement Configuration

/// Configuration for AI-powered text placement
public struct AutoPlaceConfig: Codable, Sendable {
    /// Enable auto-placement
    public let enabled: Bool
    /// Preferred anchor positions (in order of preference)
    public let preferredAnchors: [String]
    /// Avoid detected faces
    public let avoidFaces: Bool
    /// Minimum clearance from other elements (normalized 0-1)
    public let minClearance: Float
    /// Saliency threshold for safe zones (0-1)
    public let saliencyThreshold: Float
    
    public init(
        enabled: Bool = true,
        preferredAnchors: [String] = ["bottomRight", "bottomLeft"],
        avoidFaces: Bool = true,
        minClearance: Float = 0.05,
        saliencyThreshold: Float = 0.3
    ) {
        self.enabled = enabled
        self.preferredAnchors = preferredAnchors
        self.avoidFaces = avoidFaces
        self.minClearance = minClearance
        self.saliencyThreshold = saliencyThreshold
    }
    
    public enum CodingKeys: String, CodingKey {
        case enabled
        case preferredAnchors = "preferred_anchors"
        case avoidFaces = "avoid_faces"
        case minClearance = "min_clearance"
        case saliencyThreshold = "saliency_threshold"
    }
}

// MARK: - Extended Text Element

/// Extended text element configuration with Sprint 04 features
public struct TextElementEffects: Codable, Sendable {
    /// Occlusion configuration (render behind subject)
    public let occlusionConfig: OcclusionConfig?
    /// Auto-placement configuration
    public let autoPlaceConfig: AutoPlaceConfig?
    
    public init(
        occlusionConfig: OcclusionConfig? = nil,
        autoPlaceConfig: AutoPlaceConfig? = nil
    ) {
        self.occlusionConfig = occlusionConfig
        self.autoPlaceConfig = autoPlaceConfig
    }
    
    public enum CodingKeys: String, CodingKey {
        case occlusionConfig = "occlusion_config"
        case autoPlaceConfig = "auto_place_config"
    }
}

// MARK: - Manifest Extension Helpers

extension SelectiveEffectConfig {
    /// Blur radius (default 20)
    public var blurRadius: Float {
        parameters["radius"] ?? 20.0
    }
    
    /// Desaturation amount (default 0.5)
    public var desaturateAmount: Float {
        parameters["amount"] ?? 0.5
    }
    
    /// Glow intensity (default 0.3)
    public var glowIntensity: Float {
        parameters["intensity"] ?? 0.3
    }
}

extension SemanticKeyConfig {
    /// Convert quality string to VisionProvider quality
    public var segmentationQuality: VisionProvider.SegmentationQuality {
        switch quality.lowercased() {
        case "fast": return .fast
        case "accurate": return .accurate
        default: return .balanced
        }
    }
}
