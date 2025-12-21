// LayerDefinition.swift
// MetaVisRender
//
// Created for Sprint 3: Manifest Unification
// Defines layer types for the timeline model

import Foundation
import simd

// MARK: - Transform

/// 3D Transform properties for a layer
public struct Transform: Codable, Sendable {
    /// Position in 3D space (pixels)
    public var position: SIMD3<Float>
    
    /// Rotation in Euler angles (degrees)
    public var rotation: SIMD3<Float>
    
    /// Scale factor (1.0 = 100%)
    public var scale: SIMD3<Float>
    
    /// Anchor point for rotation and scaling (normalized 0-1)
    public var anchorPoint: SIMD3<Float>
    
    public init(
        position: SIMD3<Float> = .zero,
        rotation: SIMD3<Float> = .zero,
        scale: SIMD3<Float> = .one,
        anchorPoint: SIMD3<Float> = SIMD3(0.5, 0.5, 0.5)
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.anchorPoint = anchorPoint
    }
}

// MARK: - TimelineSolidLayer

/// Solid color layer (replaces TextLayer hack)
public struct TimelineSolidLayer: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public var color: SIMD4<Float>  // RGBA
    public var size: SIMD2<Int>?  // Optional, defaults to timeline resolution
    
    // Layer properties
    public var transform: Transform
    public var opacity: Float
    public var blendMode: BlendMode
    
    // Timing
    public var startTime: Double
    public var duration: Double
    
    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        color: SIMD4<Float>,
        size: SIMD2<Int>? = nil,
        transform: Transform = Transform(),
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        startTime: Double = 0,
        duration: Double = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.size = size
        self.transform = transform
        self.opacity = opacity
        self.blendMode = blendMode
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - TimelineAdjustmentLayer

/// Adjustment layer for applying effects to layers below
public struct TimelineAdjustmentLayer: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    
    // Layer properties
    public var transform: Transform
    public var opacity: Float
    public var blendMode: BlendMode
    
    // Effects
    public var effects: [TimelineEffect]
    
    // Timing
    public var startTime: Double
    public var duration: Double
    
    public init(
        id: String = UUID().uuidString,
        name: String? = nil,
        transform: Transform = Transform(),
        opacity: Float = 1.0,
        blendMode: BlendMode = .normal,
        effects: [TimelineEffect] = [],
        startTime: Double = 0,
        duration: Double = 0
    ) {
        self.id = id
        self.name = name
        self.transform = transform
        self.opacity = opacity
        self.blendMode = blendMode
        self.effects = effects
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - TimelineEffect

/// Visual effect applied to a layer
public enum TimelineEffect: Codable, Sendable {
    case blur(radius: Float)
    case colorGrade(lut: String)
    // Add more as needed
    
    enum CodingKeys: String, CodingKey {
        case type
        case radius
        case lut
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "blur":
            let radius = try container.decode(Float.self, forKey: .radius)
            self = .blur(radius: radius)
        case "colorGrade":
            let lut = try container.decode(String.self, forKey: .lut)
            self = .colorGrade(lut: lut)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown effect type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .blur(let radius):
            try container.encode("blur", forKey: .type)
            try container.encode(radius, forKey: .radius)
        case .colorGrade(let lut):
            try container.encode("colorGrade", forKey: .type)
            try container.encode(lut, forKey: .lut)
        }
    }
}
