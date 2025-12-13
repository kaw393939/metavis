import Foundation

/// Controls whether exported movies should include an audio track.
public enum AudioPolicy: Sendable, Equatable {
    /// Include audio only if the timeline contains audio tracks.
    case auto

    /// Always include an audio track (fails later if no samples are produced).
    case required

    /// Never include an audio track.
    case forbidden
}
