import Foundation
import AVFoundation
import CoreMedia

/// Represents a media asset (video, image, audio) in the project.
/// Acts as the central repository for all metadata extracted from the source file.
public struct Asset: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    
    /// The status of the asset (e.g., local, generating, ready).
    public var status: AssetStatus
    
    /// The location of the source file. Optional if generating.
    public var url: URL?
    
    /// Multi-Representation Support
    /// Stores references to different quality versions of the same asset.
    public var representations: [AssetRepresentation] = []
    
    /// Metadata for generative assets.
    public var generativeMetadata: GenerativeMetadata?
    
    /// The type of media.
    public let type: MediaType
    
    /// Duration of the asset (if applicable).
    public let duration: RationalTime
    
    /// Spatial metadata (Location, Place, Environment).
    public var spatial: SpatialContext?
    
    /// Color profile information (Primaries, Transfer Function).
    public var colorProfile: ColorProfile?
    
    /// Visual analysis results (Segmentation, Objects, Saliency).
    public var visual: VisualAnalysis?
    
    public init(
        id: UUID = UUID(),
        name: String,
        status: AssetStatus = .local,
        url: URL? = nil,
        representations: [AssetRepresentation] = [],
        generativeMetadata: GenerativeMetadata? = nil,
        type: MediaType,
        duration: RationalTime,
        spatial: SpatialContext? = nil,
        colorProfile: ColorProfile? = nil,
        visual: VisualAnalysis? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.url = url
        self.representations = representations
        self.generativeMetadata = generativeMetadata
        self.type = type
        self.duration = duration
        self.spatial = spatial
        self.colorProfile = colorProfile
        self.visual = visual
    }

    // MARK: - Ingestion (Self-Probing)
    
    /// Creates an Asset by probing the file at the given URL.
    /// This replaces the standalone MediaProbe utility.
    public init(from url: URL) async throws {
        let name = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        
        // Determine Type
        let type: MediaType
        switch fileExtension {
        case "fits", "fit":
            type = .fits
        case "jpg", "jpeg", "png", "tiff", "tif", "heic":
            type = .image
        case "mp3", "wav", "m4a", "aac":
            type = .audio
        case "usdz", "obj", "gltf":
            type = .model
        default:
            type = .video // Default to video for mov, mp4, mxf
        }
        
        // Special Handling for FITS (AVFoundation does not support it)
        if type == .fits {
            self.init(
                name: name,
                url: url,
                type: type,
                duration: RationalTime(value: 1, timescale: 24) // Default to 1 frame
            )
            return
        }
        
        // Probe with AVFoundation
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let durationSeconds = try await asset.load(.duration).seconds
        let duration = RationalTime(seconds: durationSeconds)
        
        // Extract Tracks for Resolution and Color Profile
        var resolution = SIMD2<Int>(0, 0)
        var colorProfile: ColorProfile? = nil
        
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            resolution = SIMD2<Int>(Int(size.width), Int(size.height))
            
            // Extract Color Profile
            let formatDescriptions = try await track.load(.formatDescriptions)
            if let formatDesc = formatDescriptions.first {
                colorProfile = Asset.extractColorProfile(from: formatDesc)
            }
        }
        
        // Create Original Representation
        let original = AssetRepresentation(
            type: .original,
            url: url,
            resolution: resolution
        )
        
        self.init(
            name: name,
            status: .local,
            url: url,
            representations: [original],
            type: type,
            duration: duration,
            colorProfile: colorProfile
        )
    }
    
    // MARK: - Private Helpers
    
    private static func extractColorProfile(from formatDesc: CMFormatDescription) -> ColorProfile? {
        var primaries = ColorPrimaries.rec709
        var transfer = TransferFunction.rec709
        
        // Color primaries
        if let primariesExt = CMFormatDescriptionGetExtension(
            formatDesc,
            extensionKey: kCMFormatDescriptionExtension_ColorPrimaries
        ) as? String {
            switch primariesExt {
            case "ITU_R_709_2": primaries = .rec709
            case "ITU_R_2020": primaries = .rec2020
            case "P3_D65", "DCI_P3": primaries = .p3d65
            case "ACEScg": primaries = .acescg
            default: break
            }
        }
        
        // Transfer function
        if let transferExt = CMFormatDescriptionGetExtension(
            formatDesc,
            extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String {
            switch transferExt {
            case "ITU_R_709_2": transfer = .rec709
            case "SMPTE_ST_2084_PQ": transfer = .pq
            case "ITU_R_2100_HLG", "ARIB_STD_B67": transfer = .hlg
            case "sRGB": transfer = .sRGB
            case "Linear": transfer = .linear
            case "AppleLog", "com.apple.log": transfer = .appleLog
            default: break
            }
        }
        
        return ColorProfile(primaries: primaries, transferFunction: transfer)
    }
}

public enum AssetStatus: String, Codable, Sendable {
    case local
    case remote
    case generating
    case failed
    case ready
    case streaming
    case offline
}

public struct GenerativeMetadata: Codable, Sendable {
    public let prompt: String
    public let seed: Int?
    public let providerId: String
    public let jobId: UUID?
    
    public init(prompt: String, seed: Int? = nil, providerId: String, jobId: UUID? = nil) {
        self.prompt = prompt
        self.seed = seed
        self.providerId = providerId
        self.jobId = jobId
    }
}

public enum MediaType: String, Codable, Sendable {
    case video
    case image
    case audio
    case model // 3D Model
    case fits // Scientific Data
    case composite // Multi-channel Scientific Data
}

public struct AssetRepresentation: Codable, Sendable, Identifiable {
    public var id: UUID = UUID()
    public var type: RepresentationType
    public var url: URL
    public var resolution: SIMD2<Int>
    public var bitrate: Int // bps
    public enum RepresentationType: String, Codable, Sendable {
        case original // The master file
        case mezzanine // Intermediate quality (ProRes/DNxHR)
        case proxy // Low-res edit friendly
        case stream // Live URL
        case render // Cached render
    }
    
    public init(type: RepresentationType, url: URL, resolution: SIMD2<Int>, bitrate: Int = 0) {
        self.type = type
        self.url = url
        self.resolution = resolution
        self.bitrate = bitrate
    }
}
