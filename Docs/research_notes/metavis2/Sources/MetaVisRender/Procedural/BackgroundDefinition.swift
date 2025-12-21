//
//  BackgroundDefinition.swift
//  MetaVisRender
//
//  Background types for rendering
//

import Foundation
import simd

/// Types of background rendering
public enum BackgroundDefinition: Codable, Sendable {
    case solid(SolidBackground)
    case gradient(GradientBackground)
    case starfield(StarfieldBackground)
    case procedural(ProceduralFieldDefinition)
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    enum BackgroundType: String, Codable {
        case solid
        case gradient
        case starfield
        case procedural
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BackgroundType.self, forKey: .type)
        
        switch type {
        case .solid:
            let solid = try SolidBackground(from: decoder)
            self = .solid(solid)
        case .gradient:
            let gradient = try GradientBackground(from: decoder)
            self = .gradient(gradient)
        case .starfield:
            let starfield = try StarfieldBackground(from: decoder)
            self = .starfield(starfield)
        case .procedural:
            let procedural = try ProceduralFieldDefinition(from: decoder)
            self = .procedural(procedural)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .solid(let solid):
            try container.encode(BackgroundType.solid, forKey: .type)
            try solid.encode(to: encoder)
        case .gradient(let gradient):
            try container.encode(BackgroundType.gradient, forKey: .type)
            try gradient.encode(to: encoder)
        case .starfield(let starfield):
            try container.encode(BackgroundType.starfield, forKey: .type)
            try starfield.encode(to: encoder)
        case .procedural(let procedural):
            try container.encode(BackgroundType.procedural, forKey: .type)
            try procedural.encode(to: encoder)
        }
    }
}

// MARK: - Solid Background

public struct SolidBackground: Codable, Sendable {
    /// Background color in ACEScg
    public var color: SIMD3<Float>
    
    public init(color: SIMD3<Float>) {
        self.color = color
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case color
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let colorArray = try container.decode([Float].self, forKey: .color)
        guard colorArray.count == 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .color,
                in: container,
                debugDescription: "Color must have exactly 3 components"
            )
        }
        color = SIMD3(colorArray[0], colorArray[1], colorArray[2])
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([color.x, color.y, color.z], forKey: .color)
    }
}

// MARK: - Gradient Background

public struct GradientBackground: Codable, Sendable {
    /// Gradient color stops
    public var gradient: [GradientStop]
    
    /// Angle in radians (0 = horizontal, π/2 = vertical)
    public var angle: Float
    
    public init(gradient: [GradientStop], angle: Float = 0.0) {
        self.gradient = gradient
        self.angle = angle
    }
    
    public func validate() throws {
        guard !gradient.isEmpty else {
            throw ValidationError.invalidGradient("Gradient must have at least one stop")
        }
        
        guard gradient.count <= 16 else {
            throw ValidationError.invalidGradient("Gradient can have at most 16 stops")
        }
        
        // Check gradient positions are sorted
        for i in 1..<gradient.count {
            guard gradient[i].position >= gradient[i-1].position else {
                throw ValidationError.invalidGradient("Gradient stops must be sorted by position")
            }
        }
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case gradient
        case angle
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gradient = try container.decode([GradientStop].self, forKey: .gradient)
        angle = try container.decodeIfPresent(Float.self, forKey: .angle) ?? 0.0
        try validate()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(gradient, forKey: .gradient)
        try container.encode(angle, forKey: .angle)
    }
}

// MARK: - Starfield Background

public struct StarfieldBackground: Codable, Sendable {
    /// Base background color (ACEScg)
    public var baseColor: SIMD3<Float>
    
    /// Star tint color (ACEScg)
    public var starColor: SIMD3<Float>
    
    /// Star density (0.0 - 1.0)
    public var density: Float
    
    /// Star brightness multiplier
    public var brightness: Float
    
    /// Twinkle animation speed
    public var twinkleSpeed: Float
    
    /// Random seed for star placement
    public var seed: Int
    
