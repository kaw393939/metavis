import Foundation

/// Defines the category of a virtual device.
public enum DeviceType: String, Codable, Sendable, Equatable {
    case camera
    case light
    case screen
    case generator
    case audio
    case sensor
    case colorEngine // ACES / Grading Pipeline
    case analyzer // Deterministic QA
    case critic // AI/LLM Qualitative QA
    case unknown
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        // print("Decoding DeviceType: \(rawValue)")
        self = DeviceType(rawValue: rawValue) ?? .unknown
    }
}

/// Represents the operational state of a device.
public enum DeviceState: String, Codable, Sendable, Equatable {
    case offline
    case online
    case active // e.g., recording or generating
    case error
}

/// A type-safe, Sendable wrapper for device parameters.
public enum DeviceParameterValue: Codable, Sendable, Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
    
    // Helper accessors
    public var asInt: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
    
    public var asFloat: Double? {
        if case .float(let v) = self { return v }
        return nil
    }
    
    public var asString: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    
    public var asBool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

/// The protocol that all Virtual Devices must conform to.
/// A Virtual Device is any entity that can be controlled by the MetaVis system,
/// whether it's a physical camera, a software generator, or a virtual light.
public protocol VirtualDevice: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var type: DeviceType { get }
    var state: DeviceState { get set }
    var parameters: [String: DeviceParameterValue] { get }
    
    /// Updates a parameter on the device.
    mutating func set(parameter: String, value: DeviceParameterValue)
    
    /// Executes a specific action on the device.
    func execute(action: String) async throws
}

/// A placeholder for devices that cannot be decoded (e.g. from a future version).
public struct UnknownDevice: VirtualDevice, Codable {
    public let id: UUID
    public var name: String
    public let type: DeviceType
    public var state: DeviceState = .offline
    public var parameters: [String: DeviceParameterValue] = [:]
    
    public init(id: UUID = UUID(), name: String, type: DeviceType = .unknown) {
        self.id = id
        self.name = name
        self.type = type
    }
    
    public mutating func set(parameter: String, value: DeviceParameterValue) {
        parameters[parameter] = value
    }
    
    public func execute(action: String) async throws {
        // No-op
    }
}


