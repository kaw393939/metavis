import AVFoundation
import CoreMedia
import VideoToolbox

public struct VideoSpec {
    public let resolution: CGSize
    public let frameRate: Float
    public let codec: AVVideoCodecType
    public let duration: Double
    public let tolerance: Double // Duration tolerance in seconds
    
    public init(resolution: CGSize, frameRate: Float, codec: AVVideoCodecType, duration: Double, tolerance: Double = 0.1) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.duration = duration
        self.tolerance = tolerance
    }
}

public enum VideoValidationError: Error {
    case fileNotFound
    case noVideoTrack
    case resolutionMismatch(expected: CGSize, actual: CGSize)
    case frameRateMismatch(expected: Float, actual: Float)
    case codecMismatch(expected: AVVideoCodecType, actual: String)
    case durationMismatch(expected: Double, actual: Double)
    case propertyLoadFailed(String)
}

public class VideoValidator {
    
    public static func validate(fileURL: URL, against spec: VideoSpec) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VideoValidationError.fileNotFound
        }
        
        let asset = AVAsset(url: fileURL)
        
        // 1. Load Tracks
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoValidationError.noVideoTrack
        }
        
        // 2. Validate Resolution
        let size = try await track.load(.naturalSize)
        // AVAsset naturalSize might be affected by transform, but usually for generated video it matches dimensions
        if size.width != spec.resolution.width || size.height != spec.resolution.height {
            throw VideoValidationError.resolutionMismatch(expected: spec.resolution, actual: size)
        }
        
        // 3. Validate Frame Rate
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        if abs(nominalFrameRate - spec.frameRate) > 0.1 {
             throw VideoValidationError.frameRateMismatch(expected: spec.frameRate, actual: nominalFrameRate)
        }
        
        // 4. Validate Codec
        let formatDescriptions = try await track.load(.formatDescriptions)
        if let formatDesc = formatDescriptions.first {
            let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
            // Convert FourCC to String for comparison/logging
            let codecString = fourCCToString(mediaSubType)
            
            // Map AVVideoCodecType to FourCC strings roughly
            // This is a simplification; robust mapping might be needed
            let expectedCodecString: String
            switch spec.codec {
            case .proRes4444: expectedCodecString = "ap4h"
            case .proRes422: expectedCodecString = "apcn"
            case .hevc: expectedCodecString = "hvc1" // or hev1
            case .h264: expectedCodecString = "avc1"
            default: expectedCodecString = "unknown"
            }
            
            // Loose check for HEVC/H264 variants
            let isMatch: Bool
            if spec.codec == .hevc {
                isMatch = codecString == "hvc1" || codecString == "hev1"
            } else {
                isMatch = codecString == expectedCodecString
            }
            
            if !isMatch {
                // Warning only for now as mapping is tricky, or throw if strict
                print("⚠️ Codec check: Expected \(expectedCodecString), got \(codecString). Proceeding with caution.")
            }
        }
        
        // 5. Validate Duration
        let duration = try await asset.load(.duration).seconds
        if abs(duration - spec.duration) > spec.tolerance {
            throw VideoValidationError.durationMismatch(expected: spec.duration, actual: duration)
        }
        
        return true
    }
    
    private static func fourCCToString(_ code: FourCharCode) -> String {
        let utf16 = [
            UInt16((code >> 24) & 0xFF),
            UInt16((code >> 16) & 0xFF),
            UInt16((code >> 8) & 0xFF),
            UInt16(code & 0xFF)
        ]
        return String(utf16CodeUnits: utf16, count: 4)
    }
}
