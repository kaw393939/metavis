import Foundation
import MetaVisCore

public enum TransitionType: String, Codable, Sendable {
    case dissolve
    case wipe
}

public struct Transition: Codable, Sendable, Equatable {
    public let id: UUID
    public let type: TransitionType
    public let duration: RationalTime
    
    public init(id: UUID = UUID(), type: TransitionType, duration: RationalTime) {
        self.id = id
        self.type = type
        self.duration = duration
    }
}
