import Foundation

/// Represents a distinct creative unit in the MetaVis ecosystem.
/// A Project contains metadata, configurations, and a reference to the main storage.
public struct Project: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public let mode: ProjectMode
    
    /// Creation date of the project.
    public let createdAt: Date
    
    /// Last modification date.
    public var updatedAt: Date
    
    /// The root timeline ID for this project.
    /// Note: The actual Timeline object is stored in MetaVisTimeline/Session, 
    /// but the Project holds the pointer to it.
    public var rootTimelineId: UUID
    
    /// Semantic tags for organization
    public var tags: [String]
    
    /// External project dependencies
    public var imports: [ProjectImport]
    
    /// The assets associated with this project.
    public var assets: [Asset] = []
    
    public init(
        id: UUID = UUID(),
        name: String,
        mode: ProjectMode,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        rootTimelineId: UUID = UUID(),
        tags: [String] = [],
        imports: [ProjectImport] = [],
        assets: [Asset] = []
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rootTimelineId = rootTimelineId
        self.tags = tags
        self.imports = imports
        self.assets = assets
    }
}
