import Foundation

/// Represents a dependency on another external project.
/// Allows projects to be composed (e.g. a "Master" project importing "Scene 1" and "Scene 2").
public struct ProjectImport: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    
    /// The ID of the external project being imported.
    public let projectId: UUID
    
    /// A local alias/namespace for the imported project to avoid naming collisions.
    public let namespace: String
    
    /// The version of the project at the time of import (for locking).
    public let versionLock: UUID?
    
    public init(id: UUID = UUID(), projectId: UUID, namespace: String, versionLock: UUID? = nil) {
        self.id = id
        self.projectId = projectId
        self.namespace = namespace
        self.versionLock = versionLock
    }
}