    public init(
        baseColor: SIMD3<Float> = SIMD3(0.0, 0.0, 0.05),
        starColor: SIMD3<Float> = SIMD3(1.0, 1.0, 1.0),
        density: Float = 0.02,
        brightness: Float = 1.0,
        twinkleSpeed: Float = 1.0,
        seed: Int = 42
    ) {
        self.baseColor = baseColor
        self.starColor = starColor
        self.density = density
        self.brightness = brightness
        self.twinkleSpeed = twinkleSpeed
        self.seed = seed
    }
    
    public func validate() throws {
        guard density >= 0.0 && density <= 1.0 else {
            throw ValidationError.invalidParameter("Density must be in range [0, 1]")
        }
        guard brightness > 0 else {
            throw ValidationError.invalidParameter("Brightness must be positive")
        }
        guard twinkleSpeed >= 0 else {
            throw ValidationError.invalidParameter("Twinkle speed must be non-negative")
        }
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case baseColor
        case starColor
        case density
        case brightness
        case twinkleSpeed
        case seed
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let baseColorArray = try container.decodeIfPresent([Float].self, forKey: .baseColor) ?? [0.0, 0.0, 0.05]
        guard baseColorArray.count == 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .baseColor,
                in: container,
                debugDescription: "Base color must have exactly 3 components"
            )
        }
        baseColor = SIMD3(baseColorArray[0], baseColorArray[1], baseColorArray[2])
        
        let starColorArray = try container.decodeIfPresent([Float].self, forKey: .starColor) ?? [1.0, 1.0, 1.0]
        guard starColorArray.count == 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .starColor,
                in: container,
                debugDescription: "Star color must have exactly 3 components"
            )
        }
        starColor = SIMD3(starColorArray[0], starColorArray[1], starColorArray[2])
        
        density = try container.decodeIfPresent(Float.self, forKey: .density) ?? 0.02
        brightness = try container.decodeIfPresent(Float.self, forKey: .brightness) ?? 1.0
        twinkleSpeed = try container.decodeIfPresent(Float.self, forKey: .twinkleSpeed) ?? 1.0
        seed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? 42
        
        try validate()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([baseColor.x, baseColor.y, baseColor.z], forKey: .baseColor)
        try container.encode([starColor.x, starColor.y, starColor.z], forKey: .starColor)
        try container.encode(density, forKey: .density)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(twinkleSpeed, forKey: .twinkleSpeed)
        try container.encode(seed, forKey: .seed)
    }
}

// MARK: - Presets

extension BackgroundDefinition {
    /// Common background presets
    public enum Preset {
        /// Black background
        public static let black: BackgroundDefinition = .solid(
            SolidBackground(color: SIMD3(0.0, 0.0, 0.0))
        )
        
        /// White background
        public static let white: BackgroundDefinition = .solid(
            SolidBackground(color: SIMD3(1.0, 1.0, 1.0))
        )
        
        /// Neutral gray
        public static let gray: BackgroundDefinition = .solid(
            SolidBackground(color: SIMD3(0.18, 0.18, 0.18))
        )
        
        /// Sky gradient
        public static let sky: BackgroundDefinition = .gradient(
            GradientBackground(
                gradient: [
                    GradientStop(color: SIMD3(0.5, 0.7, 1.0), position: 0.0),
                    GradientStop(color: SIMD3(0.1, 0.3, 0.8), position: 1.0)
                ],
                angle: .pi / 2  // Vertical
            )
        )
        
        /// Sunset gradient
        public static let sunset: BackgroundDefinition = .gradient(
            GradientBackground(
                gradient: GradientStop.Preset.sunset,
                angle: .pi / 2  // Vertical
            )
        )
        
        /// Starfield
        public static let stars: BackgroundDefinition = .starfield(
            StarfieldBackground()
        )
        
        /// Nebula procedural
        public static let nebula: BackgroundDefinition = .procedural(
            ProceduralFieldDefinition.Preset.nebula
        )
    }
}
