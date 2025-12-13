import Foundation

/// The Canonical Input for the Simulation Engine.
/// This struct must contain EVERYTHING needed to render a frame.
/// Start stateless, end stateless.
public struct RenderRequest: Sendable {
    public let id: UUID
    public let graph: RenderGraph
    public let time: Time
    public let quality: QualityProfile
    
    // In a real implementation, this would hold the Asset Registry or Handles.
    // For now, we mock it.
    public let assets: [String: String] // AssetID : Path
    
    public init(
        id: UUID = UUID(),
        graph: RenderGraph,
        time: Time,
        quality: QualityProfile,
        assets: [String: String] = [:]
    ) {
        self.id = id
        self.graph = graph
        self.time = time
        self.quality = quality
        self.assets = assets
    }
}
