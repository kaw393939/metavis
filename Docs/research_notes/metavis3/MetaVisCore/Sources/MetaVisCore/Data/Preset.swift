import Foundation

/// A Preset represents a pre-configured subgraph of nodes that acts as a single tool.
/// It separates the "Exposed Interface" (for UI/Agents) from the "Internal Logic" (for Engine).
public struct Preset: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    
    /// The internal node graph that implements this preset.
    public let internalGraph: NodeGraph
    
    /// A mapping of "Exposed Name" -> "InternalNodeName.Property".
    /// Example: "Softness" -> "GaussianBlurNode.radius"
    public let exposedParameters: [String: String]
    
    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        internalGraph: NodeGraph,
        exposedParameters: [String: String]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.internalGraph = internalGraph
        self.exposedParameters = exposedParameters
    }
}
