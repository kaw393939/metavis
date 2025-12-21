//
//  LayerSystem.swift
//  MetaVisRender
//
//  Layer-based compositing system for complex multi-source projects
//

import Foundation
import simd

// MARK: - Layer System

/// A compositing layer that can contain video, graphics, or effects
public enum Layer: Codable, Sendable {
    case video(VideoLayer)
    case graphics(GraphicsLayer)
    case procedural(ProceduralLayer)
    case solid(SolidLayer)
    case adjustment(AdjustmentLayer)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type.lowercased() {
        case "video":
            self = .video(try VideoLayer(from: decoder))
        case "graphics":
            self = .graphics(try GraphicsLayer(from: decoder))
        case "procedural":
            self = .procedural(try ProceduralLayer(from: decoder))
        case "solid":
            self = .solid(try SolidLayer(from: decoder))
        case "adjustment":
            self = .adjustment(try AdjustmentLayer(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown layer type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .video(let layer):
            try container.encode("video", forKey: .type)
            try layer.encode(to: encoder)
        case .graphics(let layer):
            try container.encode("graphics", forKey: .type)
            try layer.encode(to: encoder)
        case .procedural(let layer):
            try container.encode("procedural", forKey: .type)
            try layer.encode(to: encoder)
        case .solid(let layer):
            try container.encode("solid", forKey: .type)
            try layer.encode(to: encoder)
        case .adjustment(let layer):
            try container.encode("adjustment", forKey: .type)
            try layer.encode(to: encoder)
        }
    }
    
    /// Common layer properties accessor
    public var baseProperties: LayerProperties {
        switch self {
        case .video(let l): return l.base
        case .graphics(let l): return l.base
        case .procedural(let l): return l.base
        case .solid(let l): return l.base
        case .adjustment(let l): return l.base
        }
    }
}

/// Common properties for all layer types
public struct LayerProperties: Codable, Sendable {
    public let name: String
    public let enabled: Bool
    public let opacity: Float
    public let blendMode: BlendMode
    public let startTime: Float
    public let duration: Float
    public let trackMatte: TrackMatte?
    
    public init(
        name: String,
        enabled: Bool = true,
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        startTime: Float = 0.0,
        duration: Float = 0.0,
        trackMatte: TrackMatte? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.opacity = opacity
        self.blendMode = blendMode
        self.startTime = startTime
        self.duration = duration
        self.trackMatte = trackMatte
    }
}

public struct TrackMatte: Codable, Sendable {
    public let sourceLayer: String
    public let mode: MatteMode
    
    public enum MatteMode: String, Codable, Sendable {
        case alpha
        case invertedAlpha
        case luma
        case invertedLuma
    }
}

/// Video layer - plays back video files
public struct VideoLayer: Codable, Sendable {
    public let base: LayerProperties
    public let source: SourceDefinition
    public let timeRemap: TimeRemapMode?
    
    public init(base: LayerProperties, source: SourceDefinition, timeRemap: TimeRemapMode? = nil) {
        self.base = base
        self.source = source
        self.timeRemap = timeRemap
    }
}

public enum TimeRemapMode: Codable, Sendable {
    case speed(Float)
    case freeze(Float)
    case reverse
    case pingPong
    
    enum CodingKeys: String, CodingKey {
        case mode
        case value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        
        switch mode.lowercased() {
        case "speed":
            let value = try container.decode(Float.self, forKey: .value)
            self = .speed(value)
        case "freeze":
            let value = try container.decode(Float.self, forKey: .value)
            self = .freeze(value)
        case "reverse":
            self = .reverse
        case "pingpong":
            self = .pingPong
        default:
            self = .speed(1.0)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .speed(let value):
            try container.encode("speed", forKey: .mode)
            try container.encode(value, forKey: .value)
        case .freeze(let time):
            try container.encode("freeze", forKey: .mode)
            try container.encode(time, forKey: .value)
        case .reverse:
            try container.encode("reverse", forKey: .mode)
        case .pingPong:
            try container.encode("pingPong", forKey: .mode)
        }
    }
}

/// Graphics layer - contains text, shapes, and 3D elements
public struct GraphicsLayer: Codable, Sendable {
    public let base: LayerProperties
    public let elements: [ManifestElement]
    
    public init(base: LayerProperties, elements: [ManifestElement]) {
        self.base = base
        self.elements = elements
    }
}

/// Procedural layer - GPU-generated backgrounds
public struct ProceduralLayer: Codable, Sendable {
    public let base: LayerProperties
    public let background: BackgroundDefinition
    
