import Foundation

/// Represents a physical camera model for cinematographic rendering.
public struct VirtualCamera: Sendable, Codable {
    
    // MARK: - Sensor (Film Back)
    
    public enum SensorFormat: String, Codable, Sendable {
        case imax70mm      // 70.41mm x 52.63mm
        case fullFrame35mm // 36mm x 24mm
        case super35       // 24.89mm x 18.66mm
        case apsc          // 23.6mm x 15.6mm
        case microFourThirds // 17.3mm x 13mm
        
        public var dimensions: CGSize {
            switch self {
            case .imax70mm: return CGSize(width: 70.41, height: 52.63)
            case .fullFrame35mm: return CGSize(width: 36.0, height: 24.0)
            case .super35: return CGSize(width: 24.89, height: 18.66)
            case .apsc: return CGSize(width: 23.6, height: 15.6)
            case .microFourThirds: return CGSize(width: 17.3, height: 13.0)
            }
        }
    }
    
    public let sensor: SensorFormat
    
    // MARK: - Lens (Optics)
    
    /// Focal length in millimeters
    public var focalLength: Double
    
    /// Aperture f-stop (e.g., 1.4, 2.8, 5.6)
    public var fStop: Double
    
    /// Focus distance in meters
    public var focusDistance: Double
    
    // MARK: - Mechanics
    
    /// Shutter angle in degrees (standard is 180.0)
    public var shutterAngle: Double
    
    /// ISO sensitivity (Gain)
    public var iso: Double
    
    // MARK: - Initialization
    
    public init(
        sensor: SensorFormat = .super35,
        focalLength: Double = 35.0,
        fStop: Double = 2.8,
        focusDistance: Double = 2.0,
        shutterAngle: Double = 180.0,
        iso: Double = 800.0
    ) {
        self.sensor = sensor
        self.focalLength = focalLength
        self.fStop = fStop
        self.focusDistance = focusDistance
        self.shutterAngle = shutterAngle
        self.iso = iso
    }
    
    // MARK: - Computed Physics
    
    /// Horizontal Field of View in degrees
    public var horizontalFOV: Double {
        let sensorWidth = sensor.dimensions.width
        // FOV = 2 * atan(sensorWidth / (2 * focalLength))
        let radians = 2 * atan(sensorWidth / (2 * focalLength))
        return radians * 180 / .pi
    }
    
    /// Vertical Field of View in degrees
    public var verticalFOV: Double {
        let sensorHeight = sensor.dimensions.height
        let radians = 2 * atan(sensorHeight / (2 * focalLength))
        return radians * 180 / .pi
    }
}
