//
//  ProceduralFieldDefinition.swift
//  MetaVisRender
//
//  High-level definition for procedural noise fields
//

import Foundation
import simd

/// Complete definition of a procedural field
public struct ProceduralFieldDefinition: Codable, Sendable {
    // MARK: - Core Parameters
    
    /// Type of noise field
    public var fieldType: FieldType
    
    /// Base frequency of noise (higher = more detail)
    public var frequency: Float
    
    /// Number of octaves for FBM (1-8)
    public var octaves: Int
    
    /// Frequency multiplier between octaves (typically 2.0)
    public var lacunarity: Float
    
    /// Amplitude multiplier between octaves (typically 0.5)
    public var gain: Float
    
    // MARK: - Domain Transformation
    
    /// Type of domain warping
    public var domainWarp: DomainWarpType
    
    /// Strength of domain warp
    public var warpStrength: Float
    
    /// Scale applied to UV coordinates
    public var scale: SIMD2<Float>
    
    /// Offset applied to UV coordinates
    public var offset: SIMD2<Float>
    
    /// Rotation in radians
    public var rotation: Float
    
    // MARK: - Color Mapping
    
    /// Gradient stops for color mapping
    public var gradient: [GradientStop]
    
    /// Whether gradient should loop
    public var loopGradient: Bool
    
    /// Color space interpretation for gradient colors
    /// - "linear": Scene-linear ACEScg, requires ACES tone mapping (matches PBR materials)
    /// - "display": Display-referred perceptual values, directly usable
    public var gradientColorSpace: String
    
    // MARK: - Animation
    
    /// Animation speed (multiplier for time)
    public var animationSpeed: Float
    
    // MARK: - Init
    
    public init(
        fieldType: FieldType,
        frequency: Float = 1.0,
        octaves: Int = 4,
        lacunarity: Float = 2.0,
        gain: Float = 0.5,
        domainWarp: DomainWarpType = .none,
        warpStrength: Float = 0.0,
        scale: SIMD2<Float> = SIMD2(1.0, 1.0),
        offset: SIMD2<Float> = SIMD2(0.0, 0.0),
        rotation: Float = 0.0,
        gradient: [GradientStop] = [],
        loopGradient: Bool = false,
        gradientColorSpace: String = "linear",
        animationSpeed: Float = 1.0
    ) {
        self.fieldType = fieldType
        self.frequency = frequency
        self.octaves = octaves
        self.lacunarity = lacunarity
        self.gain = gain
        self.domainWarp = domainWarp
        self.warpStrength = warpStrength
        self.scale = scale
        self.offset = offset
        self.rotation = rotation
        self.gradient = gradient
        self.loopGradient = loopGradient
        self.gradientColorSpace = gradientColorSpace
        self.animationSpeed = animationSpeed
    }
    
    // MARK: - Validation
    
    /// Validate all parameters
    public func validate() throws {
        // Validate field type specific parameters
        try fieldType.validate(octaves: octaves, frequency: frequency)
        
        // Validate FBM parameters
        if fieldType == .fbm {
            guard lacunarity > 0 else {
                throw ValidationError.invalidParameter("Lacunarity must be positive")
            }
            guard gain > 0 && gain < 1 else {
                throw ValidationError.invalidParameter("Gain must be in range (0, 1)")
            }
        }
        
        // Validate domain warp
        try domainWarp.validate(warpStrength: warpStrength)
        
        // Validate scale
        guard scale.x > 0 && scale.y > 0 else {
            throw ValidationError.invalidParameter("Scale components must be positive")
        }
        
        // Validate gradient
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
        
        // Check first stop is at 0 and last at 1
        guard gradient.first!.position == 0.0 else {
            throw ValidationError.invalidGradient("First gradient stop must be at position 0.0")
        }
        guard gradient.last!.position == 1.0 else {
            throw ValidationError.invalidGradient("Last gradient stop must be at position 1.0")
        }
        
        // Validate animation speed
        guard animationSpeed >= 0 else {
            throw ValidationError.invalidParameter("Animation speed must be non-negative")
        }
    }
    
    // MARK: - GPU Conversion
    
    /// Convert to GPU parameters
    public func toFieldParams(time: Float = 0.0) -> FieldParams {
        // Convert gradientColorSpace string to integer
        let colorSpaceValue: Int32 = (gradientColorSpace.lowercased() == "display") ? 1 : 0
        
        return FieldParams(
            fieldType: fieldType.gpuValue,
            frequency: frequency,
            octaves: Int32(octaves),
            lacunarity: lacunarity,
            gain: gain,
            domainWarp: domainWarp.gpuValue,
            warpStrength: warpStrength,
            scale: scale,
            offset: offset,
            rotation: rotation,
            colorCount: Int32(gradient.count),
            loopGradient: loopGradient ? 1 : 0,
            gradientColorSpace: colorSpaceValue,
            time: time * animationSpeed
        )
    }
    