    public init(base: LayerProperties, background: BackgroundDefinition) {
        self.base = base
        self.background = background
    }
}

/// Solid color layer
public struct SolidLayer: Codable, Sendable {
    public let base: LayerProperties
    public let color: SIMD4<Float>
    
    public init(base: LayerProperties, color: SIMD4<Float>) {
        self.base = base
        self.color = color
    }
}

/// Adjustment layer - applies effects to all layers below
public struct AdjustmentLayer: Codable, Sendable {
    public let base: LayerProperties
    public let effects: [Effect]
    
    public init(base: LayerProperties, effects: [Effect]) {
        self.base = base
        self.effects = effects
    }
}

public enum Effect: Codable, Sendable {
    case colorCorrection(ColorCorrectionEffect)
    case blur(BlurEffect)
    case sharpen(SharpenEffect)
    case glow(GlowEffect)
    case chromaticAberration(ChromaticAberrationEffect)
    case vignette(VignetteEffect)
    case filmGrain(FilmGrainEffect)
    
    enum CodingKeys: String, CodingKey {
        case effectType
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .effectType)
        
        switch type.lowercased() {
        case "colorcorrection":
            self = .colorCorrection(try ColorCorrectionEffect(from: decoder))
        case "blur":
            self = .blur(try BlurEffect(from: decoder))
        case "sharpen":
            self = .sharpen(try SharpenEffect(from: decoder))
        case "glow":
            self = .glow(try GlowEffect(from: decoder))
        case "chromaticaberration":
            self = .chromaticAberration(try ChromaticAberrationEffect(from: decoder))
        case "vignette":
            self = .vignette(try VignetteEffect(from: decoder))
        case "filmgrain":
            self = .filmGrain(try FilmGrainEffect(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .effectType, in: container, debugDescription: "Unknown effect type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .colorCorrection(let effect):
            try container.encode("colorCorrection", forKey: .effectType)
            try effect.encode(to: encoder)
        case .blur(let effect):
            try container.encode("blur", forKey: .effectType)
            try effect.encode(to: encoder)
        case .sharpen(let effect):
            try container.encode("sharpen", forKey: .effectType)
            try effect.encode(to: encoder)
        case .glow(let effect):
            try container.encode("glow", forKey: .effectType)
            try effect.encode(to: encoder)
        case .chromaticAberration(let effect):
            try container.encode("chromaticAberration", forKey: .effectType)
            try effect.encode(to: encoder)
        case .vignette(let effect):
            try container.encode("vignette", forKey: .effectType)
            try effect.encode(to: encoder)
        case .filmGrain(let effect):
            try container.encode("filmGrain", forKey: .effectType)
            try effect.encode(to: encoder)
        }
    }
}

public struct ColorCorrectionEffect: Codable, Sendable {
    public let exposure: Float
    public let contrast: Float
    public let saturation: Float
    public let temperature: Float
    public let tint: Float
    
    public init(exposure: Float = 0.0, contrast: Float = 1.0, saturation: Float = 1.0, temperature: Float = 0.0, tint: Float = 0.0) {
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.tint = tint
    }
}

public struct BlurEffect: Codable, Sendable {
    public let radius: Float
    public let quality: String // "low", "medium", "high"
    
    public init(radius: Float, quality: String = "medium") {
        self.radius = radius
        self.quality = quality
    }
}

public struct SharpenEffect: Codable, Sendable {
    public let amount: Float
    public let radius: Float
    
    public init(amount: Float, radius: Float = 1.0) {
        self.amount = amount
        self.radius = radius
    }
}

public struct GlowEffect: Codable, Sendable {
    public let intensity: Float
    public let threshold: Float
    public let radius: Float
    
    public init(intensity: Float, threshold: Float = 0.8, radius: Float = 10.0) {
        self.intensity = intensity
        self.threshold = threshold
        self.radius = radius
    }
}

public struct ChromaticAberrationEffect: Codable, Sendable {
    public let amount: Float
    
    public init(amount: Float) {
        self.amount = amount
    }
}

public struct VignetteEffect: Codable, Sendable {
    public let intensity: Float
    public let smoothness: Float
    
    public init(intensity: Float, smoothness: Float = 0.5) {
        self.intensity = intensity
        self.smoothness = smoothness
    }
}

public struct FilmGrainEffect: Codable, Sendable {
    public let intensity: Float
    public let size: Float
    
    public init(intensity: Float, size: Float = 1.0) {
        self.intensity = intensity
        self.size = size
    }
}
