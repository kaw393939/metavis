import Foundation
import MetaVisCore

/// Canonical identity spine for downstream safety/QC.
///
/// Written as a single JSON file: `identity.timeline.v1.json`.
public struct IdentityTimelineV1: Sendable, Codable, Equatable {
    public var schema: String
    public var analyzedSeconds: Double
    public var speakers: [IdentitySpeakerV1]
    public var spans: [IdentitySpanV1]
    public var bindings: [IdentityBindingEdgeV1]

    public init(
        schema: String = "identity.timeline.v1",
        analyzedSeconds: Double,
        speakers: [IdentitySpeakerV1],
        spans: [IdentitySpanV1],
        bindings: [IdentityBindingEdgeV1]
    ) {
        self.schema = schema
        self.analyzedSeconds = analyzedSeconds
        self.speakers = speakers
        self.spans = spans
        self.bindings = bindings
    }
}

public struct IdentitySpeakerV1: Sendable, Codable, Equatable {
    public var speakerId: String
    public var speakerLabel: String?

    /// Cluster lifecycle fields.
    public var bornAtSeconds: Double
    public var lastActiveAtSeconds: Double
    public var frozen: Bool
    public var frozenAtSeconds: Double?

    /// 0..1 aggregate confidence across attributed words.
    public var confidenceScore: Double

    /// Deterministic, explainable merge hints.
    public var mergeCandidates: [String]

    /// Best on-screen binding (if any).
    public var bestPersonId: String?
    public var bestTrackId: UUID?
    public var bestPosterior: Double?

    public init(
        speakerId: String,
        speakerLabel: String? = nil,
        bornAtSeconds: Double,
        lastActiveAtSeconds: Double,
        frozen: Bool,
        frozenAtSeconds: Double? = nil,
        confidenceScore: Double,
        mergeCandidates: [String] = [],
        bestPersonId: String? = nil,
        bestTrackId: UUID? = nil,
        bestPosterior: Double? = nil
    ) {
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.bornAtSeconds = bornAtSeconds
        self.lastActiveAtSeconds = lastActiveAtSeconds
        self.frozen = frozen
        self.frozenAtSeconds = frozenAtSeconds
        self.confidenceScore = max(0.0, min(1.0, confidenceScore))
        self.mergeCandidates = mergeCandidates
        self.bestPersonId = bestPersonId
        self.bestTrackId = bestTrackId
        self.bestPosterior = bestPosterior.map { max(0.0, min(1.0, $0)) }
    }
}

public struct IdentitySpanV1: Sendable, Codable, Equatable {
    public var speakerId: String
    public var speakerLabel: String?
    public var startSeconds: Double
    public var endSeconds: Double
    public var wordCount: Int

    public init(
        speakerId: String,
        speakerLabel: String? = nil,
        startSeconds: Double,
        endSeconds: Double,
        wordCount: Int
    ) {
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.startSeconds = startSeconds
        self.endSeconds = max(startSeconds, endSeconds)
        self.wordCount = max(0, wordCount)
    }
}
