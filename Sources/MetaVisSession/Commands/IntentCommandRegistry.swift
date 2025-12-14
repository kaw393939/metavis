import Foundation
import MetaVisCore
import MetaVisServices

public enum IntentCommandRegistry {
    public static func commands(for intent: UserIntent) -> [IntentCommand] {
        switch intent.action {
        case .colorGrade:
            return [.applyColorGradeToFirstVideoClip(target: intent.target, params: intent.params)]
        case .cut:
            // Simplest deterministic mapping: if `time` is present, treat as trim end.
            if let t = intent.params["time"], t.isFinite {
                return [.trimEndOfFirstVideoClip(atSeconds: max(0, t))]
            }
            return []
        case .speed:
            if let s = intent.params["factor"], s.isFinite {
                return [.retimeFirstVideoClip(speedFactor: max(0.01, s))]
            }
            if let s = intent.params["speed"], s.isFinite {
                return [.retimeFirstVideoClip(speedFactor: max(0.01, s))]
            }
            return []
        case .unknown:
            return []
        }
    }
}
