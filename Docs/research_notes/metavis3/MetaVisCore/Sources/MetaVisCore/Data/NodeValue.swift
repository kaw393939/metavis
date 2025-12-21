import Foundation

/// A strongly-typed value wrapper for Node properties.
/// This replaces the fragile [String: String] dictionary and ensures type safety
/// and correct serialization across different locales.
public enum NodeValue: Codable, Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case float(Double)
    case string(String)
    case vector2(SIMD2<Float>)
    case vector3(SIMD3<Float>)
    case color(SIMD4<Float>) // RGBA
    case uuid(UUID) // Reference to Assets, People, or other Nodes
    
    // Custom coding keys to make the JSON clean
    enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "bool":
            let val = try container.decode(Bool.self, forKey: .value)
            self = .bool(val)
        case "int":
            let val = try container.decode(Int.self, forKey: .value)
            self = .int(val)
        case "float":
            let val = try container.decode(Double.self, forKey: .value)
            self = .float(val)
        case "string":
            let val = try container.decode(String.self, forKey: .value)
            self = .string(val)
        case "vector2":
            let val = try container.decode(SIMD2<Float>.self, forKey: .value)
            self = .vector2(val)
        case "vector3":
            let val = try container.decode(SIMD3<Float>.self, forKey: .value)
            self = .vector3(val)
        case "color":
            let val = try container.decode(SIMD4<Float>.self, forKey: .value)
            self = .color(val)
        case "uuid":
            let val = try container.decode(UUID.self, forKey: .value)
            self = .uuid(val)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown NodeValue type: \(type)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .bool(let val):
            try container.encode("bool", forKey: .type)
            try container.encode(val, forKey: .value)
        case .int(let val):
            try container.encode("int", forKey: .type)
            try container.encode(val, forKey: .value)
        case .float(let val):
            try container.encode("float", forKey: .type)
            try container.encode(val, forKey: .value)
        case .string(let val):
            try container.encode("string", forKey: .type)
            try container.encode(val, forKey: .value)
        case .vector2(let val):
            try container.encode("vector2", forKey: .type)
            try container.encode(val, forKey: .value)
        case .vector3(let val):
            try container.encode("vector3", forKey: .type)
            try container.encode(val, forKey: .value)
        case .color(let val):
            try container.encode("color", forKey: .type)
            try container.encode(val, forKey: .value)
        case .uuid(let val):
            try container.encode("uuid", forKey: .type)
            try container.encode(val, forKey: .value)
        }
    }
}

// Helper accessors
public extension NodeValue {
    var asFloat: Double? {
        if case .float(let v) = self { return v }
        return nil
    }
    
    var asString: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    
    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    
    var floatValue: Float? {
        if case .float(let v) = self { return Float(v) }
        if case .int(let v) = self { return Float(v) }
        return nil
    }
}
