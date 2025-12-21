import AVFoundation
import Foundation

public enum MediaProbeError: Error {
    case fileNotFound
    case unreadableFile
    case missingVideoTrack
}

/// Options for media probing
public struct ProbeOptions: OptionSet, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Extract basic video metadata only
    public static let basic = ProbeOptions(rawValue: 1 << 0)
    
    /// Extract EXIF metadata (camera settings, device info)
    public static let exif = ProbeOptions(rawValue: 1 << 1)
    
    /// Extract XMP metadata (keywords, ratings, copyright)
    public static let xmp = ProbeOptions(rawValue: 1 << 2)
    
    /// Extract all available metadata
    public static let full: ProbeOptions = [.basic, .exif, .xmp]
    
    /// Default options (full extraction)
    public static let `default`: ProbeOptions = .full
}

public class MediaProbe {
    
    /// Probe media file with default options (full metadata extraction)
    public static func probe(url: URL) async throws -> MediaProfile {
        try await probe(url: url, options: .default)
    }
    
    /// Probe media file with specified options
    public static func probe(url: URL, options: ProbeOptions) async throws -> MediaProfile {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaProbeError.fileNotFound
        }
        
        let asset = AVURLAsset(url: url)
        
        // Load tracks asynchronously
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw MediaProbeError.missingVideoTrack
        }
        
        // Extract metadata
        let size = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        
        // Codec and Color info
        let formatDescriptions = try await track.load(.formatDescriptions)
        var codec = "unknown"
        var colorSpace: String? = nil
        var transferFunction: String? = nil
        
        if let desc = formatDescriptions.first {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
            codec = codeToString(mediaSubType)
            
            // Color Primaries
            if let primaries = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String {
                colorSpace = primaries
            }
            
            // Transfer Function
            if let transfer = CMFormatDescriptionGetExtension(desc, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String {
                transferFunction = transfer
            }
        }
        
        // Extract extended metadata if requested
        var cameraSettings: CameraSettings? = nil
        var deviceInfo: DeviceInfo? = nil
        var shootingConditions: ShootingConditions? = nil
        var curation: CurationMetadata? = nil
        
        if options.contains(.exif) || options.contains(.xmp) {
            // Run EXIF and XMP extraction in parallel
            async let exifTask: EXIFParser.EXIFResult? = options.contains(.exif) 
                ? (try? await EXIFParser().extractEXIF(from: url)) 
                : nil
            async let xmpTask: XMPParser.XMPResult? = options.contains(.xmp)
                ? (try? await XMPParser().extractXMP(from: url))
                : nil
            
            let (exifResult, xmpResult) = await (exifTask, xmpTask)
            
            if let exif = exifResult {
                cameraSettings = exif.cameraSettings.hasData ? exif.cameraSettings : nil
                deviceInfo = exif.deviceInfo.hasData ? exif.deviceInfo : nil
                shootingConditions = exif.shootingConditions.hasData ? exif.shootingConditions : nil
            }
            
            if let xmp = xmpResult, xmp.hasData {
                curation = xmp.toCurationMetadata()
            }
        }
        
        return MediaProfile(
            resolution: SIMD2<Int>(Int(size.width), Int(size.height)),
            fps: Double(frameRate),
            duration: duration,
            codec: codec,
            colorSpace: colorSpace,
            transferFunction: transferFunction,
            cameraSettings: cameraSettings,
            deviceInfo: deviceInfo,
            shootingConditions: shootingConditions,
            curation: curation
        )
    }
    
    private static func codeToString(_ code: FourCharCode) -> String {
        let n = Int(code)
        var s = String(UnicodeScalar((n >> 24) & 255)!)
        s.append(String(UnicodeScalar((n >> 16) & 255)!))
        s.append(String(UnicodeScalar((n >> 8) & 255)!))
        s.append(String(UnicodeScalar(n & 255)!))
        return s.trimmingCharacters(in: .whitespaces)
    }
}
