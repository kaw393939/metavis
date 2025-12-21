import Foundation

/// Represents the Global Color Management System (ACES) as a controllable device.
/// This allows the "Cinematic OS" to control the look of the entire pipeline
/// via standard device commands (e.g. "Set ODT to Rec.709", "Increase Global Contrast").
public struct ACESDevice: VirtualDevice, Codable, Sendable {
    public let id: UUID
    public let deviceId: String
    public var name: String
    public var type: DeviceType = .colorEngine
    public var state: DeviceState = .online
    public var parameters: [String: DeviceParameterValue] = [:]
    
    public init(name: String = "ACES Color Engine", deviceId: String = "aces-global") {
        self.id = UUID()
        self.deviceId = deviceId
        self.name = name
        
        // Default ACES Pipeline State
        self.parameters = [
            // Output Device Transform (ODT)
            "odt": .string("Rec.709"), // Rec.709, P3-D65, Rec.2020-PQ
            
            // Global Grading (Applied after compositing, before ODT)
            "exposure": .float(0.0),
            "contrast": .float(1.0),
            "saturation": .float(1.0),
            "temperature": .float(6500.0),
            "tint": .float(0.0),
            
            // Look Management
            "look_lut": .string("none"), // Path to .cube or preset name
            "film_grain": .bool(false)
        ]
    }
    
    public mutating func set(parameter: String, value: DeviceParameterValue) {
        // Validate ODTs
        if parameter == "odt", case .string(let odt) = value {
            let validODTs = ["Rec.709", "P3-D65", "Rec.2020-PQ", "sRGB"]
            if !validODTs.contains(odt) {
                print("⚠️ Invalid ODT: \(odt). Keeping current.")
                return
            }
        }
        
        parameters[parameter] = value
    }
    
    public func execute(action: String) async throws {
        switch action {
        case "reset":
            // Reset to neutral
            // Note: Since struct is value type, this won't mutate 'self' in place unless handled by a manager.
            // In the DeviceManager context, we'd reset the parameters.
            print("ACES Pipeline Reset to Neutral")
            
        case "apply_look":
            // Logic to load a complex look preset
            print("Applying Cinematic Look...")
            
        default:
            print("Unknown action \(action) for ACES Device")
        }
    }
}
