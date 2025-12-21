import Foundation

public typealias PolicyId = String

/// Canonical, shared confidence record (v1).
///
/// Confidence is governed:
/// - `grade` is primary for consumers.
/// - `score` is supporting detail.
/// - `reasons` must be finite, stable, and sorted.
public struct ConfidenceRecordV1: Codable, Sendable, Equatable {
    public var score: Float
    public var grade: ConfidenceGradeV1
    public var sources: [ConfidenceSourceV1]
    public var reasons: [ReasonCodeV1]
    public var evidenceRefs: [EvidenceRefV1]
    public var policyId: PolicyId?

    public init(
        score: Float,
        grade: ConfidenceGradeV1,
        sources: [ConfidenceSourceV1] = [],
        reasons: [ReasonCodeV1] = [],
        evidenceRefs: [EvidenceRefV1] = [],
        policyId: PolicyId? = nil
    ) {
        self.score = max(0.0, min(1.0, score))
        self.grade = grade
        self.sources = sources.sorted()
        self.reasons = reasons.sorted()
        self.evidenceRefs = evidenceRefs
        self.policyId = policyId
    }

    public static func evidence(
        score: Float,
        sources: [ConfidenceSourceV1],
        reasons: [ReasonCodeV1] = [],
        evidenceRefs: [EvidenceRefV1] = []
    ) -> ConfidenceRecordV1 {
        let clamped = max(0.0, min(1.0, score))
        return ConfidenceRecordV1(
            score: clamped,
            grade: ConfidenceMappingV1.grade(for: clamped),
            sources: sources,
            reasons: reasons,
            evidenceRefs: evidenceRefs,
            policyId: nil
        )
    }

    public static func decision(
        score: Float,
        policyId: PolicyId,
        sources: [ConfidenceSourceV1],
        reasons: [ReasonCodeV1] = [],
        evidenceRefs: [EvidenceRefV1] = []
    ) -> ConfidenceRecordV1 {
        let clamped = max(0.0, min(1.0, score))
        return ConfidenceRecordV1(
            score: clamped,
            grade: ConfidenceMappingV1.grade(for: clamped),
            sources: sources,
            reasons: reasons,
            evidenceRefs: evidenceRefs,
            policyId: policyId
        )
    }
}

/// Discrete grades (v1). Primary consumer-facing signal.
public enum ConfidenceGradeV1: String, Codable, Sendable, Equatable, Comparable {
    case VERIFIED // A
    case STRONG   // B
    case AMBIGUOUS // C
    case WEAK     // D
    case INVALID  // F

    public static func < (lhs: ConfidenceGradeV1, rhs: ConfidenceGradeV1) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .INVALID: return 0
        case .WEAK: return 1
        case .AMBIGUOUS: return 2
        case .STRONG: return 3
        case .VERIFIED: return 4
        }
    }
}

/// Sources of confidence, standardized across the system.
public enum ConfidenceSourceV1: String, Codable, Sendable, Equatable, Comparable {
    case audio
    case vision
    case fused

    public static func < (lhs: ConfidenceSourceV1, rhs: ConfidenceSourceV1) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Finite, governed reason codes (v1).
///
/// No free-text reasons are allowed in governed confidence.
public enum ReasonCodeV1: String, Codable, Sendable, Equatable, Comparable {
    // Diarization / identity
    case low_audio_similarity
    case cluster_boundary
    case cluster_merge_applied
    case overlap_crosstalk_detected
    case low_face_overlap
    case track_reacquired
    case offscreen_forced

    // Devices / stability
    case mask_unstable_iou
    case mask_low_coverage
    case flow_unstable
    case teeth_outside_mouth_roi
    case faceparts_model_missing
    case faceparts_infer_failed
    case mobilesam_model_missing
    case mobilesam_infer_failed
    case track_missing
    case track_ambiguous

    // MasterSensors warnings (governed)
    // Video
    case no_face_detected
    case multiple_faces_competing
    case face_too_small
    case underexposed_risk
    case overexposed_risk
    case luma_instability_risk
    case framing_jump_risk

    // Audio
    case audio_silence
    case audio_clip_risk
    case audio_noise_risk

    // Depth
    case depth_missing
    case depth_invalid_range

    public static func < (lhs: ReasonCodeV1, rhs: ReasonCodeV1) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct EvidenceRefV1: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case metric
        case interval
        case device
        case artifact
    }

    public var kind: Kind
    public var id: String?
    public var field: String?
    public var value: Double?

    public init(kind: Kind, id: String? = nil, field: String? = nil, value: Double? = nil) {
        self.kind = kind
        self.id = id
        self.field = field
        self.value = value
    }

    public static func metric(_ field: String, value: Double) -> EvidenceRefV1 {
        EvidenceRefV1(kind: .metric, field: field, value: value)
    }
}
