import Foundation
import MetaVisCore

public enum ClipTarget: Sendable, Equatable {
    /// Backward-compatible default.
    case firstVideoClip

    /// Deterministic explicit targeting.
    case clipId(UUID)
}

public enum IntentCommand: Sendable, Equatable {
    case applyColorGrade(target: ClipTarget, gradeTarget: String, params: [String: Double])
    /// Absolute timeline seconds.
    case trimClipEnd(target: ClipTarget, atSeconds: Double)
    case retimeClip(target: ClipTarget, speedFactor: Double)

    /// Move clip start to an absolute timeline time.
    case moveClip(target: ClipTarget, toStartSeconds: Double)

    /// "Trim in" as a slip of the source offset (does not change timeline start or duration).
    case trimClipIn(target: ClipTarget, toOffsetSeconds: Double)

    /// Split a clip at an absolute timeline time.
    case bladeClip(target: ClipTarget, atSeconds: Double)

    /// Ripple trim-out to an absolute end time, shifting downstream clips on the same track.
    case rippleTrimOut(target: ClipTarget, newEndSeconds: Double)

    /// Ripple trim-in by setting a new absolute source offset, shifting downstream clips on the same track.
    /// Semantics: adjusts `offset` and compensates `duration` so the media region changes; end time shifts and ripples.
    case rippleTrimIn(target: ClipTarget, newOffsetSeconds: Double)

    /// Ripple delete removes the clip and shifts downstream clips left by the removed clip's duration.
    case rippleDelete(target: ClipTarget)
}

extension IntentCommand {
    public var traceDescription: String {
        func fmt(_ v: Double) -> String { String(format: "%.6f", v) }

        func targetDesc(_ t: ClipTarget) -> String {
            switch t {
            case .firstVideoClip:
                return "firstVideoClip"
            case .clipId(let id):
                return "clipId(\(id.uuidString))"
            }
        }

        switch self {
        case let .applyColorGrade(target, gradeTarget, params):
            let kv = params
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\(fmt($0.value))" }
                .joined(separator: ",")
            return "applyColorGrade(target:\(targetDesc(target)),gradeTarget:\(gradeTarget),params:{\(kv)})"
        case let .trimClipEnd(target, atSeconds):
            return "trimClipEnd(target:\(targetDesc(target)),atSeconds:\(fmt(atSeconds)))"
        case let .retimeClip(target, speedFactor):
            return "retimeClip(target:\(targetDesc(target)),speedFactor:\(fmt(speedFactor)))"
        case let .moveClip(target, toStartSeconds):
            return "moveClip(target:\(targetDesc(target)),toStartSeconds:\(fmt(toStartSeconds)))"
        case let .trimClipIn(target, toOffsetSeconds):
            return "trimClipIn(target:\(targetDesc(target)),toOffsetSeconds:\(fmt(toOffsetSeconds)))"
        case let .bladeClip(target, atSeconds):
            return "bladeClip(target:\(targetDesc(target)),atSeconds:\(fmt(atSeconds)))"
        case let .rippleTrimOut(target, newEndSeconds):
            return "rippleTrimOut(target:\(targetDesc(target)),newEndSeconds:\(fmt(newEndSeconds)))"
        case let .rippleTrimIn(target, newOffsetSeconds):
            return "rippleTrimIn(target:\(targetDesc(target)),newOffsetSeconds:\(fmt(newOffsetSeconds)))"
        case let .rippleDelete(target):
            return "rippleDelete(target:\(targetDesc(target)))"
        }
    }
}
