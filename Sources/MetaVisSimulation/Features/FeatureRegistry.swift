import Foundation

public enum FeatureRegistryValidationError: Error, LocalizedError, Sendable, Equatable {
    case validationFailed(errors: [FeatureManifestValidationError])
    case registryKeyMismatch(expectedID: String, manifestID: String)

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let errors):
            if errors.isEmpty { return "FeatureRegistry validation failed" }
            let first = errors.prefix(5).map { "\($0.code):\($0.message)" }.joined(separator: " | ")
            return "FeatureRegistry validation failed (\(errors.count) errors): \(first)"
        case .registryKeyMismatch(let expectedID, let manifestID):
            return "FeatureRegistry internal key mismatch: expected '\(expectedID)' but manifest.id was '\(manifestID)'"
        }
    }
}

/// A centralized registry for managing available features (effects/shaders).
/// Thread-safe actor.
public actor FeatureRegistry {
    
    /// Singleton instance for global access (though dependency injection is preferred)
    public static let shared = FeatureRegistry()
    
    private var features: [String: FeatureManifest] = [:]
    
    public init() {}
    
    /// Register a new feature.
    /// - Parameter manifest: The feature manifest to register.
    /// - Throws: Error if the feature ID is invalid or conflicts (policy dependent).
    public func register(_ manifest: FeatureManifest) {
        if let existing = features[manifest.id] {
            // Policy: Overwrite log warning? For now, silent overwrite is useful for hot-reloading.
            print("FeatureRegistry: Overwriting existing feature \(manifest.id) (v\(existing.version) -> v\(manifest.version))")
        }
        features[manifest.id] = manifest
    }
    
    /// Retrieve a feature manifest by ID.
    public func feature(for id: String) -> FeatureManifest? {
        return features[id]
    }
    
    /// Retrieve all registered features.
    public func allFeatures() -> [FeatureManifest] {
        return Array(features.values).sorted { $0.name < $1.name }
    }
    
    /// Retrieve features by category.
    public func features(in category: FeatureCategory) -> [FeatureManifest] {
        return features.values.filter { $0.category == category }.sorted { $0.name < $1.name }
    }
    
    /// Remove a feature
    public func unregister(id: String) {
        features.removeValue(forKey: id)
    }

    /// Validates all registered manifests.
    ///
    /// This is intended as a safety belt for startup/bootstrapping: it catches invalid manifests
    /// that might have been registered programmatically (not via the bundle loader).
    public func validateRegistry() throws {
        // Ensure dictionary keys match manifest ids.
        for (k, v) in features {
            if k != v.id {
                throw FeatureRegistryValidationError.registryKeyMismatch(expectedID: k, manifestID: v.id)
            }
        }

        // Deterministic ordering and stable error surface.
        let manifests = features.values.sorted(by: { $0.id < $1.id })
        var errors: [FeatureManifestValidationError] = []
        for m in manifests {
            errors.append(contentsOf: FeatureManifestValidator.validateForRegistryLoad(m))
        }

        // Stable error ordering.
        errors.sort {
            if $0.featureID != $1.featureID { return ($0.featureID ?? "") < ($1.featureID ?? "") }
            if $0.code != $1.code { return $0.code < $1.code }
            return $0.message < $1.message
        }

        if !errors.isEmpty {
            throw FeatureRegistryValidationError.validationFailed(errors: errors)
        }
    }
}
