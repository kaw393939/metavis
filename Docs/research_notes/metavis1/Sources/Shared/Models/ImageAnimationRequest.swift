import Foundation

/// Request structure for image animation (MetalKinetic)
/// Follows kinetic_image.md specification
public struct ImageAnimationRequest: Codable, Sendable {
    /// Path to source image file
    public let imagePath: String

    /// Output configuration
    public let output: ImageOutputConfig

    /// Animation parameters
    public let animation: ImageAnimationConfig

    /// Optional quality settings
    public let quality: ImageQualityConfig?

    public init(
        imagePath: String,
        output: ImageOutputConfig,
        animation: ImageAnimationConfig,
        quality: ImageQualityConfig? = nil
    ) {
        self.imagePath = imagePath
        self.output = output
        self.animation = animation
        self.quality = quality
    }
}

/// Output configuration for image animation
public struct ImageOutputConfig: Codable, Sendable {
    /// Output file path
    public let path: String

    /// Video format (mp4, mov, webm)
    public let format: String

    /// Resolution
    public let width: Int
    public let height: Int

    /// Frame rate (30, 60)
    public let fps: Int

    /// Codec (h264, h265, prores)
    public let codec: String?

    /// Bitrate in Mbps
    public let bitrate: Int?

    public init(
        path: String,
        format: String = "mp4",
        width: Int,
        height: Int,
        fps: Int = 30,
        codec: String? = "h264",
        bitrate: Int? = 20
    ) {
        self.path = path
        self.format = format
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.bitrate = bitrate
    }
}

/// Animation configuration following kinetic_image.md spec
public struct ImageAnimationConfig: Codable, Sendable {
    /// Total duration in seconds
    public let duration: Double

    /// Motion pattern
    public let motion: MotionPattern

    /// Easing function
    public let easing: EasingFunction

    /// Optional keyframes for custom animations
    public let keyframes: [TransformKeyframe]?

    public init(
        duration: Double,
        motion: MotionPattern,
        easing: EasingFunction = .easeInOut,
        keyframes: [TransformKeyframe]? = nil
    ) {
        self.duration = duration
        self.motion = motion
        self.easing = easing
        self.keyframes = keyframes
    }
}

/// Motion patterns from kinetic_image.md
public enum MotionPattern: String, Codable, Sendable {
    /// Ken Burns: slow zoom + pan
    case kenBurns

    /// Pure zoom in/out
    case zoom

    /// Horizontal/vertical pan
    case pan

    /// Rotation around center
    case rotate

    /// Parallax layers (for multi-layer composition)
    case parallax

    /// Custom keyframe animation
    case custom
}

/// Easing functions for smooth motion
public enum EasingFunction: String, Codable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case cubicBezier
}

/// Transform keyframe for animation timeline
public struct TransformKeyframe: Codable, Sendable {
    /// Time in seconds
    public let time: Double

    /// Translation (x, y) in pixels
    public let translation: [Double]

    /// Scale (x, y)
    public let scale: [Double]

    /// Rotation in degrees
    public let rotation: Double

    /// Opacity (0-1)
    public let opacity: Double

    /// Anchor point (0-1 normalized, default 0.5 = center)
    public let anchor: [Double]?

    public init(
        time: Double,
        translation: [Double] = [0, 0],
        scale: [Double] = [1, 1],
        rotation: Double = 0,
        opacity: Double = 1.0,
        anchor: [Double]? = nil
    ) {
        self.time = time
        self.translation = translation
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.anchor = anchor
    }
}

/// Quality settings for high-end rendering
public struct ImageQualityConfig: Codable, Sendable {
    /// Enable motion blur (multi-sample accumulation)
    public let motionBlur: Bool

    /// Motion blur samples (4-16)
    public let motionBlurSamples: Int

    /// Use Lanczos3 filtering (high-quality resampling)
    public let useLanczos3: Bool

    /// Anti-aliasing samples (1, 2, 4, 8)
    public let antiAliasing: Int

    public init(
        motionBlur: Bool = false,
        motionBlurSamples: Int = 8,
        useLanczos3: Bool = false,
        antiAliasing: Int = 1
    ) {
        self.motionBlur = motionBlur
        self.motionBlurSamples = motionBlurSamples
        self.useLanczos3 = useLanczos3
        self.antiAliasing = antiAliasing
    }
}

/// Simple Ken Burns effect request (convenience)
public struct KenBurnsRequest: Codable, Sendable {
    /// Path to source image
    public let imagePath: String

    /// Output path
    public let outputPath: String

    /// Duration in seconds
    public let duration: Double

    /// Start scale (1.0 = no zoom)
    public let startScale: Double

    /// End scale
    public let endScale: Double

    /// Start position (x, y) normalized (0-1)
    public let startPosition: [Double]

    /// End position (x, y) normalized (0-1)
    public let endPosition: [Double]

    /// Frame rate
    public let fps: Int

    /// Resolution
    public let width: Int
    public let height: Int

    public init(
        imagePath: String,
        outputPath: String,
        duration: Double = 5.0,
        startScale: Double = 1.0,
        endScale: Double = 1.2,
        startPosition: [Double] = [0.5, 0.5],
        endPosition: [Double] = [0.5, 0.5],
        fps: Int = 30,
        width: Int = 1920,
        height: Int = 1080
    ) {
        self.imagePath = imagePath
        self.outputPath = outputPath
        self.duration = duration
        self.startScale = startScale
        self.endScale = endScale
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.fps = fps
        self.width = width
        self.height = height
    }

    /// Convert to full ImageAnimationRequest
    public func toImageAnimationRequest() -> ImageAnimationRequest {
        let keyframes = [
            TransformKeyframe(
                time: 0,
                translation: [
                    (startPosition[0] - 0.5) * Double(width),
                    (startPosition[1] - 0.5) * Double(height)
                ],
                scale: [startScale, startScale],
                rotation: 0,
                opacity: 1.0
            ),
            TransformKeyframe(
                time: duration,
                translation: [
                    (endPosition[0] - 0.5) * Double(width),
                    (endPosition[1] - 0.5) * Double(height)
                ],
                scale: [endScale, endScale],
                rotation: 0,
                opacity: 1.0
            )
        ]

        return ImageAnimationRequest(
            imagePath: imagePath,
            output: ImageOutputConfig(
                path: outputPath,
                width: width,
                height: height,
                fps: fps
            ),
            animation: ImageAnimationConfig(
                duration: duration,
                motion: .kenBurns,
                easing: .easeInOut,
                keyframes: keyframes
            ),
            quality: nil
        )
    }
}
