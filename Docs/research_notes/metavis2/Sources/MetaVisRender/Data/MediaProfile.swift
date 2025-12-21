import Foundation
import simd

public struct MediaProfile: Codable, Sendable {
    // MARK: - Core Properties (Sprint 03)
    
    public let resolution: SIMD2<Int>
    public let fps: Double
    public let duration: Double
    public let codec: String
    public let colorSpace: String?
    public let transferFunction: String?
    
    // MARK: - Extended Metadata (Sprint 03_cleanup)
    
    /// Camera settings (ISO, aperture, shutter speed, etc.)
    public let cameraSettings: CameraSettings?
    
    /// Device information (camera make/model, lens info)
    public let deviceInfo: DeviceInfo?
    
    /// Shooting conditions (capture date, GPS, orientation)
    public let shootingConditions: ShootingConditions?
    
    /// Curation metadata (keywords, rating, copyright)
    public let curation: CurationMetadata?
    
    // MARK: - Initialization
    
    public init(
        resolution: SIMD2<Int>,
        fps: Double,
        duration: Double,
        codec: String,
        colorSpace: String? = nil,
        transferFunction: String? = nil,
        cameraSettings: CameraSettings? = nil,
        deviceInfo: DeviceInfo? = nil,
        shootingConditions: ShootingConditions? = nil,
        curation: CurationMetadata? = nil
    ) {
        self.resolution = resolution
        self.fps = fps
        self.duration = duration
        self.codec = codec
        self.colorSpace = colorSpace
        self.transferFunction = transferFunction
        self.cameraSettings = cameraSettings
        self.deviceInfo = deviceInfo
        self.shootingConditions = shootingConditions
        self.curation = curation
    }
    
    // MARK: - Convenience Accessors
    
    /// Whether any extended metadata was extracted
    public var hasExtendedMetadata: Bool {
        (cameraSettings?.hasData ?? false) ||
        (deviceInfo?.hasData ?? false) ||
        (shootingConditions?.hasData ?? false) ||
        (curation?.hasData ?? false)
    }
    
    /// Quick access to camera name
    public var cameraName: String? {
        deviceInfo?.fullCameraName
    }
    
    /// Quick access to capture date
    public var capturedAt: Date? {
        shootingConditions?.capturedAt
    }
    
    /// Quick access to rating
    public var rating: Int? {
        curation?.rating
    }
    
    /// Quick access to keywords
    public var keywords: [String]? {
        curation?.keywords
    }
}