    /// Convert gradient to GPU format
    public func toGPUGradient() -> [GPUGradientStop] {
        return gradient.map { $0.toGPUFormat() }
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case fieldType
        case frequency
        case octaves
        case lacunarity
        case gain
        case domainWarp
        case warpStrength
        case scale
        case offset
        case rotation
        case gradient
        case loopGradient
        case gradientColorSpace
        case animationSpeed
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        fieldType = try container.decode(FieldType.self, forKey: .fieldType)
        frequency = try container.decodeIfPresent(Float.self, forKey: .frequency) ?? 1.0
        octaves = try container.decodeIfPresent(Int.self, forKey: .octaves) ?? 4
        lacunarity = try container.decodeIfPresent(Float.self, forKey: .lacunarity) ?? 2.0
        gain = try container.decodeIfPresent(Float.self, forKey: .gain) ?? 0.5
        domainWarp = try container.decodeIfPresent(DomainWarpType.self, forKey: .domainWarp) ?? .none
        warpStrength = try container.decodeIfPresent(Float.self, forKey: .warpStrength) ?? 0.0
        
        // Decode scale/offset as arrays
        if let scaleArray = try container.decodeIfPresent([Float].self, forKey: .scale) {
            guard scaleArray.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .scale,
                    in: container,
                    debugDescription: "Scale must have exactly 2 components"
                )
            }
            scale = SIMD2(scaleArray[0], scaleArray[1])
        } else {
            scale = SIMD2(1.0, 1.0)
        }
        
        if let offsetArray = try container.decodeIfPresent([Float].self, forKey: .offset) {
            guard offsetArray.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .offset,
                    in: container,
                    debugDescription: "Offset must have exactly 2 components"
                )
            }
            offset = SIMD2(offsetArray[0], offsetArray[1])
        } else {
            offset = SIMD2(0.0, 0.0)
        }
        
        rotation = try container.decodeIfPresent(Float.self, forKey: .rotation) ?? 0.0
        gradient = try container.decode([GradientStop].self, forKey: .gradient)
        loopGradient = try container.decodeIfPresent(Bool.self, forKey: .loopGradient) ?? false
        gradientColorSpace = try container.decodeIfPresent(String.self, forKey: .gradientColorSpace) ?? "linear"
        animationSpeed = try container.decodeIfPresent(Float.self, forKey: .animationSpeed) ?? 1.0
        
        // Validate after decoding
        try validate()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(fieldType, forKey: .fieldType)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(octaves, forKey: .octaves)
        try container.encode(lacunarity, forKey: .lacunarity)
        try container.encode(gain, forKey: .gain)
        try container.encode(domainWarp, forKey: .domainWarp)
        try container.encode(warpStrength, forKey: .warpStrength)
        try container.encode([scale.x, scale.y], forKey: .scale)
        try container.encode([offset.x, offset.y], forKey: .offset)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(gradient, forKey: .gradient)
        try container.encode(loopGradient, forKey: .loopGradient)
        try container.encode(gradientColorSpace, forKey: .gradientColorSpace)
        try container.encode(animationSpeed, forKey: .animationSpeed)
    }
}

// MARK: - Presets

extension ProceduralFieldDefinition {
    /// Common procedural field presets
    public enum Preset {
        /// Animated nebula cloud
        public static let nebula: ProceduralFieldDefinition = {
            ProceduralFieldDefinition(
                fieldType: .fbm,
                frequency: 2.0,
                octaves: 6,
                lacunarity: 2.2,
                gain: 0.5,
                domainWarp: .advancedFBM,
                warpStrength: 0.3,
                gradient: GradientStop.Preset.nebula,
                animationSpeed: 0.1
            )
        }()
        
        /// Fire effect
        public static let fire: ProceduralFieldDefinition = {
            ProceduralFieldDefinition(
                fieldType: .fbm,
                frequency: 3.0,
                octaves: 5,
                lacunarity: 2.0,
                gain: 0.6,
                domainWarp: .basicFBM,
                warpStrength: 0.5,
                scale: SIMD2(1.0, 2.0),  // Stretch vertically
                gradient: GradientStop.Preset.fire,
                animationSpeed: 0.5
            )
        }()
        
        /// Ocean waves
        public static let ocean: ProceduralFieldDefinition = {
            ProceduralFieldDefinition(
                fieldType: .fbm,
                frequency: 1.5,
                octaves: 4,
                lacunarity: 2.0,
                gain: 0.5,
                domainWarp: .basicFBM,
                warpStrength: 0.2,
                gradient: GradientStop.Preset.ocean,
                animationSpeed: 0.2
            )
        }()
        
        /// Cellular pattern
        public static let cells: ProceduralFieldDefinition = {
            ProceduralFieldDefinition(
                fieldType: .worley,
                frequency: 4.0,
                octaves: 1,
                gradient: [
                    GradientStop(color: SIMD3(0.0, 0.0, 0.0), position: 0.0),
                    GradientStop(color: SIMD3(0.8, 0.8, 0.8), position: 1.0)
                ]
            )
        }()
        
        /// Smooth Perlin clouds
        public static let clouds: ProceduralFieldDefinition = {
            ProceduralFieldDefinition(
                fieldType: .perlin,
                frequency: 2.0,
                octaves: 1,
                gradient: [
                    GradientStop(color: SIMD3(0.2, 0.3, 0.4), position: 0.0),
                    GradientStop(color: SIMD3(0.9, 0.95, 1.0), position: 1.0)
                ],
                animationSpeed: 0.05
            )
        }()
    }
}
