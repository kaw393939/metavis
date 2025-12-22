import Foundation

/// Epistemic confidence type (v1).
///
/// This is a categorical declaration of *how* a value was produced.
/// It complements `ConfidenceRecordV1` (grade/score/reasons/evidence).
public enum ConfidenceLevelV1: String, Codable, Sendable, Equatable {
    /// Computed via deterministic math/hashes/geometry; reproducible.
    case deterministic
    /// Rule-based thresholds / heuristics; reproducible but approximate.
    case heuristic
    /// Output of an ML model with known error characteristics.
    case modelEstimated
    /// Cross-signal reasoning / fusion (auditable, but not purely direct evidence).
    case inferred
}
