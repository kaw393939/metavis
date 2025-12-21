import Foundation

/// A single timed caption cue.
public struct CaptionCue: Codable, Sendable, Equatable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String
    public let speaker: String?

    public init(startSeconds: Double, endSeconds: Double, text: String, speaker: String? = nil) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.speaker = speaker
    }
}
