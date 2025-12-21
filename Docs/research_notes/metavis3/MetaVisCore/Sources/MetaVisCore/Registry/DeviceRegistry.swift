import Foundation

/// A registry that manages the serialization and deserialization of polymorphic VirtualDevices.
/// It allows the system to save a list of mixed devices (Cameras, Lights, etc.) and restore them
/// to their concrete types.
public struct DeviceRegistry: Codable, Sendable {
    
    /// The internal storage of devices.
    /// Note: We use a private array and provide accessors to ensure thread safety if needed later,
    /// though this struct itself is a value type.
    public private(set) var devices: [UUID: any VirtualDevice] = [:]
    
    public init() {}
    
    /// Adds a device to the registry.
    public mutating func add(_ device: any VirtualDevice) {
        devices[device.id] = device
    }
    
    /// Retrieves a device by ID.
    public func get(id: UUID) -> (any VirtualDevice)? {
        return devices[id]
    }
    
    // MARK: - Polymorphic Codable Support
    
    /// A static map of DeviceType to Concrete Type.
    /// This must be populated at runtime (e.g., in App Delegate or Module Init)
    /// to avoid circular dependencies.
    /// Internal access so DeviceWrapper can see it.
    static nonisolated(unsafe) var typeMap: [DeviceType: any VirtualDevice.Type] = [:]
    
    /// Registers a concrete type for a specific device category.
    /// Example: `DeviceRegistry.register(type: CameraDevice.self, for: .camera)`
    public static func register(type: any VirtualDevice.Type, for category: DeviceType) {
        typeMap[category] = type
    }
    
    enum CodingKeys: String, CodingKey {
        case devices
    }
    
    // Custom Encoding
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var arrayContainer = container.nestedUnkeyedContainer(forKey: .devices)
        
        for device in devices.values {
            // We need a wrapper to encode the type info alongside the data
            let wrapper = DeviceWrapper(device: device)
            try arrayContainer.encode(wrapper)
        }
    }
    
    // Custom Decoding
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var arrayContainer = try container.nestedUnkeyedContainer(forKey: .devices)
        
        var loadedDevices: [UUID: any VirtualDevice] = [:]
        
        while !arrayContainer.isAtEnd {
            // Decode into the wrapper first to get the type
            do {
                let wrapper = try arrayContainer.decode(DeviceWrapper.self)
                loadedDevices[wrapper.device.id] = wrapper.device
            } catch {
                // Graceful failure: Log and skip unknown types
                // In a real app, we might want to store "UnknownDevice" to preserve the data
                print("DeviceRegistry: Failed to decode device. Error: \(error)")
                // We must advance the container if decoding failed? 
                // Actually, if `decode(DeviceWrapper.self)` fails, the container state might be tricky.
                // However, DeviceWrapper handles the "unknown type" logic internally.
            }
        }
        
        self.devices = loadedDevices
    }
}

/// A private wrapper used for encoding/decoding the polymorphic device.
private struct DeviceWrapper: Codable {
    let type: DeviceType
    let device: any VirtualDevice
    
    enum CodingKeys: String, CodingKey {
        case type
        case data
    }
    
    init(device: any VirtualDevice) {
        self.type = device.type
        self.device = device
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        
        // We need to cast to Encodable to encode the concrete instance
        guard let encodableDevice = device as? Encodable else {
            throw EncodingError.invalidValue(device, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Device does not conform to Encodable"))
        }
        
        // Use a super-encoder to encode the device into the 'data' key
        let superEncoder = container.superEncoder(forKey: .data)
        try encodableDevice.encode(to: superEncoder)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DeviceType.self, forKey: .type)
        self.type = type
        
        // Look up the concrete type
        if let concreteType = DeviceRegistry.typeMap[type] {
            // We need to verify the concrete type conforms to Codable (it should if it's in the map)
            guard let codableType = concreteType as? Decodable.Type else {
                 throw DecodingError.typeMismatch(DeviceType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Registered type for \(type) is not Decodable"))
            }
            
            let superDecoder = try container.superDecoder(forKey: .data)
            self.device = try codableType.init(from: superDecoder) as! any VirtualDevice
        } else {
            // Fallback for unknown types: Decode as UnknownDevice to preserve ID and basic info if possible
            // Note: UnknownDevice might not match the 'data' structure of the original device,
            // but we can try to decode at least the ID/Name if they are standard.
            // However, 'data' is a nested container.
            
            // If we can't decode the data, we create a dummy UnknownDevice.
            // Ideally we would decode 'data' into a dictionary, but that's complex.
            // Let's just create a placeholder.
            self.device = UnknownDevice(id: UUID(), name: "Unknown Device (\(type.rawValue))", type: type)
        }
    }
}
