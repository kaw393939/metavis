import Foundation

/// Centralized, deterministic mapping from score -> grade (v1).
///
/// No feature code should embed ad-hoc thresholds.
public enum ConfidenceMappingV1 {

    /// Deterministic mapping.
    ///
    /// Thresholds are intentionally simple and versioned.
    public static func grade(for score: Float) -> ConfidenceGradeV1 {
        let s = max(0.0, min(1.0, score))
        if s >= 0.95 { return .VERIFIED }
        if s >= 0.80 { return .STRONG }
        if s >= 0.55 { return .AMBIGUOUS }
        if s >= 0.30 { return .WEAK }
        return .INVALID
    }
}
