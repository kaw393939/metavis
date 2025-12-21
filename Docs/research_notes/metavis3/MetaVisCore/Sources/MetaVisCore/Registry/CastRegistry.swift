import Foundation

/// A registry for managing identified people in the project.
public struct CastRegistry: Codable, Sendable {
    private var personMap: [UUID: String] = [:]
    
    public init() {}
    
    public mutating func register(id: UUID, name: String) {
        personMap[id] = name
    }
    
    public func name(for id: UUID) -> String? {
        return personMap[id]
    }
}
