import Foundation
import MetaVisCore

public struct IdentityBindingGraphV1: Sendable, Codable, Equatable {
    public var schema: String
    public var analyzedSeconds: Double
    public var bindings: [IdentityBindingEdgeV1]

    public init(
        schema: String = "identity.bindings.v1",
        analyzedSeconds: Double,
        bindings: [IdentityBindingEdgeV1]
    ) {
        self.schema = schema
        self.analyzedSeconds = analyzedSeconds
        self.bindings = bindings
    }
}

public struct IdentityBindingEdgeV1: Sendable, Codable, Equatable {
    public var speakerId: String
    public var speakerLabel: String?

    public var trackId: UUID
    public var personId: String?

    /// Posterior probability from co-occurrence statistics.
    public var posterior: Double

    public var confidence: ConfidenceRecordV1
    public var confidenceLevel: ConfidenceLevelV1
    public var provenance: [ProvenanceRefV1]

    public init(
        speakerId: String,
        speakerLabel: String? = nil,
        trackId: UUID,
        personId: String? = nil,
        posterior: Double,
        confidence: ConfidenceRecordV1,
        confidenceLevel: ConfidenceLevelV1,
        provenance: [ProvenanceRefV1] = []
    ) {
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.trackId = trackId
        self.personId = personId
        self.posterior = max(0.0, min(1.0, posterior))
        self.confidence = confidence
        self.confidenceLevel = confidenceLevel
        self.provenance = provenance
    }
}
