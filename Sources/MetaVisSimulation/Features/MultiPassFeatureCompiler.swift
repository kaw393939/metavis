import Foundation
import MetaVisCore

/// Compiles a `FeatureManifest` into one or more `RenderNode`s.
///
/// This is the Sprint 04 bridge between feature manifests and the current `RenderGraph` execution model
/// (`MetalSimulationEngine` executes nodes in order).
public struct MultiPassFeatureCompiler: Sendable {
    public enum Error: Swift.Error, Sendable, Equatable {
        case missingExternalInput(String)
    }

    private let scheduler: PassScheduler

    public init(scheduler: PassScheduler = PassScheduler()) {
        self.scheduler = scheduler
    }

    /// Compile a manifest into nodes.
    ///
    /// - Parameters:
    ///   - manifest: Feature definition.
    ///   - externalInputs: Mapping from semantic input name to upstream node id (e.g. `source` → generatorNode.id).
    ///   - parameters: Node parameters to apply to each pass node.
    ///   - shaderRegistry: Optional registry used when a pass omits `function`.
    /// - Returns: Nodes in execution order and the root node id.
    public func compile(
        manifest: FeatureManifest,
        externalInputs: [String: UUID],
        parameters: [String: NodeValue] = [:],
        shaderRegistry: ShaderRegistry? = nil
    ) async throws -> (nodes: [RenderNode], rootNodeID: UUID) {
        // Single-pass fallback.
        guard let passes = manifest.passes, !passes.isEmpty else {
            let node = RenderNode(
                name: manifest.name,
                shader: manifest.kernelName,
                inputs: Self.normalizeExternalInputs(externalInputs),
                parameters: parameters
            )
            return (nodes: [node], rootNodeID: node.id)
        }

        let ordered = try scheduler.schedule(passes)

        var nodes: [RenderNode] = []
        nodes.reserveCapacity(ordered.count)

        var produced: [String: UUID] = [:] // outputName -> node id

        for pass in ordered {
            let shaderName: String
            if let f = pass.function {
                shaderName = f
            } else if let shaderRegistry {
                shaderName = try await shaderRegistry.resolveOrThrow(pass.logicalName)
            } else {
                // No function and no registry; treat logicalName as concrete function name.
                shaderName = pass.logicalName
            }

            var nodeInputs: [String: UUID] = [:]

            // Convention:
            // - Single-input passes bind that input to the primary port "input".
            // - Multi-input passes bind the first input to primary port "input",
            //   and bind the remaining inputs using their declared names.
            for (i, inputName) in pass.inputs.enumerated() {
                let upstream: UUID
                if let id = produced[inputName] {
                    upstream = id
                } else if let id = externalInputs[inputName] {
                    upstream = id
                } else if inputName == "input", let id = externalInputs["input"] ?? externalInputs["source"] {
                    upstream = id
                } else if inputName == "source", let id = externalInputs["source"] ?? externalInputs["input"] {
                    upstream = id
                } else {
                    throw Error.missingExternalInput(inputName)
                }

                if pass.inputs.count == 1 {
                    nodeInputs["input"] = upstream
                } else {
                    let port = (i == 0) ? "input" : inputName
                    nodeInputs[port] = upstream
                }
            }

            let node = RenderNode(
                name: "\(manifest.name) — \(pass.logicalName)",
                shader: shaderName,
                inputs: nodeInputs,
                parameters: parameters
            )

            nodes.append(node)
            produced[pass.output] = node.id
        }

        let rootID = nodes.last?.id ?? UUID()
        return (nodes: nodes, rootNodeID: rootID)
    }

    private static func normalizeExternalInputs(_ externalInputs: [String: UUID]) -> [String: UUID] {
        // Preserve multi-input features (e.g. `input` + `mask`, `source` + `faceMask`).
        guard externalInputs.count <= 1 else {
            return externalInputs
        }

        // Engine convention: a single primary input is named `input`.
        if let input = externalInputs["input"] {
            return ["input": input]
        }
        if let source = externalInputs["source"] {
            return ["input": source]
        }
        return externalInputs
    }
}
