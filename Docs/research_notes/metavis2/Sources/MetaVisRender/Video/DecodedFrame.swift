import Foundation
import CoreMedia
import CoreVideo
import Metal

// MARK: - DecodedFrame

/// A decoded video frame with timing information and pixel data.
/// 
/// `DecodedFrame` encapsulates the result of video decoding, containing:
/// - The raw pixel buffer (CVPixelBuffer) suitable for GPU conversion
/// - Presentation and decode timing for synchronization
/// - Metadata about keyframes and frame sequence
///
/// ## Example Usage
/// ```swift
/// let decoder = try await VideoDecoder(url: videoURL, device: device)
/// let frame = try await decoder.nextFrame()
/// 
/// print("Frame \(frame.frameNumber) at \(frame.timeSeconds)s")
/// let texture = decoder.texture(from: frame)
/// ```
public struct DecodedFrame: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// The decoded pixel buffer containing frame data.
    /// This is backed by IOSurface for efficient GPU access.
    public let pixelBuffer: CVPixelBuffer
    
    /// The presentation timestamp for this frame.
    /// This is when the frame should be displayed.
    public let presentationTime: CMTime
    
    /// The duration this frame should be displayed.
    public let duration: CMTime
    
    /// The decode timestamp for this frame.
    /// This may differ from presentation time for B-frames.
    public let decodeTime: CMTime
    
    /// Whether this frame is a keyframe (I-frame).
    /// Keyframes can be decoded independently.
    public let isKeyframe: Bool
    
    /// Sequential frame number in the video.
    public let frameNumber: Int
    
    // MARK: - Computed Properties
    
    /// Presentation time in seconds.
    public var timeSeconds: Double {
        presentationTime.seconds
    }
    
    /// Duration in seconds.
    public var durationSeconds: Double {
        duration.seconds
    }
    
    /// Frame dimensions as SIMD2.
    public var size: SIMD2<Int> {
        SIMD2(
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer)
        )
    }
    
    /// Width of the frame in pixels.
    public var width: Int {
        CVPixelBufferGetWidth(pixelBuffer)
    }
    
    /// Height of the frame in pixels.
    public var height: Int {
        CVPixelBufferGetHeight(pixelBuffer)
    }
    
    /// Aspect ratio (width / height).
    public var aspectRatio: Float {
        guard height > 0 else { return 1.0 }
        return Float(width) / Float(height)
    }
    
    /// Pixel format of the frame.
    public var pixelFormat: OSType {
        CVPixelBufferGetPixelFormatType(pixelBuffer)
    }
    
    /// Whether the pixel buffer is IOSurface-backed (efficient for Metal).
    public var isIOSurfaceBacked: Bool {
        CVPixelBufferGetIOSurface(pixelBuffer) != nil
    }
    
    // MARK: - Initialization
    
    /// Creates a new decoded frame.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The decoded pixel data.
    ///   - presentationTime: When this frame should be displayed.
    ///   - duration: How long this frame should be displayed.
    ///   - decodeTime: When this frame was decoded (may differ for B-frames).
    ///   - isKeyframe: Whether this is an independently decodable keyframe.
    ///   - frameNumber: Sequential frame number in the video.
    public init(
        pixelBuffer: CVPixelBuffer,
        presentationTime: CMTime,
        duration: CMTime,
        decodeTime: CMTime,
        isKeyframe: Bool,
        frameNumber: Int
    ) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
        self.duration = duration
        self.decodeTime = decodeTime
        self.isKeyframe = isKeyframe
        self.frameNumber = frameNumber
    }
}

// MARK: - CustomStringConvertible

extension DecodedFrame: CustomStringConvertible {
    public var description: String {
        "DecodedFrame(frame: \(frameNumber), time: \(String(format: "%.3f", timeSeconds))s, size: \(width)x\(height), keyframe: \(isKeyframe))"
    }
}

// MARK: - CMTime Extensions

extension CMTime {
    /// Creates a CMTime from seconds with standard video timescale.
    public static func seconds(_ value: Double, preferredTimescale: CMTimeScale = 600) -> CMTime {
        CMTimeMakeWithSeconds(value, preferredTimescale: preferredTimescale)
    }
}

// MARK: - PixelFormat Description

extension DecodedFrame {
    /// Human-readable description of the pixel format.
    public var pixelFormatDescription: String {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            return "BGRA (32-bit)"
        case kCVPixelFormatType_32RGBA:
            return "RGBA (32-bit)"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return "YUV 420 Bi-Planar (Video Range)"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return "YUV 420 Bi-Planar (Full Range)"
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            return "YUV 420 10-bit Bi-Planar (Video Range)"
        case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return "YUV 420 10-bit Bi-Planar (Full Range)"
        default:
            return "Unknown (\(pixelFormat))"
        }
    }
}

// MARK: - VideoMetadata

/// Metadata about a video source.
public struct VideoMetadata: Sendable {
    /// Video resolution in pixels.
    public let resolution: SIMD2<Int>
    
    /// Frame rate in frames per second.
    public let frameRate: Double
    
    /// Total duration of the video.
    public let duration: CMTime
    
    /// Video codec identifier (e.g., "avc1", "hvc1").
    public let codec: String
    
    /// Whether the video has an alpha channel.
    public let hasAlpha: Bool
    
    /// Color space of the video.
    public let colorSpace: CGColorSpace?
    
    /// Whether HDR content is detected.
    public let isHDR: Bool
    
    /// Estimated data rate in bits per second.
    public let estimatedDataRate: Float?
    
    /// Total number of frames in the video.
    public var totalFrames: Int {
        Int(ceil(duration.seconds * frameRate))
    }
    
    /// Duration in seconds.
    public var durationSeconds: Double {
        duration.seconds
    }
    
    public init(
        resolution: SIMD2<Int>,
        frameRate: Double,
        duration: CMTime,
        codec: String,
        hasAlpha: Bool = false,
        colorSpace: CGColorSpace? = nil,
        isHDR: Bool = false,
        estimatedDataRate: Float? = nil
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.duration = duration
        self.codec = codec
        self.hasAlpha = hasAlpha
        self.colorSpace = colorSpace
        self.isHDR = isHDR
        self.estimatedDataRate = estimatedDataRate
    }
}

extension VideoMetadata: CustomStringConvertible {
    public var description: String {
        "VideoMetadata(\(resolution.x)x\(resolution.y) @ \(String(format: "%.2f", frameRate))fps, \(String(format: "%.2f", durationSeconds))s, codec: \(codec), HDR: \(isHDR))"
    }
}
