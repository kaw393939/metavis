import Foundation
import simd

// MARK: - Node Graph Data Model

/// A node-based processing graph.
public struct NodeGraph: Codable, Sendable {
    public var nodes: [GraphNode]
    public var connections: [NodeConnection]
    public var rootNodeId: String // The final output node
    
    public init(nodes: [GraphNode] = [], connections: [NodeConnection] = [], rootNodeId: String = "") {
        self.nodes = nodes
        self.connections = connections
        self.rootNodeId = rootNodeId
    }
}

/// A single node in the graph.
public struct GraphNode: Codable, Sendable, Identifiable {
    public let id: String
    public var type: NodeType
    public var name: String
    public var position: SIMD2<Float> // UI position
    public var properties: [String: NodeValue] // Internal parameters (not inputs)
    
    public init(id: String = UUID().uuidString, type: NodeType, name: String, position: SIMD2<Float> = .zero, properties: [String: NodeValue] = [:]) {
        self.id = id
        self.type = type
        self.name = name
        self.position = position
        self.properties = properties
    }
}

/// Types of nodes available in the system.
public enum NodeType: String, Codable, Sendable {
    case input // Source footage, image, etc.
    case output // Final render target
    case composite // Blend two inputs
    case transform // 2D/3D transform
    case filter // Blur, Color Correct, etc.
    case generator // Solid, Gradient, Noise
    case text // Text rendering
    case time // Time manipulation
    case pbr // Physically Based Rendering
    case halation // Film halation
    case bloom // Light bloom
    case vignette // Vignette
    case grain // Film grain
    case segmentation // AI Segmentation
}

/// A connection between two nodes.
public struct NodeConnection: Codable, Sendable, Identifiable {
    public var id: String { "\(fromNodeId):\(fromPinId)->\(toNodeId):\(toPinId)" }
    
    public let fromNodeId: String
    public let fromPinId: String
    public let toNodeId: String
    public let toPinId: String
    
    public init(fromNodeId: String, fromPinId: String, toNodeId: String, toPinId: String) {
        self.fromNodeId = fromNodeId
        self.fromPinId = fromPinId
        self.toNodeId = toNodeId
        self.toPinId = toPinId
    }
}

/// Values that can be stored in node properties or passed between pins.
public enum NodeValue: Codable, Sendable {
    case float(Float)
    case vector2(SIMD2<Float>)
    case vector3(SIMD3<Float>)
    case vector4(SIMD4<Float>)
    case color(SIMD3<Float>)
    case string(String)
    case bool(Bool)
    case enumValue(String)
    
    enum CodingKeys: String, CodingKey {
        case float, vector2, vector3, vector4, color, string, bool, enumValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Float.self, forKey: .float) {
            self = .float(value)
        } else if let value = try? container.decode(SIMD2<Float>.self, forKey: .vector2) {
            self = .vector2(value)
        } else if let value = try? container.decode(SIMD3<Float>.self, forKey: .vector3) {
            self = .vector3(value)
        } else if let value = try? container.decode(SIMD4<Float>.self, forKey: .vector4) {
            self = .vector4(value)
        } else if let value = try? container.decode(SIMD3<Float>.self, forKey: .color) {
            self = .color(value)
        } else if let value = try? container.decode(String.self, forKey: .string) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self, forKey: .bool) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self, forKey: .enumValue) {
            self = .enumValue(value)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: "Invalid NodeValue"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .float(let v): try container.encode(v, forKey: .float)
        case .vector2(let v): try container.encode(v, forKey: .vector2)
        case .vector3(let v): try container.encode(v, forKey: .vector3)
        case .vector4(let v): try container.encode(v, forKey: .vector4)
        case .color(let v): try container.encode(v, forKey: .color)
        case .string(let v): try container.encode(v, forKey: .string)
        case .bool(let v): try container.encode(v, forKey: .bool)
        case .enumValue(let v): try container.encode(v, forKey: .enumValue)
        }
    }
    
    // Helper accessors
    public var floatValue: Float? {
        if case .float(let v) = self { return v }
        return nil
    }
}
