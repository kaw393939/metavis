import Foundation
import MetaVisCore

/// Ensures the built-in feature set is registered exactly once.
public actor FeatureRegistryBootstrap {
    public static let shared = FeatureRegistryBootstrap()

    private var didRegisterStandardFeatures = false
    private var didLoadBundleManifests = false

    public func ensureStandardFeaturesRegistered(trace: any TraceSink = NoOpTraceSink()) async throws {
        if !didRegisterStandardFeatures {
            await trace.record("feature_registry.bootstrap.standard_features.begin", fields: [:])
            await StandardFeatures.registerAll()
            didRegisterStandardFeatures = true
            await trace.record("feature_registry.bootstrap.standard_features.end", fields: [:])
        }

        if !didLoadBundleManifests {
            await trace.record("feature_registry.bootstrap.bundle_manifests.begin", fields: [:])
            let loader = FeatureRegistryLoader(trace: trace)

            // Load+validate deterministically, but do not overwrite in-memory StandardFeatures.
            let manifests = try loader.loadManifests()
            for m in manifests {
                if await FeatureRegistry.shared.feature(for: m.id) == nil {
                    await FeatureRegistry.shared.register(m)
                }
            }
            didLoadBundleManifests = true
            await trace.record("feature_registry.bootstrap.bundle_manifests.end", fields: [:])
        }

        // Final safety belt: validate the in-memory registry.
        try await FeatureRegistry.shared.validateRegistry()
    }
}
