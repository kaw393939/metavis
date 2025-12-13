import Foundation

/// A single operation in the render graph.
public struct RenderNode: Identifiable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let shader: String           // Metal Kernel Name
    public let inputs: [String: UUID]   // Port Name : Input Node ID
    public let parameters: [String: NodeValue]
    public let timing: TimeRange?       // If nil, valid for all t
    
    public init(
        id: UUID = UUID(),
        name: String,
        shader: String,
        inputs: [String: UUID] = [:],
        parameters: [String: NodeValue] = [:],
        timing: TimeRange? = nil
    ) {
        self.id = id
        self.name = name
        self.shader = shader
        self.inputs = inputs
        self.parameters = parameters
        self.timing = timing
    }
}

/// The Directed Acyclic Graph describing a frame render.
public struct RenderGraph: Sendable, Codable {
    public let id: UUID
    public let nodes: [RenderNode]
    public let rootNodeID: UUID // The node to output
    
    public init(id: UUID = UUID(), nodes: [RenderNode], rootNodeID: UUID) {
        self.id = id
        self.nodes = nodes
        self.rootNodeID = rootNodeID
    }
}
