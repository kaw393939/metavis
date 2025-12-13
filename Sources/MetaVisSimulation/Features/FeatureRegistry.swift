import Foundation

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
}
