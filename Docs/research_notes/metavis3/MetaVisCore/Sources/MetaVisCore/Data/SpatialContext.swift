import Foundation

/// Represents the physical and semantic location of a media asset or timeline event.
/// This unifies raw GPS data with semantic place understanding.
public struct SpatialContext: Codable, Sendable, Equatable {
    /// The raw GPS coordinates.
    public let coordinate: GeoCoordinate?
    
    /// Altitude in meters.
    public let altitude: Double?
    
    /// Compass heading in degrees (0-360).
    public let heading: Double?
    
    /// Semantic place information (e.g. "Eiffel Tower", "Home").
    public let place: PlaceInfo?
    
    /// The type of scene environment.
    public let sceneType: SceneEnvironment?
    
    /// Environmental conditions (weather, lighting).
    public let environment: EnvironmentalConditions?
    
    public init(
        coordinate: GeoCoordinate? = nil,
        altitude: Double? = nil,
        heading: Double? = nil,
        place: PlaceInfo? = nil,
        sceneType: SceneEnvironment? = nil,
        environment: EnvironmentalConditions? = nil
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.heading = heading
        self.place = place
        self.sceneType = sceneType
        self.environment = environment
    }
}

/// A geographic coordinate (Latitude/Longitude).
public struct GeoCoordinate: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Semantic information about a location.
public struct PlaceInfo: Codable, Sendable, Equatable {
    public let name: String?      // e.g. "Apple Park"
    public let address: String?   // e.g. "1 Apple Park Way"
    public let city: String?      // e.g. "Cupertino"
    public let region: String?    // e.g. "CA"
    public let country: String?   // e.g. "USA"
    public let isoCountryCode: String? // e.g. "US"
    public let interestPoints: [String] // e.g. ["Landmark", "Park"]
    
    public init(
        name: String? = nil,
        address: String? = nil,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil,
        isoCountryCode: String? = nil,
        interestPoints: [String] = []
    ) {
        self.name = name
        self.address = address
        self.city = city
        self.region = region
        self.country = country
        self.isoCountryCode = isoCountryCode
        self.interestPoints = interestPoints
    }
}

/// High-level classification of the environment.
public enum SceneEnvironment: String, Codable, Sendable {
    case indoor
    case outdoor
    case urban
    case nature
    case underwater
    case space
    case unknown
}

/// Environmental conditions at the location.
public struct EnvironmentalConditions: Codable, Sendable, Equatable {
    public let weather: String? // e.g. "Sunny", "Rainy"
    public let temperature: Double? // Celsius
    public let lighting: String? // e.g. "Daylight", "Artificial", "Low Light"
    
    public init(weather: String? = nil, temperature: Double? = nil, lighting: String? = nil) {
        self.weather = weather
        self.temperature = temperature
        self.lighting = lighting
    }
}
