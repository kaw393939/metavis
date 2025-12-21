import Foundation

/// A concrete implementation of VirtualDevice representing a physical or virtual camera.
public struct CameraDevice: VirtualDevice, Codable, Sendable {
    public let id: UUID
    public let deviceId: String // System ID (e.g., "built-in-webcam", "iphone-uuid")
    public var name: String
    public var type: DeviceType = .camera
    public var state: DeviceState = .offline
    public var parameters: [String: DeviceParameterValue] = [:]
    
    public init(name: String, deviceId: String) {
        self.id = UUID()
        self.deviceId = deviceId
        self.name = name
        
        // Set default camera parameters
        self.parameters = [
            "iso": .int(400),
            "shutter_angle": .float(180.0),
            "white_balance": .int(5600),
            "lens": .string("24mm"),
            "aperture": .float(2.8)
        ]
    }
    
    public mutating func set(parameter: String, value: DeviceParameterValue) {
        // In a real implementation, this would validate the value against device capabilities
        parameters[parameter] = value
    }
    
    public func execute(action: String) async throws {
        switch action {
        case "start_recording":
            // Logic to start recording
            // In a real system, this would call the MCP client or AVFoundation
            Log.device.info("Camera \(name) started recording")
        case "stop_recording":
            Log.device.info("Camera \(name) stopped recording")
        default:
            Log.device.warning("Unknown action \(action) for camera \(name)")
        }
    }
}

// Helper for logging (assuming a Log system exists, or we define a simple one)
// Since I don't have the full Log system context, I'll add a simple placeholder if needed,
// but based on the audit, there was a `Log.graph` usage, so `Log` likely exists.
// I'll check if `Log` is available. If not, I'll remove the logging for now to pass compilation.
