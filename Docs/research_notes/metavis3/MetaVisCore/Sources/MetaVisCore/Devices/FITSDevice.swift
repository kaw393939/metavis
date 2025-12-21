import Foundation
import MetaVisCore

/// A specialized device for handling FITS (Flexible Image Transport System) data.
/// This device manages the ingestion, validation, and metadata extraction of scientific assets.
public struct FITSDevice: VirtualDevice, Codable, Sendable {
    public let id: UUID
    public let deviceId: String
    public var name: String
    public var type: DeviceType = .sensor // FITS data comes from sensors (JWST/Hubble)
    public var state: DeviceState = .online
    public var parameters: [String: DeviceParameterValue] = [:]
    
    public init(name: String = "JWST FITS Ingest", deviceId: String = "fits-ingest-01") {
        self.id = UUID()
        self.deviceId = deviceId
        self.name = name
        
        // Default Configuration
        self.parameters = [
            "searchPath": .string("./assets"),
            "recursive": .bool(true),
            "validateHeaders": .bool(true),
            "allowedExtensions": .string("fits,fit,fts")
        ]
    }
    
    public mutating func set(parameter: String, value: DeviceParameterValue) {
        parameters[parameter] = value
    }
    
    public func execute(action: String) async throws {
        // In the future, this could trigger async background scanning
        print("FITSDevice executing action: \(action)")
    }
}
