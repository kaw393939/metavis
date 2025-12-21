import Foundation

public struct Node: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var type: String
    public var position: SIMD2<Float>
    
    /// Strongly typed properties for the node.
    public var properties: [String: NodeValue] 
    
    public var inputs: [NodePort]
    public var outputs: [NodePort]
    
    public var subGraphId: UUID?
    
    public init(
        id: UUID = UUID(),
        name: String,
        type: String,
        position: SIMD2<Float> = .zero,
        properties: [String: NodeValue] = [:],
        inputs: [NodePort] = [],
        outputs: [NodePort] = [],
        subGraphId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.position = position
        self.properties = properties
        self.inputs = inputs
        self.outputs = outputs
        self.subGraphId = subGraphId
    }
}
