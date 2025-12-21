import Foundation

/// Manages license validation and feature access.
/// This component is the source of truth for "Entitlements".
public actor LicenseManager {
    
    public var currentTier: LicenseTier
    
    public init(tier: LicenseTier = .free) {
        self.currentTier = tier
    }
    
    /// Updates the current license tier (e.g. after In-App Purchase)
    public func setTier(_ tier: LicenseTier) {
        // In a real app, this would verify a receipt or crypto signature.
        self.currentTier = tier
    }
    
    /// Checks if a specific feature is allowed under the current tier.
    public func isAllowed(_ feature: LicenseFeature) -> Bool {
        switch feature {
        case .export4K:
            return currentTier >= .pro
            
        case .exportProRes:
            return currentTier >= .pro
            
        case .aiGenerativeVideo:
            return currentTier >= .studio
            
        case .advancedColorGrading:
            return currentTier >= .pro
            
        case .unlimitedProjects:
            // Free tier limited to small number
            return currentTier >= .pro
        }
    }
    
    /// Throws an error if the feature is not allowed. Useful for guard clauses.
    public func validate(_ feature: LicenseFeature) throws {
        guard isAllowed(feature) else {
            throw MetaVisError.licenseRestricted(feature: feature.rawValue, requiredTier: requiredTier(for: feature))
        }
    }
    
    private func requiredTier(for feature: LicenseFeature) -> LicenseTier {
        switch feature {
        case .export4K, .exportProRes, .advancedColorGrading, .unlimitedProjects:
            return .pro
        case .aiGenerativeVideo:
            return .studio
        }
    }
}


