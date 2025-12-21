// Sources/MetaVisRender/Ingestion/Metadata/EXIFParser.swift
// Sprint 03_cleanup: EXIF metadata extraction using ImageIO

import Foundation
import ImageIO
import CoreGraphics

/// Actor for extracting EXIF metadata from image and video files
public actor EXIFParser {
    
    /// Result type containing all extracted EXIF data
    public struct EXIFResult: Sendable {
        public let cameraSettings: CameraSettings
        public let deviceInfo: DeviceInfo
        public let shootingConditions: ShootingConditions
        
        public static let empty = EXIFResult(
            cameraSettings: .empty,
            deviceInfo: .empty,
            shootingConditions: .empty
        )
    }
    
    public init() {}
    
    /// Extract EXIF metadata from a media file
    /// - Parameter url: URL to the media file
    /// - Returns: Extracted EXIF data organized into components
    /// - Throws: MetadataError if file cannot be opened
    public func extractEXIF(from url: URL) async throws -> EXIFResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MetadataError.cannotOpenFile
        }
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            // Return empty result for files that can't be parsed (not an error)
            return .empty
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return .empty
        }
        
        // Extract from different dictionaries
        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gpsDict = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        
        let cameraSettings = extractCameraSettings(from: exifDict)
        let deviceInfo = extractDeviceInfo(from: tiffDict, exifDict: exifDict)
        let shootingConditions = extractShootingConditions(from: tiffDict, gpsDict: gpsDict, properties: properties)
        
        return EXIFResult(
            cameraSettings: cameraSettings,
            deviceInfo: deviceInfo,
            shootingConditions: shootingConditions
        )
    }
    
    // MARK: - Private Extraction Methods
    
    private func extractCameraSettings(from exifDict: [String: Any]) -> CameraSettings {
        // ISO - can be array or single value
        var iso: Int? = nil
        if let isoArray = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let first = isoArray.first {
            iso = first
        } else if let isoValue = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? Int {
            iso = isoValue
        }
        
        // Aperture (F-Number)
        let aperture = exifDict[kCGImagePropertyExifFNumber as String] as? Double
        
        // Shutter speed (exposure time in seconds)
        let shutterSpeed = exifDict[kCGImagePropertyExifExposureTime as String] as? Double
        
        // Focal length
        let focalLength = exifDict[kCGImagePropertyExifFocalLength as String] as? Double
        
        // White balance
        var whiteBalance: String? = nil
        if let wb = exifDict[kCGImagePropertyExifWhiteBalance as String] as? Int {
            whiteBalance = wb == 0 ? "Auto" : "Manual"
        }
        
        // Exposure compensation
        let exposureCompensation = exifDict[kCGImagePropertyExifExposureBiasValue as String] as? Double
        
        // Metering mode
        let meteringMode = exifDict[kCGImagePropertyExifMeteringMode as String] as? Int
        
        // Flash
        let flash = exifDict[kCGImagePropertyExifFlash as String] as? Int
        
        return CameraSettings(
            iso: iso,
            shutterSpeed: shutterSpeed,
            aperture: aperture,
            focalLength: focalLength,
            whiteBalance: whiteBalance,
            exposureCompensation: exposureCompensation,
            meteringMode: meteringMode,
            flash: flash
        )
    }
    
    private func extractDeviceInfo(from tiffDict: [String: Any], exifDict: [String: Any]) -> DeviceInfo {
        let cameraMake = tiffDict[kCGImagePropertyTIFFMake as String] as? String
        let cameraModel = tiffDict[kCGImagePropertyTIFFModel as String] as? String
        let software = tiffDict[kCGImagePropertyTIFFSoftware as String] as? String
        
        // Lens info from EXIF Aux dictionary or main EXIF
        let lensModel = exifDict[kCGImagePropertyExifLensModel as String] as? String
        let lensMake = exifDict[kCGImagePropertyExifLensMake as String] as? String
        let lensSerial = exifDict[kCGImagePropertyExifLensSerialNumber as String] as? String
        let cameraSerial = exifDict[kCGImagePropertyExifBodySerialNumber as String] as? String
        
        return DeviceInfo(
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensMake: lensMake,
            lensModel: lensModel,
            lensSerial: lensSerial,
            cameraSerial: cameraSerial,
            software: software
        )
    }
    
    private func extractShootingConditions(
        from tiffDict: [String: Any],
        gpsDict: [String: Any],
        properties: [String: Any]
    ) -> ShootingConditions {
        // Capture date/time
        var capturedAt: Date? = nil
        if let dateString = tiffDict[kCGImagePropertyTIFFDateTime as String] as? String {
            capturedAt = parseDateTimeOriginal(dateString)
        }
        
        // Orientation
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int
        
        // GPS coordinates
        var gpsLatitude: Double? = nil
        var gpsLongitude: Double? = nil
        var gpsAltitude: Double? = nil
        
        if let lat = gpsDict[kCGImagePropertyGPSLatitude as String] as? Double {
            let latRef = gpsDict[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
            gpsLatitude = latRef == "S" ? -lat : lat
        }
        
        if let lon = gpsDict[kCGImagePropertyGPSLongitude as String] as? Double {
            let lonRef = gpsDict[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
            gpsLongitude = lonRef == "W" ? -lon : lon
        }
        
        gpsAltitude = gpsDict[kCGImagePropertyGPSAltitude as String] as? Double
        if let altRef = gpsDict[kCGImagePropertyGPSAltitudeRef as String] as? Int, altRef == 1 {
            gpsAltitude = gpsAltitude.map { -$0 } // Below sea level
        }
        
        return ShootingConditions(
            capturedAt: capturedAt,
            gpsLatitude: gpsLatitude,
            gpsLongitude: gpsLongitude,
            gpsAltitude: gpsAltitude,
            orientation: orientation
        )
    }
    
    /// Parse EXIF date format: "YYYY:MM:DD HH:MM:SS"
    private func parseDateTimeOriginal(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }
}
