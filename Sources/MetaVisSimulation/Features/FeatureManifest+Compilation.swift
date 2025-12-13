import Foundation
import MetaVisCore
import simd

public extension FeatureManifest {
    /// Default `RenderNode` parameters derived from `parameters`.
    func defaultNodeParameters() -> [String: NodeValue] {
        var initialParameters: [String: NodeValue] = [:]

        for param in parameters {
            switch param {
            case .float(let name, _, _, let def):
                initialParameters[name] = .float(Double(def))
            case .int(let name, _, _, let def):
                // NodeValue currently has no Int; map to float.
                initialParameters[name] = .float(Double(def))
            case .bool(let name, let def):
                initialParameters[name] = .bool(def)
            case .color(let name, let def):
                let doubleColor = SIMD4<Double>(Double(def.x), Double(def.y), Double(def.z), Double(def.w))
                initialParameters[name] = .color(doubleColor)
            case .vector3(let name, let def):
                let doubleVec = SIMD3<Double>(Double(def.x), Double(def.y), Double(def.z))
                initialParameters[name] = .vector3(doubleVec)
            }
        }

        return initialParameters
    }

    /// Compile this feature into one or more `RenderNode`s.
    ///
    /// - Note: Multi-pass compilation is supported when `passes` is present.
    func compileNodes(
        externalInputs: [String: UUID],
        parameterOverrides: [String: NodeValue] = [:],
        shaderRegistry: ShaderRegistry? = nil,
        compiler: MultiPassFeatureCompiler = MultiPassFeatureCompiler()
    ) async throws -> (nodes: [RenderNode], rootNodeID: UUID) {
        let base = defaultNodeParameters().merging(parameterOverrides) { _, new in new }
        return try await compiler.compile(
            manifest: self,
            externalInputs: externalInputs,
            parameters: base,
            shaderRegistry: shaderRegistry
        )
    }
}
