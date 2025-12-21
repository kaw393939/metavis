import Foundation
import MetaVisCore

/// A semantic grouping of media and action that occurs in a specific location and time.
/// In MetaVis, a Scene is represented as a Specialized Timeline Segment or a container.
/// It wraps a Timeline but adds metadata relevant to the script/storyboard.
public struct Scene: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    
    /// The timeline that represents this scene's content.
    public var timeline: Timeline
    
    /// Script/Screenplay metadata
    public var scriptLocation: String?
    public var scriptTime: String? // INT/EXT DAY, etc.
    
    /// The ID of the project this scene belongs to.
    public let projectId: UUID
    
    public init(
        id: UUID = UUID(),
        name: String,
        timeline: Timeline,
        projectId: UUID,
        scriptLocation: String? = nil,
        scriptTime: String? = nil
    ) {
        self.id = id
        self.name = name
        self.timeline = timeline
        self.projectId = projectId
        self.scriptLocation = scriptLocation
        self.scriptTime = scriptTime
    }
}
