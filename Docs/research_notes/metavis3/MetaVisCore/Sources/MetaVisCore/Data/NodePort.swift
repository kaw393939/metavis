import Foundation

public typealias PortID = String

public enum PortType: String, Codable, Hashable, Sendable {
    case image
    case audio
    case depth // LiDAR depth maps or Z-buffers
    case cameraData // ARKit/Vision Pro tracking matrices
    case float
    case vector3
    case string
    case event
    case unknown
}

public struct NodePort: Identifiable, Codable, Hashable, Sendable {
    public let id: PortID
    public var name: String
    public var type: PortType
    
    public init(id: PortID, name: String, type: PortType) {
        self.id = id
        self.name = name
        self.type = type
    }
}
