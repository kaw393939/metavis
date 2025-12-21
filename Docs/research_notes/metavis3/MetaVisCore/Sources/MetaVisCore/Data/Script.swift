import Foundation

/// Represents a script or transcript of dialogue in the session.
/// This bridges the gap between raw audio ingestion (Speech-to-Text) and the Cast (Actors).
public struct Script: Codable, Sendable, Identifiable {
    public let id: UUID
    public var lines: [DialogueLine]
    public var language: String
    public var source: ScriptSource
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        lines: [DialogueLine] = [],
        language: String = "en",
        source: ScriptSource = .manual,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.lines = lines
        self.language = language
        self.source = source
        self.createdAt = createdAt
    }
}

public enum ScriptSource: String, Codable, Sendable {
    case manual
    case imported
    case speechToText
}

/// A single line of dialogue or a segment of speech.
public struct DialogueLine: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// The spoken text.
    public var text: String
    
    /// The start time of the line in the timeline.
    public var startTime: RationalTime
    
    /// The duration of the line.
    public var duration: RationalTime
    
    /// The ID of the CastMember speaking this line.
    /// If nil, the speaker is unidentified (e.g. "Speaker 1" from raw diarization not yet linked).
    public var speakerId: UUID?
    
    /// The raw speaker label from ingestion (e.g. "SPEAKER_01") if not yet linked to a CastMember.
    public var rawSpeakerLabel: String?
    
    /// Confidence score of the transcription (0.0 - 1.0).
    public var confidence: Float
    
    /// Word-level timing if available.
    public var words: [ScriptWord]
    
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: RationalTime,
        duration: RationalTime,
        speakerId: UUID? = nil,
        rawSpeakerLabel: String? = nil,
        confidence: Float = 1.0,
        words: [ScriptWord] = []
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.speakerId = speakerId
        self.rawSpeakerLabel = rawSpeakerLabel
        self.confidence = confidence
        self.words = words
    }
    
    public var endTime: RationalTime {
        return startTime + duration
    }
}

/// Word-level timing information.
public struct ScriptWord: Codable, Sendable {
    public let text: String
    public let startTime: RationalTime
    public let duration: RationalTime
    public let confidence: Float
    
    public init(
        text: String,
        startTime: RationalTime,
        duration: RationalTime,
        confidence: Float
    ) {
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.confidence = confidence
    }
}
