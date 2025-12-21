import Foundation

/// Represents the type of audio track for routing to the correct bus
public enum AudioTrackType: String, Codable, Sendable {
    case voice // Narration (Master timing)
    case music // Background score (Auto-ducking)
    case sfx // Sound effects (Polyphonic, anchored)
}

/// Represents a single audio clip on the timeline
public struct AudioTrack: Identifiable, Codable, Sendable {
    public let id: String
    public let url: URL
    public let type: AudioTrackType
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let offset: TimeInterval // Start time within the source file
    public let volume: Float

    public init(id: String, url: URL, type: AudioTrackType, startTime: TimeInterval, duration: TimeInterval, offset: TimeInterval = 0.0, volume: Float = 1.0) {
        self.id = id
        self.url = url
        self.type = type
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
        self.volume = volume
    }
}
