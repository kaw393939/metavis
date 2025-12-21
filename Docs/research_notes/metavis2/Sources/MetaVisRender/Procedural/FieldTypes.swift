//
//  FieldTypes.swift
//  MetaVisRender
//
//  Type definitions for procedural field generation
//

import Foundation
import simd

/// Type of procedural noise field
public enum FieldType: String, Codable, Sendable {
    case perlin
    case simplex
    case worley
    case fbm
    
    /// Convert to GPU integer value
    var gpuValue: Int32 {
        switch self {
        case .perlin: return 0
        case .simplex: return 1
        case .worley: return 2
        case .fbm: return 3
        }
    }
}

/// Type of domain warp
public enum DomainWarpType: String, Codable, Sendable {
    case none
    case basicFBM
    case advancedFBM
    
    /// Convert to GPU integer value
    var gpuValue: Int32 {
        switch self {
        case .none: return 0
        case .basicFBM: return 1
        case .advancedFBM: return 2
        }
    }
}

/// Parameters for procedural field generation
/// MUST match FieldParams struct in FieldKernels.metal exactly
public struct FieldParams: Sendable {
    public var fieldType: Int32
    public var frequency: Float
    public var octaves: Int32
    public var lacunarity: Float
    public var gain: Float
    public var domainWarp: Int32
    public var warpStrength: Float
    public var scale: SIMD2<Float>
    public var offset: SIMD2<Float>
    public var rotation: Float
    public var colorCount: Int32
    public var loopGradient: Int32
    public var gradientColorSpace: Int32  // 0=linear (scene-referred), 1=display (perceptual)
    public var time: Float
    
    public init(
        fieldType: Int32,
        frequency: Float = 1.0,
        octaves: Int32 = 4,
        lacunarity: Float = 2.0,
        gain: Float = 0.5,
        domainWarp: Int32 = 0,
        warpStrength: Float = 0.0,
        scale: SIMD2<Float> = SIMD2(1.0, 1.0),
        offset: SIMD2<Float> = SIMD2(0.0, 0.0),
        rotation: Float = 0.0,
        colorCount: Int32 = 0,
        loopGradient: Int32 = 0,
        gradientColorSpace: Int32 = 0,
        time: Float = 0.0
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
        self.colorCount = colorCount
        self.loopGradient = loopGradient
        self.gradientColorSpace = gradientColorSpace
        self.time = time
    }
}

// MARK: - Validation Helpers

extension FieldType {
    /// Validate field-specific parameters
    func validate(octaves: Int, frequency: Float) throws {
        switch self {
        case .perlin, .simplex, .worley:
            if octaves != 1 {
                print("Warning: \(self.rawValue) ignores octaves parameter (using 1)")
            }
        case .fbm:
            guard octaves >= 1 && octaves <= 8 else {
                throw ValidationError.invalidParameter(
                    "FBM octaves must be 1-8, got \(octaves)"
                )
            }
        }
        
        guard frequency > 0 else {
            throw ValidationError.invalidParameter(
                "Frequency must be positive, got \(frequency)"
            )
        }
    }
}

extension DomainWarpType {
    /// Validate warp-specific parameters
    func validate(warpStrength: Float) throws {
        switch self {
        case .none:
            if warpStrength != 0.0 {
                print("Warning: no domain warp but warpStrength=\(warpStrength) (ignored)")
            }
        case .basicFBM, .advancedFBM:
            guard warpStrength >= 0 else {
                throw ValidationError.invalidParameter(
                    "Warp strength must be non-negative, got \(warpStrength)"
                )
            }
        }
    }
}

// MARK: - Errors

public enum ValidationError: Error, CustomStringConvertible {
    case invalidParameter(String)
    case invalidGradient(String)
    case missingRequiredField(String)
    case unsupportedConfiguration(String)
    
    public var description: String {
        switch self {
        case .invalidParameter(let msg): return "Invalid parameter: \(msg)"
        case .invalidGradient(let msg): return "Invalid gradient: \(msg)"
        case .missingRequiredField(let field): return "Missing required field: \(field)"
        case .unsupportedConfiguration(let msg): return "Unsupported configuration: \(msg)"
        }
    }
}
