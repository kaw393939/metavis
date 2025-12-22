import Foundation
import MetaVisCore

public struct TemporalContextV1: Sendable, Codable, Equatable {
    public var schema: String
    public var analyzedSeconds: Double
    public var events: [TemporalEventV1]

    public init(
        schema: String = "temporal.context.v1",
        analyzedSeconds: Double,
        events: [TemporalEventV1]
    ) {
        self.schema = schema
        self.analyzedSeconds = analyzedSeconds
        self.events = events
    }
}

public struct TemporalEventV1: Sendable, Codable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case faceTrackStable
        case speakerChange
        case lightingShift
    }

    public var kind: Kind
    public var startSeconds: Double
    public var endSeconds: Double

    /// Optional stable IDs for the event payload.
    public var trackId: UUID?
    public var personId: String?
    public var fromSpeakerId: String?
    public var toSpeakerId: String?

    public var confidence: ConfidenceRecordV1
    public var confidenceLevel: ConfidenceLevelV1
    public var provenance: [ProvenanceRefV1]

    public init(
        kind: Kind,
        startSeconds: Double,
        endSeconds: Double,
        trackId: UUID? = nil,
        personId: String? = nil,
        fromSpeakerId: String? = nil,
        toSpeakerId: String? = nil,
        confidence: ConfidenceRecordV1,
        confidenceLevel: ConfidenceLevelV1,
        provenance: [ProvenanceRefV1] = []
    ) {
        self.kind = kind
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.trackId = trackId
        self.personId = personId
        self.fromSpeakerId = fromSpeakerId
        self.toSpeakerId = toSpeakerId
        self.confidence = confidence
        self.confidenceLevel = confidenceLevel
        self.provenance = provenance
    }
}
