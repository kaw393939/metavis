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
        let sortedURLs = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        let manifests = try sortedURLs.map { url in
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

        // Cross-manifest hardening: collisions + referenced resource verification.
        try validateNoIDCollisions(manifests: manifests, urls: sortedURLs)
        try validateReferencedMetalKernelsExist(manifests: manifests)

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

    private func validateNoIDCollisions(manifests: [FeatureManifest], urls: [URL]) throws {
        precondition(manifests.count == urls.count)

        var firstSeenByID: [String: String] = [:] // id -> first filename

        for (manifest, url) in zip(manifests, urls) {
            if let firstFile = firstSeenByID[manifest.id] {
                let errors: [FeatureManifestValidationError] = [
                    .init(
                        code: "MVFM050",
                        featureID: manifest.id,
                        message: "Duplicate feature id '\(manifest.id)' in '\(url.lastPathComponent)' (already defined in '\(firstFile)')"
                    )
                ]
                Task {
                    await trace.record(
                        "feature_registry.loader.duplicate_id",
                        fields: ["id": manifest.id, "file": url.lastPathComponent, "firstFile": firstFile]
                    )
                }
                throw FeatureRegistryLoaderError.validationFailed(file: url.lastPathComponent, errors: errors)
            }

            firstSeenByID[manifest.id] = url.lastPathComponent
        }
    }

    private func validateReferencedMetalKernelsExist(manifests: [FeatureManifest]) throws {
        // Only validate explicit, concrete function names.
        // (Multi-pass `logicalName` without a `function` may be resolved dynamically via ShaderRegistry.)
        let referencedFunctions: [(featureID: String, function: String)] = manifests.flatMap { m in
            var out: [(String, String)] = []

            let kernel = m.kernelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kernel.isEmpty {
                out.append((m.id, kernel))
            }

            if let passes = m.passes {
                for p in passes {
                    if let f = p.function?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty {
                        out.append((m.id, f))
                    }
                }
            }
            return out
        }

        guard !referencedFunctions.isEmpty else { return }

        let metalSource = try loadCombinedMetalSourceText()

        for (featureID, function) in referencedFunctions {
            guard metalSource.containsKernelVoid(named: function) else {
                let errors: [FeatureManifestValidationError] = [
                    .init(
                        code: "MVFM051",
                        featureID: featureID,
                        message: "Referenced kernel '\(function)' not found in bundle .metal sources"
                    )
                ]
                Task {
                    await trace.record(
                        "feature_registry.loader.missing_kernel",
                        fields: ["id": featureID, "kernel": function]
                    )
                }
                throw FeatureRegistryLoaderError.validationFailed(file: "<bundle>", errors: errors)
            }
        }
    }

    private func loadCombinedMetalSourceText() throws -> String {
        let metalURLs = bundle.urls(forResourcesWithExtension: "metal", subdirectory: nil) ?? []
        guard !metalURLs.isEmpty else {
            // Treat as empty; any referenced kernel will fail deterministically.
            return ""
        }

        // Deterministic order.
        let sorted = metalURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        var combined = ""
        combined.reserveCapacity(64 * 1024)

        for url in sorted {
            // Best-effort: ignore unreadable files.
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                combined.append("\n// --- \(url.lastPathComponent) ---\n")
                combined.append(s)
            }
        }
        return combined
    }
}

private extension String {
    func containsKernelVoid(named functionName: String) -> Bool {
        // Typical pattern: `kernel void fx_name(`
        // We intentionally keep this simple and conservative.
        let escaped = NSRegularExpression.escapedPattern(for: functionName)
        let pattern = "\\bkernel\\s+void\\s+\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return contains(functionName)
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}
