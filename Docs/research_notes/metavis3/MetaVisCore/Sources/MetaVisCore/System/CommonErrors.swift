import Foundation

public enum MetaVisError: MetaVisErrorProtocol, Equatable {
    case runtimeError(String)
    case licenseRestricted(feature: String, requiredTier: LicenseTier)
    
    public var code: Int {
        switch self {
        case .runtimeError: return 9000
        case .licenseRestricted: return 9001
        }
    }
    
    public var title: String {
        switch self {
        case .runtimeError: return "Runtime Error"
        case .licenseRestricted: return "Feature Locked"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .runtimeError(let msg): return msg
        case .licenseRestricted(let feature, let tier):
            return "Access Denied: Feature '\(feature)' requires \(tier.rawValue.capitalized) license."
        }
    }
}
