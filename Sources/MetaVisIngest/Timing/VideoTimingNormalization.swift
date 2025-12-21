import Foundation

/// Deterministic guidance for mapping a potentially-VFR source into a constant-frame-rate timeline/export.
///
/// Scope: this is a *policy suggestion* layer. It does not resample media by itself.
public enum VideoTimingNormalization {

    public struct Decision: Codable, Sendable, Equatable {
        public enum Mode: String, Codable, Sendable, Equatable {
            /// Treat the source as CFR (no special handling).
            case passthrough
            /// Normalize into a constant FPS timebase.
            case normalizeToCFR
        }

        public let mode: Mode
        public let targetFPS: Double
        public let reason: String

        public init(mode: Mode, targetFPS: Double, reason: String) {
            self.mode = mode
            self.targetFPS = targetFPS
            self.reason = reason
        }

        public var frameStepSeconds: Double {
            guard targetFPS.isFinite, targetFPS > 0 else { return 1.0 / 24.0 }
            return 1.0 / targetFPS
        }
    }

    /// Choose a constant FPS timebase for a source.
    ///
    /// Rules (simple + deterministic):
    /// - Prefer nominal FPS when present.
    /// - Else use estimated FPS when present.
    /// - Snap to the nearest common timebase (23.976, 24, 25, 29.97, 30, 50, 59.94, 60) when close.
    /// - If VFR is not likely, return `.passthrough` with the inferred FPS.
    public static func decide(
        profile: VideoTimingProfile,
        fallbackFPS: Double = 24.0,
        snapTolerance: Double = 0.20
    ) -> Decision {
        let inferred = firstPositive(profile.nominalFPS)
            ?? firstPositive(profile.estimatedFPS)
            ?? (fallbackFPS.isFinite && fallbackFPS > 0 ? fallbackFPS : 24.0)

        let snapped = snapToCommonFPS(inferred, tolerance: snapTolerance) ?? inferred
        let target = max(0.0001, snapped)

        if profile.isVFRLikely {
            return Decision(mode: .normalizeToCFR, targetFPS: target, reason: "VFR-likely (PTS deltas varied); normalize to CFR")
        }

        return Decision(mode: .passthrough, targetFPS: target, reason: "CFR-likely; use inferred FPS")
    }

    private static func firstPositive(_ x: Double?) -> Double? {
        guard let x, x.isFinite, x > 0 else { return nil }
        return x
    }

    private static func snapToCommonFPS(_ fps: Double, tolerance: Double) -> Double? {
        guard fps.isFinite, fps > 0 else { return nil }
        let common: [Double] = [23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0]
        var best: (value: Double, delta: Double)? = nil
        for c in common {
            let d = abs(fps - c)
            if best == nil || d < best!.delta {
                best = (c, d)
            }
        }
        guard let best else { return nil }
        return best.delta <= tolerance ? best.value : nil
    }
}
