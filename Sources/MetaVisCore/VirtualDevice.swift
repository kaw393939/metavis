import Foundation

/// Represents the capability of a device.
public enum DeviceType: String, Codable, Sendable {
    case camera
    case light
    case generator
    case screen
    case hardware
    case unknown
}

/// Represents a value update for a device property.
/// Implementation Detail: This will eventually be a rich enum supporting Float, String, Vector3, etc.
public enum NodeValue: Codable, Sendable, Equatable {
    case float(Double)
    case string(String)
    case bool(Bool)
    case vector3(SIMD3<Double>)
    case color(SIMD4<Double>)
    case floatArray([Float]) // Added for buffer binding (e.g. Face Rects)
    case data(Data) // For complex blobs (LUTs)
}

/// Defines an action that a device can perform.
public struct ActionDefinition: Codable, Sendable {
    public let name: String
    public let description: String
    public let parameters: [String: String] // Name: Type
    
    public init(name: String, description: String, parameters: [String : String] = [:]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// The atomic unit of capability in MetaVis.
/// Any entity that can be controlled (Camera, Light, AI Service) must conform to this.
public protocol VirtualDevice: Sendable, Identifiable {
    var id: UUID { get }
    var name: String { get }
    var deviceType: DeviceType { get }
    
    /// The educational manifest for this device.
    var knowledgeBase: DeviceKnowledgeBase { get }
    
    /// Current state of the device.
    var properties: [String: NodeValue] { get async }
    
    /// Capabilities of the device.
    var actions: [String: ActionDefinition] { get }
    
    /// Perform an action and return outputs.
    @discardableResult
    func perform(action: String, with params: [String: NodeValue]) async throws -> [String: NodeValue]
    
    /// Update a property.
    func setProperty(_ key: String, to value: NodeValue) async throws
}
