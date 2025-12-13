import Foundation
import simd
import MetaVisCore

/// A manifest describing a pluggable feature (shader/effect).
public struct FeatureManifest: Identifiable, Codable, Sendable {
    /// Unique identifier (e.g., "com.metavis.fx.bloom")
    public let id: String
    
    /// Semantic Version (e.g., "1.0.0")
    public let version: String
    
    /// User-facing display name
    public let name: String
    
    /// Category for UI grouping
    public let category: FeatureCategory
    
    /// Input ports required by this feature
    public let inputs: [PortDefinition]
    
    /// Configurable parameters
    public let parameters: [ParameterDefinition]
    
    /// Name of the Metal kernel function to execute
    public let kernelName: String

    /// Optional multi-pass definition. If present, the feature is executed as an ordered/scheduled set of passes.
    /// Backward compatible: existing manifests continue using `kernelName`.
    public let passes: [FeaturePass]?
    
    public init(
        id: String,
        version: String,
        name: String,
        category: FeatureCategory,
        inputs: [PortDefinition],
        parameters: [ParameterDefinition],
        kernelName: String,
        passes: [FeaturePass]? = nil
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.category = category
        self.inputs = inputs
        self.parameters = parameters
        self.kernelName = kernelName
        self.passes = passes
    }
}

/// A single pass in a multi-pass feature.
public struct FeaturePass: Codable, Sendable, Equatable {
    /// Stable, public identifier for this pass (used by recipes and manifests).
    public let logicalName: String

    /// Concrete Metal compute function name. If nil, it must be resolved via `ShaderRegistry`.
    public let function: String?

    /// Named inputs to this pass. Names can refer to external inputs (e.g. `source`) or prior pass outputs.
    public let inputs: [String]

    /// Named output (intermediate) produced by this pass.
    public let output: String

    public init(logicalName: String, function: String? = nil, inputs: [String], output: String) {
        self.logicalName = logicalName
        self.function = function
        self.inputs = inputs
        self.output = output
    }
}

public enum FeatureCategory: String, Codable, Sendable {
    case color
    case tone
    case blur
    case distortion
    case generative
    case compositing
    case utility
    case specialty
    case style
    case stylize // Restored
    case generator // Restored
}
public struct PortDefinition: Codable, Sendable {
    public let name: String
    public let type: PortType // Using PortType from MetaVisCore if available, otherwise defining minimal
    public let description: String?
    
    public init(name: String, type: PortType = .image, description: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
    }
}

// We need to ensure PortType is available. Since we depend on MetaVisCore, it should be fine.
// If not, we'll need to define it or import it. Assuming MetaVisCore has PortType.
// Checking legacy NodeGraph.swift, PortType was used. Let's assume it exists in the ported Core.
// If usage fails, I will add it.

public enum ParameterDefinition: Codable, Sendable {
    case float(name: String, min: Float, max: Float, default: Float)
    case int(name: String, min: Int, max: Int, default: Int)
    case bool(name: String, default: Bool)
    case color(name: String, default: SIMD4<Float>)
    case vector3(name: String, default: SIMD3<Float>)
    
    // Custom coding keys for enum with associated values
    enum Keys: String, CodingKey {
        case type, name, min, max, defaultValue
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .float(let name, let min, let max, let def):
            try container.encode("float", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(min, forKey: .min)
            try container.encode(max, forKey: .max)
            try container.encode(def, forKey: .defaultValue)
        case .int(let name, let min, let max, let def):
            try container.encode("int", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(min, forKey: .min)
            try container.encode(max, forKey: .max)
            try container.encode(def, forKey: .defaultValue)
        case .bool(let name, let def):
            try container.encode("bool", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(def, forKey: .defaultValue)
        case .color(let name, let def):
            try container.encode("color", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(def, forKey: .defaultValue)
        case .vector3(let name, let def):
            try container.encode("vector3", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(def, forKey: .defaultValue)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let type = try container.decode(String.self, forKey: .type)
        let name = try container.decode(String.self, forKey: .name)
        
        switch type {
        case "float":
            let min = try container.decode(Float.self, forKey: .min)
            let max = try container.decode(Float.self, forKey: .max)
            let def = try container.decode(Float.self, forKey: .defaultValue)
            self = .float(name: name, min: min, max: max, default: def)
        case "int":
            let min = try container.decode(Int.self, forKey: .min)
            let max = try container.decode(Int.self, forKey: .max)
            let def = try container.decode(Int.self, forKey: .defaultValue)
            self = .int(name: name, min: min, max: max, default: def)
        case "bool":
            let def = try container.decode(Bool.self, forKey: .defaultValue)
            self = .bool(name: name, default: def)
        case "color":
            let def = try container.decode(SIMD4<Float>.self, forKey: .defaultValue)
            self = .color(name: name, default: def)
        case "vector3":
            let def = try container.decode(SIMD3<Float>.self, forKey: .defaultValue)
            self = .vector3(name: name, default: def)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown parameter type: \(type)")
        }
    }
}
