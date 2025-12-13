import Foundation
import MetaVisGraphics

public enum FeatureRegistryLoaderError: Error, Sendable, Equatable {
    case noManifestsFound(subdirectory: String?)
    case decodeFailed(file: String)
}

/// Loads `FeatureManifest` JSON files from a bundle.
public struct FeatureRegistryLoader: Sendable {
    public let bundle: Bundle
    public let subdirectory: String?

    public init(bundle: Bundle = GraphicsBundleHelper.bundle, subdirectory: String? = nil) {
        self.bundle = bundle
        self.subdirectory = subdirectory
    }

    public func loadManifests() throws -> [FeatureManifest] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory), !urls.isEmpty else {
            throw FeatureRegistryLoaderError.noManifestsFound(subdirectory: subdirectory)
        }

        let decoder = JSONDecoder()
        return try urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).map { url in
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(FeatureManifest.self, from: data)
            } catch {
                throw FeatureRegistryLoaderError.decodeFailed(file: url.lastPathComponent)
            }
        }
    }

    @discardableResult
    public func load(into registry: FeatureRegistry) async throws -> [FeatureManifest] {
        let manifests = try loadManifests()
        for m in manifests {
            await registry.register(m)
        }
        return manifests
    }
}
