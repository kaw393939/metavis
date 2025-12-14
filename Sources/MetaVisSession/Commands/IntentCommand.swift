import Foundation
import MetaVisCore

public enum IntentCommand: Sendable, Equatable {
    case applyColorGradeToFirstVideoClip(target: String, params: [String: Double])
    case trimEndOfFirstVideoClip(atSeconds: Double)
    case retimeFirstVideoClip(speedFactor: Double)
}
