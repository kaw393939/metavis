import Foundation

public struct FeatureManifestValidationError: Error, Sendable, Equatable {
    public let code: String
    public let featureID: String?
    public let message: String

    public init(code: String, featureID: String?, message: String) {
        self.code = code
        self.featureID = featureID
        self.message = message
    }
}

public enum FeatureManifestValidator {
    /// Validates a manifest for registry-load purposes.
    ///
    /// This enforces *manifest-level* invariants and the declared compilation domain.
    ///
    /// In particular, clip-scoped manifests must only declare input ports supported by
    /// `TimelineCompiler.compileEffects(...)` so incompatibility is discovered early.
    public static func validateForRegistryLoad(_ manifest: FeatureManifest) -> [FeatureManifestValidationError] {
        var errors: [FeatureManifestValidationError] = []

        if manifest.schemaVersion != 1 {
            errors.append(.init(code: "MVFM001", featureID: manifest.id, message: "Unsupported schemaVersion: \(manifest.schemaVersion)"))
        }

        if manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.init(code: "MVFM010", featureID: manifest.id, message: "Feature id is empty"))
        }

        let inferred = FeatureManifest.Domain.infer(from: manifest.id)
        if manifest.domain != inferred {
            errors.append(.init(code: "MVFM011", featureID: manifest.id, message: "Domain \(manifest.domain.rawValue) does not match inferred domain \(inferred.rawValue) for id \(manifest.id)"))
        }

        if manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.init(code: "MVFM012", featureID: manifest.id, message: "Version is empty"))
        }

        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.init(code: "MVFM013", featureID: manifest.id, message: "Name is empty"))
        }

        // Ports must have unique names.
        let portNames = manifest.inputs.map { $0.name }
        if Set(portNames).count != portNames.count {
            errors.append(.init(code: "MVFM020", featureID: manifest.id, message: "Duplicate input port names"))
        }

        // Compilation-domain sanity: prevent late compiler discovery of incompatibility.
        if manifest.domain == .video, manifest.compilationDomain == .clip {
            let supportedClipPorts: Set<String> = ["source", "input", "faceMask"]
            for port in manifest.inputs {
                if !supportedClipPorts.contains(port.name) {
                    errors.append(
                        .init(
                            code: "MVFM060",
                            featureID: manifest.id,
                            message: "compilationDomain=clip but declares unsupported input port '\(port.name)'. Supported clip ports: \(supportedClipPorts.sorted().joined(separator: ", "))"
                        )
                    )
                }
            }
        }

        // Parameter sanity.
        for param in manifest.parameters {
            switch param {
            case let .float(name, min, max, def):
                if min > max {
                    errors.append(.init(code: "MVFM030", featureID: manifest.id, message: "Float param \(name) has min > max"))
                } else if def < min || def > max {
                    errors.append(.init(code: "MVFM031", featureID: manifest.id, message: "Float param \(name) default \(def) out of range [\(min), \(max)]"))
                }
            case let .int(name, min, max, def):
                if min > max {
                    errors.append(.init(code: "MVFM032", featureID: manifest.id, message: "Int param \(name) has min > max"))
                } else if def < min || def > max {
                    errors.append(.init(code: "MVFM033", featureID: manifest.id, message: "Int param \(name) default \(def) out of range [\(min), \(max)]"))
                }
            case .bool:
                break
            case .color:
                break
            case .vector3:
                break
            }
        }

        switch manifest.domain {
        case .video:
            let hasKernel = !manifest.kernelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPasses = (manifest.passes?.isEmpty == false)
            if !hasKernel && !hasPasses {
                errors.append(.init(code: "MVFM040", featureID: manifest.id, message: "Video manifest must have kernelName or passes"))
            }
        case .audio, .intrinsic:
            // kernelName is intentionally allowed to be empty for non-video manifests.
            break
        }

        return errors
    }
}
