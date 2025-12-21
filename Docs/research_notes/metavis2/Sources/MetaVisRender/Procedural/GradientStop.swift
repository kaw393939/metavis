//
//  GradientStop.swift
//  MetaVisRender
//
//  Gradient color stops for procedural field mapping
//

import Foundation
import simd

/// A color stop in a gradient
/// Colors are in ACEScg color space
public struct GradientStop: Codable, Sendable {
    /// Color in ACEScg space
    public var color: SIMD3<Float>
    
    /// Position in gradient [0, 1]
    public var position: Float
    
    public init(color: SIMD3<Float>, position: Float) {
        self.color = color
        self.position = position
    }
    
    /// Convert to Metal-compatible format
    func toGPUFormat() -> GPUGradientStop {
        return GPUGradientStop(color: color, position: position)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case color
        case position
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode color as array [r, g, b]
        let colorArray = try container.decode([Float].self, forKey: .color)
        guard colorArray.count == 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .color,
                in: container,
                debugDescription: "Color must have exactly 3 components"
            )
        }
        color = SIMD3(colorArray[0], colorArray[1], colorArray[2])
        
        position = try container.decode(Float.self, forKey: .position)
        
        // Validate
        guard position >= 0.0 && position <= 1.0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .position,
                in: container,
                debugDescription: "Position must be in range [0, 1]"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([color.x, color.y, color.z], forKey: .color)
        try container.encode(position, forKey: .position)
    }
}

/// GPU-compatible gradient stop (matches Metal struct)
public struct GPUGradientStop {
    var color: SIMD3<Float>
    var position: Float
    
    init(color: SIMD3<Float>, position: Float) {
        self.color = color
        self.position = position
    }
}

// MARK: - Presets

extension GradientStop {
    /// Common gradient presets
    public enum Preset {
        /// Purple to orange nebula
        public static let nebula: [GradientStop] = [
            GradientStop(color: SIMD3(0.05, 0.0, 0.15), position: 0.0),
            GradientStop(color: SIMD3(1.2, 0.4, 0.0), position: 0.5),
            GradientStop(color: SIMD3(0.0, 0.9, 1.5), position: 1.0)
        ]
        
        /// Fire gradient
        public static let fire: [GradientStop] = [
            GradientStop(color: SIMD3(0.0, 0.0, 0.0), position: 0.0),
            GradientStop(color: SIMD3(0.8, 0.0, 0.0), position: 0.3),
            GradientStop(color: SIMD3(1.5, 0.5, 0.0), position: 0.6),
            GradientStop(color: SIMD3(2.0, 1.5, 0.5), position: 1.0)
        ]
        
        /// Ocean gradient
        public static let ocean: [GradientStop] = [
            GradientStop(color: SIMD3(0.0, 0.05, 0.1), position: 0.0),
            GradientStop(color: SIMD3(0.0, 0.3, 0.6), position: 0.5),
            GradientStop(color: SIMD3(0.3, 0.8, 1.2), position: 1.0)
        ]
        
        /// Forest gradient
        public static let forest: [GradientStop] = [
            GradientStop(color: SIMD3(0.05, 0.1, 0.0), position: 0.0),
            GradientStop(color: SIMD3(0.1, 0.4, 0.1), position: 0.5),
            GradientStop(color: SIMD3(0.5, 1.0, 0.3), position: 1.0)
        ]
        
        /// Sunset gradient
        public static let sunset: [GradientStop] = [
            GradientStop(color: SIMD3(0.1, 0.05, 0.15), position: 0.0),
            GradientStop(color: SIMD3(1.2, 0.3, 0.2), position: 0.4),
            GradientStop(color: SIMD3(1.8, 0.8, 0.3), position: 0.7),
            GradientStop(color: SIMD3(0.3, 0.5, 0.9), position: 1.0)
        ]
    }
}
