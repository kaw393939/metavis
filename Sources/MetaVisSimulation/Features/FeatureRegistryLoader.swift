import Foundation
import MetaVisGraphics
import MetaVisCore

public enum FeatureRegistryLoaderError: Error, Sendable, Equatable {
    case noManifestsFound(subdirectory: String?)
    case decodeFailed(file: String)
    case validationFailed(file: String, errors: [FeatureManifestValidationError])
}

/// Loads `FeatureManifest` JSON files from a bundle.
public struct FeatureRegistryLoader: Sendable {
    public let bundle: Bundle
    public let subdirectory: String?
    public let trace: any TraceSink

    public init(
        bundle: Bundle = GraphicsBundleHelper.bundle,
        subdirectory: String? = nil,
        trace: any TraceSink = NoOpTraceSink()
    ) {
        self.bundle = bundle
        self.subdirectory = subdirectory
        self.trace = trace
    }

    public func loadManifests() throws -> [FeatureManifest] {
        Task { await trace.record("feature_registry.loader.load_manifests.begin", fields: ["subdirectory": subdirectory ?? "<nil>"]) }
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory), !urls.isEmpty else {
            Task { await trace.record("feature_registry.loader.load_manifests.none_found", fields: ["subdirectory": subdirectory ?? "<nil>"]) }
            throw FeatureRegistryLoaderError.noManifestsFound(subdirectory: subdirectory)
        }

        let decoder = JSONDecoder()
        let manifests = try urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).map { url in
            do {
                let data = try Data(contentsOf: url)
                let manifest = try decoder.decode(FeatureManifest.self, from: data)
                let validationErrors = FeatureManifestValidator.validateForRegistryLoad(manifest)
                if !validationErrors.isEmpty {
                    Task {
                        await trace.record(
                            "feature_registry.loader.validation_failed",
                            fields: [
                                "file": url.lastPathComponent,
                                "id": manifest.id,
                                "errors": validationErrors.map { "\($0.code):\($0.message)" }.joined(separator: " | ")
                            ]
                        )
                    }
                    throw FeatureRegistryLoaderError.validationFailed(file: url.lastPathComponent, errors: validationErrors)
                }
                return manifest
            } catch let err as FeatureRegistryLoaderError {
                // Preserve typed loader errors (e.g. validationFailed).
                throw err
            } catch {
                Task { await trace.record("feature_registry.loader.decode_failed", fields: ["file": url.lastPathComponent]) }
                throw FeatureRegistryLoaderError.decodeFailed(file: url.lastPathComponent)
            }
        }

        Task { await trace.record("feature_registry.loader.load_manifests.end", fields: ["count": String(manifests.count)]) }
        return manifests
    }

    @discardableResult
    public func load(into registry: FeatureRegistry) async throws -> [FeatureManifest] {
        await trace.record("feature_registry.loader.load_into.begin", fields: ["subdirectory": subdirectory ?? "<nil>"]) 
        let manifests = try loadManifests()
        for m in manifests {
            let willOverwrite = await registry.feature(for: m.id) != nil
            await trace.record(
                "feature_registry.loader.register",
                fields: [
                    "id": m.id,
                    "domain": m.domain.rawValue,
                    "schemaVersion": String(m.schemaVersion),
                    "overwrite": willOverwrite ? "true" : "false"
                ]
            )
            await registry.register(m)
        }
        await trace.record("feature_registry.loader.load_into.end", fields: ["count": String(manifests.count)])
        return manifests
    }
}
