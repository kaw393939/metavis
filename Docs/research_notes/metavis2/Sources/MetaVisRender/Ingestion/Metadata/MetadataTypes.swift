// Sources/MetaVisRender/Ingestion/Metadata/MetadataTypes.swift
// Sprint 03_cleanup: Metadata type definitions for EXIF/XMP extraction

import Foundation

// MARK: - Camera Settings

/// Stores technical camera configuration at time of capture
public struct CameraSettings: Codable, Sendable, Equatable {
    /// ISO sensitivity (e.g., 100, 200, 400, 800)
    public let iso: Int?
    
    /// Shutter speed in seconds (e.g., 0.001 = 1/1000s)
    public let shutterSpeed: Double?
    
    /// Aperture f-stop (e.g., 1.8, 2.8, 5.6)
    public let aperture: Double?
    
    /// Focal length in millimeters
    public let focalLength: Double?
    
    /// White balance mode ("Auto", "Daylight", "Cloudy", "Tungsten", etc.)
    public let whiteBalance: String?
    
    /// Exposure compensation in EV (+/- stops)
    public let exposureCompensation: Double?
    
    /// Metering mode (0=unknown, 1=average, 2=center-weighted, 3=spot, 5=multi-segment)
    public let meteringMode: Int?
    
    /// Flash mode (0=no flash, 1=flash fired)
    public let flash: Int?
    
    public init(
        iso: Int? = nil,
        shutterSpeed: Double? = nil,
        aperture: Double? = nil,
        focalLength: Double? = nil,
        whiteBalance: String? = nil,
        exposureCompensation: Double? = nil,
        meteringMode: Int? = nil,
        flash: Int? = nil
    ) {
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.focalLength = focalLength
        self.whiteBalance = whiteBalance
        self.exposureCompensation = exposureCompensation
        self.meteringMode = meteringMode
        self.flash = flash
    }
    
    /// Empty camera settings (all nil)
    public static let empty = CameraSettings()
    
    /// Whether any settings are present
    public var hasData: Bool {
        iso != nil || shutterSpeed != nil || aperture != nil || focalLength != nil
    }
}

// MARK: - Device Info

/// Stores camera/lens device identification
public struct DeviceInfo: Codable, Sendable, Equatable {
    /// Camera manufacturer (e.g., "Apple", "Canon", "Sony")
    public let cameraMake: String?
    
    /// Camera model (e.g., "iPhone 15 Pro", "EOS R5")
    public let cameraModel: String?
    
    /// Lens manufacturer
    public let lensMake: String?
    
    /// Lens model (e.g., "iPhone 15 Pro back triple camera 6.86mm f/1.78")
    public let lensModel: String?
    
    /// Lens serial number (for tracking specific lenses)
    public let lensSerial: String?
    
    /// Camera serial number (for multi-camera workflows)
    public let cameraSerial: String?
    
    /// Firmware version
    public let firmwareVersion: String?
    
    /// Image stabilization enabled
    public let imageStabilization: Bool?
    
    /// Recording software (e.g., "17.1.1")
    public let software: String?
    
    public init(
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensMake: String? = nil,
        lensModel: String? = nil,
        lensSerial: String? = nil,
        cameraSerial: String? = nil,
        firmwareVersion: String? = nil,
        imageStabilization: Bool? = nil,
        software: String? = nil
    ) {
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensMake = lensMake
        self.lensModel = lensModel
        self.lensSerial = lensSerial
        self.cameraSerial = cameraSerial
        self.firmwareVersion = firmwareVersion
        self.imageStabilization = imageStabilization
        self.software = software
    }
    
    /// Empty device info (all nil)
    public static let empty = DeviceInfo()
    
    /// Whether any device info is present
    public var hasData: Bool {
        cameraMake != nil || cameraModel != nil || lensModel != nil
    }
    
    /// Full camera name combining make and model
    public var fullCameraName: String? {
        guard let make = cameraMake, let model = cameraModel else {
            return cameraModel ?? cameraMake
        }
        // Avoid duplication like "Apple Apple iPhone"
        if model.lowercased().hasPrefix(make.lowercased()) {
            return model
        }
        return "\(make) \(model)"
    }
}

// MARK: - Shooting Conditions

/// Stores temporal and environmental context
public struct ShootingConditions: Codable, Sendable, Equatable {
    /// Exact capture timestamp
    public let capturedAt: Date?
    
