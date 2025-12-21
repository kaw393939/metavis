import Foundation

/// The Canonical Input for the Simulation Engine.
/// This struct must contain EVERYTHING needed to render a frame.
/// Start stateless, end stateless.
public struct RenderRequest: Sendable {
    public let id: UUID
    public let graph: RenderGraph
    public let time: Time
    public let quality: QualityProfile

    /// Optional hint about the render cadence (e.g. export FPS). Used for deterministic
    /// sampling heuristics when a source provides insufficient timing metadata.
    public let renderFPS: Double?
    
    // In a real implementation, this would hold the Asset Registry or Handles.
    // For now, we mock it.
    public let assets: [String: String] // AssetID : Path
    
    public init(
        id: UUID = UUID(),
        graph: RenderGraph,
        time: Time,
        quality: QualityProfile,
        assets: [String: String] = [:],
        renderFPS: Double? = nil
    ) {
        self.id = id
        self.graph = graph
        self.time = time
        self.quality = quality
        self.assets = assets
        self.renderFPS = renderFPS
    }
}
