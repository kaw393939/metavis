import Foundation

/// High-level runtime render policy tiers.
///
/// These are intended to be product-facing knobs ("consumer", "creator", "studio") that
/// deterministically configure engine defaults.
public enum RenderPolicyTier: String, Codable, Sendable, CaseIterable {
    case consumer
    case creator
    case studio

    /// Parse a tier from user/config input.
    public static func parse(_ raw: String) -> RenderPolicyTier? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return RenderPolicyTier(rawValue: trimmed)
    }
}

/// Concrete defaults associated with a render policy tier.
public struct RenderPolicy: Sendable, Equatable {
    public var tier: RenderPolicyTier
    public var edgePolicy: RenderRequest.EdgeCompatibilityPolicy

    public init(tier: RenderPolicyTier, edgePolicy: RenderRequest.EdgeCompatibilityPolicy) {
        self.tier = tier
        self.edgePolicy = edgePolicy
    }
}

/// Registry of built-in render policy tiers.
public enum RenderPolicyCatalog {
    public static func policy(for tier: RenderPolicyTier) -> RenderPolicy {
        switch tier {
        case .consumer:
            // Consumer: prefer speed and resilience over strict authored-graph correctness.
            return RenderPolicy(tier: tier, edgePolicy: .autoResizeBilinear)
        case .creator:
            // Creator: still resilient, but higher-quality default resampling.
            return RenderPolicy(tier: tier, edgePolicy: .autoResizeBicubic)
        case .studio:
            // Studio: strict graph correctness; require explicit adapter nodes for auditability.
            return RenderPolicy(tier: tier, edgePolicy: .requireExplicitAdapters)
        }
    }
}
