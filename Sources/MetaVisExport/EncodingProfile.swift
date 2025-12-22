import Foundation
import AVFoundation

/// Encoding settings that control bitrate/GOP/audio independent of `QualityProfile`.
///
/// - Note: This is intentionally small and focused. Callers that don't care about
///   bitrate/codec knobs can omit it and rely on `VideoExporter` defaults.
public struct EncodingProfile: Codable, Sendable, Equatable {
    public var videoAverageBitRate: Int
    public var maxKeyFrameInterval: Int

    public var audioBitRate: Int
    public var audioSampleRate: Int
    public var audioChannelCount: Int

    public init(
        videoAverageBitRate: Int,
        maxKeyFrameInterval: Int,
        audioBitRate: Int = 128_000,
        audioSampleRate: Int = 48_000,
        audioChannelCount: Int = 2
    ) {
        self.videoAverageBitRate = videoAverageBitRate
        self.maxKeyFrameInterval = maxKeyFrameInterval
        self.audioBitRate = audioBitRate
        self.audioSampleRate = audioSampleRate
        self.audioChannelCount = audioChannelCount
    }
}

public extension EncodingProfile {
    /// Low-bitrate proxy defaults suitable for “inline upload” limits.
    static func proxy(frameRate: Int, maxVideoBitRate: Int = 900_000, audioBitRate: Int = 96_000) -> EncodingProfile {
        EncodingProfile(
            videoAverageBitRate: max(50_000, maxVideoBitRate),
            maxKeyFrameInterval: max(1, frameRate),
            audioBitRate: max(24_000, audioBitRate),
            audioSampleRate: 48_000,
            audioChannelCount: 2
        )
    }
}
