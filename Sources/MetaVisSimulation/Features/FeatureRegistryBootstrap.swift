import Foundation

/// Ensures the built-in feature set is registered exactly once.
public actor FeatureRegistryBootstrap {
    public static let shared = FeatureRegistryBootstrap()

    private var didRegisterStandardFeatures = false

    public func ensureStandardFeaturesRegistered() async {
        guard !didRegisterStandardFeatures else { return }
        await StandardFeatures.registerAll()
        didRegisterStandardFeatures = true
    }
}
