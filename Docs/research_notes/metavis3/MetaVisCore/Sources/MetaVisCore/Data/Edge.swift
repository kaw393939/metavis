import Foundation

public struct Edge: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let fromNode: UUID
    public let fromPort: PortID
    public let toNode: UUID
    public let toPort: PortID
    
    public init(
        id: UUID = UUID(),
        fromNode: UUID,
        fromPort: PortID,
        toNode: UUID,
        toPort: PortID
    ) {
        self.id = id
        self.fromNode = fromNode
        self.fromPort = fromPort
        self.toNode = toNode
        self.toPort = toPort
    }
}