    /// Timezone identifier (e.g., "America/New_York")
    public let timezone: String?
    
    /// GPS latitude
    public let gpsLatitude: Double?
    
    /// GPS longitude
    public let gpsLongitude: Double?
    
    /// GPS altitude in meters
    public let gpsAltitude: Double?
    
    /// Image orientation (1=normal, 3=upside down, 6=90° CW, 8=90° CCW)
    public let orientation: Int?
    
    public init(
        capturedAt: Date? = nil,
        timezone: String? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsAltitude: Double? = nil,
        orientation: Int? = nil
    ) {
        self.capturedAt = capturedAt
        self.timezone = timezone
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsAltitude = gpsAltitude
        self.orientation = orientation
    }
    
    /// Empty shooting conditions (all nil)
    public static let empty = ShootingConditions()
    
    /// Whether any conditions are present
    public var hasData: Bool {
        capturedAt != nil || gpsLatitude != nil || orientation != nil
    }
    
    /// GPS coordinates as tuple if both lat/lon present
    public var gpsCoordinates: (latitude: Double, longitude: Double)? {
        guard let lat = gpsLatitude, let lon = gpsLongitude else { return nil }
        return (lat, lon)
    }
    
    /// Whether image is portrait orientation
    public var isPortrait: Bool {
        guard let o = orientation else { return false }
        return o == 6 || o == 8  // 90° CW or 90° CCW
    }
}

// MARK: - Curation Metadata

/// Stores user-applied metadata for search and organization
public struct CurationMetadata: Codable, Sendable, Equatable {
    /// User-applied tags/keywords
    public let keywords: [String]?
    
    /// Description/caption
    public let description: String?
    
    /// Star rating (0-5)
    public let rating: Int?
    
    /// Copyright notice
    public let copyright: String?
    
    /// Creator/photographer name
    public let creator: String?
    
    /// Usage rights/terms
    public let usageTerms: String?
    
    public init(
        keywords: [String]? = nil,
        description: String? = nil,
        rating: Int? = nil,
        copyright: String? = nil,
        creator: String? = nil,
        usageTerms: String? = nil
    ) {
        self.keywords = keywords
        self.description = description
        self.rating = rating
        self.copyright = copyright
        self.creator = creator
        self.usageTerms = usageTerms
    }
    
    /// Empty curation metadata (all nil)
    public static let empty = CurationMetadata()
    
    /// Whether any curation data is present
    public var hasData: Bool {
        (keywords?.isEmpty == false) || rating != nil || description != nil
    }
}

// MARK: - Metadata Error

/// Errors during metadata extraction
public enum MetadataError: Error, LocalizedError {
    case cannotOpenFile
    case invalidEXIF
    case invalidXMP
    case unsupportedFormat
    case parsingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .cannotOpenFile:
            return "Cannot open media file for metadata extraction"
        case .invalidEXIF:
            return "EXIF data is malformed or unreadable"
        case .invalidXMP:
            return "XMP data is malformed or unreadable"
        case .unsupportedFormat:
            return "This file format does not support metadata extraction"
        case .parsingFailed(let detail):
            return "Metadata parsing failed: \(detail)"
        }
    }
}

// MARK: - Combined Extracted Metadata

/// Combined result from all metadata parsers
public struct ExtractedMetadata: Codable, Sendable, Equatable {
    public let cameraSettings: CameraSettings?
    public let deviceInfo: DeviceInfo?
    public let shootingConditions: ShootingConditions?
    public let curation: CurationMetadata?
    
    public init(
        cameraSettings: CameraSettings? = nil,
        deviceInfo: DeviceInfo? = nil,
        shootingConditions: ShootingConditions? = nil,
        curation: CurationMetadata? = nil
    ) {
        self.cameraSettings = cameraSettings
        self.deviceInfo = deviceInfo
        self.shootingConditions = shootingConditions
        self.curation = curation
    }
    
    /// Empty metadata (all nil)
    public static let empty = ExtractedMetadata()
    
    /// Whether any metadata was extracted
    public var hasData: Bool {
        (cameraSettings?.hasData ?? false) ||
        (deviceInfo?.hasData ?? false) ||
        (shootingConditions?.hasData ?? false) ||
        (curation?.hasData ?? false)
    }
}
