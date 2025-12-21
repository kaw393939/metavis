import Foundation
import MetaVisCore
import MetaVisServices

public enum IntentCommandRegistry {
    public static func commands(for intent: UserIntent) -> [IntentCommand] {
        let target: ClipTarget = intent.clipId.map { .clipId($0) } ?? .firstVideoClip

        func firstFinite(_ keys: [String]) -> Double? {
            for k in keys {
                if let v = intent.params[k], v.isFinite {
                    return v
                }
            }
            return nil
        }

        switch intent.action {
        case .colorGrade:
            return [.applyColorGrade(target: target, gradeTarget: intent.target, params: intent.params)]
        case .cut:
            // Simplest deterministic mapping: if `time` is present, treat as a blade (cut) at time.
            if let t = firstFinite(["time", "at", "seconds"]) {
                return [.bladeClip(target: target, atSeconds: max(0, t))]
            }
            return []
        case .speed:
            if let s = firstFinite(["factor", "speed"]) {
                return [.retimeClip(target: target, speedFactor: max(0.01, s))]
            }
            return []
        case .move:
            if let t = firstFinite(["start", "start_seconds", "time", "to"]) {
                return [.moveClip(target: target, toStartSeconds: max(0, t))]
            }
            return []
        case .trimIn:
            if let o = firstFinite(["offset", "offset_seconds", "in", "trim_in"]) {
                return [.trimClipIn(target: target, toOffsetSeconds: max(0, o))]
            }
            return []
        case .trimEnd:
            if let t = firstFinite(["end", "end_seconds", "time", "to"]) {
                return [.trimClipEnd(target: target, atSeconds: max(0, t))]
            }
            return []
        case .rippleTrimOut:
            if let t = firstFinite(["end", "end_seconds", "time", "to"]) {
                return [.rippleTrimOut(target: target, newEndSeconds: max(0, t))]
            }
            return []

        case .rippleTrimIn:
            if let o = firstFinite(["offset", "offset_seconds", "in", "trim_in"]) {
                return [.rippleTrimIn(target: target, newOffsetSeconds: max(0, o))]
            }
            return []

        case .rippleDelete:
            return [.rippleDelete(target: target)]
        case .unknown:
            return []
        }
    }
}
