import Foundation

/// JSONL record schema emitted by MetaVisLab speaker diarization (Sprint 24).
///
/// This record is written one-per-line to `transcript.attribution.v1.jsonl`.
/// It is keyed by `wordId` so that the main transcript schema (`TranscriptWordV1`)
/// can remain stable while we add governed uncertainty surfaces.
public struct TranscriptAttributionV1: Codable, Sendable, Equatable {
    public var schema: String

    /// Foreign key into `transcript.words.v1.jsonl`.
    public var wordId: String

    /// Assigned speaker identity. `nil` means unassigned / outside gating.
    public var speakerId: String?

    /// Friendly label (`T1`, `T2`, …) or `OFFSCREEN`.
    public var speakerLabel: String?

    /// Governed confidence for the speaker attribution decision.
    public var attributionConfidence: ConfidenceRecordV1

    public init(
        schema: String = "transcript.attribution.v1",
        wordId: String,
        speakerId: String?,
        speakerLabel: String?,
        attributionConfidence: ConfidenceRecordV1
    ) {
        self.schema = schema
        self.wordId = wordId
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.attributionConfidence = attributionConfidence
    }
}
