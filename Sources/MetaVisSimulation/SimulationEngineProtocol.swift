import Foundation
import MetaVisCore

/// The output of a render operation.
/// For the vertical slice, we mock the texture data.
public struct RenderResult: Sendable {
    public let imageBuffer: Data? // Mocking texture as Data
    public let metadata: [String: String]
}

/// A device capable of executing a RenderGraph.
public protocol SimulationEngineProtocol: Sendable {
    
    /// Configures the engine (e.g. allocates cache).
    func configure() async throws
    
    /// Executes a single frame render.
    func render(request: RenderRequest) async throws -> RenderResult
}
