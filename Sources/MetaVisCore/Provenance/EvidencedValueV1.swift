import Foundation

/// Typed perception attribute wrapper (v1).
///
/// This is used at the LLM boundary (and other perception outputs) to ensure every value
/// carries governed confidence, epistemic type, and provenance.
public struct EvidencedValueV1<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public var value: T
    public var confidence: ConfidenceRecordV1
    public var confidenceLevel: ConfidenceLevelV1
    public var provenance: [ProvenanceRefV1]

    public init(
        value: T,
        confidence: ConfidenceRecordV1,
        confidenceLevel: ConfidenceLevelV1,
        provenance: [ProvenanceRefV1] = []
    ) {
        self.value = value
        self.confidence = confidence
        self.confidenceLevel = confidenceLevel
        self.provenance = provenance
    }
}
