import Foundation

/// Defines the subscription or access level of the user.
public enum LicenseTier: String, Codable, Sendable, Comparable {
    case free
    case pro
    case studio
    case enterprise
    
    /// Comparable conformance for tier checking (e.g. if tier >= .pro)
    public static func < (lhs: LicenseTier, rhs: LicenseTier) -> Bool {
        switch (lhs, rhs) {
        case (.free, .pro), (.free, .studio), (.free, .enterprise): return true
        case (.pro, .studio), (.pro, .enterprise): return true
        case (.studio, .enterprise): return true
        default: return false
        }
    }
}

/// Specific features that can be gated by a license.
public enum LicenseFeature: String, Codable, Sendable {
    case export4K
    case exportProRes
    case aiGenerativeVideo
    case unlimitedProjects
    case advancedColorGrading
}
