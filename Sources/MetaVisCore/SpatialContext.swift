import Foundation

/// Represents a geographic location for physical sun positioning.
public struct LocationData: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let name: String?
    
    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }
    
    public static let sanFrancisco = LocationData(latitude: 37.7749, longitude: -122.4194, name: "San Francisco")
    public static let london = LocationData(latitude: 51.5074, longitude: -0.1278, name: "London")
    public static let tokyo = LocationData(latitude: 35.6762, longitude: 139.6503, name: "Tokyo")
}

/// Defines the environmental characteristics (HDRI, Acoustics).
public struct EnvironmentProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let hdriMap: String? // Asset Path
    public let reverbImpulse: String? // Asset Path
    
    public init(id: UUID = UUID(), name: String, hdriMap: String? = nil, reverbImpulse: String? = nil) {
        self.id = id
        self.name = name
        self.hdriMap = hdriMap
        self.reverbImpulse = reverbImpulse
    }
    
    public static let studio = EnvironmentProfile(name: "Studio Clean")
    public static let outdoorSunny = EnvironmentProfile(name: "Outdoor Sunny")
}

/// The entire spatial state of the Virtual Set.
/// This context is passed to AI agents to resolve relative instructions ("Make it 5pm").
public struct SpatialContext: Codable, Sendable, Equatable {
    public var activeCameraId: UUID?
    public var environment: EnvironmentProfile
    public var location: LocationData
    public var timeOfDay: Date
    
    public init(
        activeCameraId: UUID? = nil,
        environment: EnvironmentProfile = .studio,
        location: LocationData = .sanFrancisco,
        timeOfDay: Date = Date()
    ) {
        self.activeCameraId = activeCameraId
        self.environment = environment
        self.location = location
        self.timeOfDay = timeOfDay
    }
}
