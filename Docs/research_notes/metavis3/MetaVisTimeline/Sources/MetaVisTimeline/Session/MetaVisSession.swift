import Foundation
import MetaVisCore

/// Represents the high-level state of a user's editing session.
/// This is the "Brain" that the Local Agent interacts with.
/// It manages the "Real" timeline, "Shadow" timelines (for AI experiments),
/// and project-level metadata like the Cast Registry.
public struct MetaVisSession: Identifiable, Codable, Sendable {
    public let id: UUID
    
    /// The primary timeline the user is viewing/editing.
    public var activeTimeline: Timeline
    
    /// A dictionary of "Shadow Timelines" created by Agents or for A/B testing.
    /// Key is the Timeline ID.
    public var shadowTimelines: [UUID: Timeline] = [:]
    
    /// The registry of people identified in this session.
    public var cast: CastRegistry
    
    /// The registry of Virtual Devices (Cameras, Lights, Generators).
    public var devices: DeviceRegistry
    
    /// The registry of media assets (Videos, Images, Audio).
    public var assets: AssetRegistry
    
    /// The active script or transcript for the session.
    public var script: Script?
    
    /// UI State Configuration
    /// Stores user preferences for layout, theme, and active panels.
    public var uiState: UIState
    
    public init(id: UUID = UUID(), timeline: Timeline = Timeline(name: "Main")) {
        self.id = id
        self.activeTimeline = timeline
        self.cast = CastRegistry()
        self.devices = DeviceRegistry()
        self.assets = AssetRegistry()
        self.script = nil
        self.uiState = UIState()
    }
    
    /// Creates a copy of the active timeline for experimentation.
    /// Returns the ID of the new shadow timeline.
    public mutating func createShadowTimeline(name: String) -> UUID {
        var shadow = activeTimeline
        shadow.name = name
        let shadowID = UUID() // In a real app, Timeline would have its own ID we might regenerate
        // Note: Timeline struct has 'let id'. To truly fork, we might need to create a new Timeline with new ID but same tracks.
        // For now, we just store it. Ideally Timeline.init(copying: ...)
        
        // Let's assume we want to keep the content but change the ID/Name.
        // Since Timeline.id is 'let', we need a new instance.
        let newTimeline = Timeline(id: shadowID, name: name, tracks: shadow.tracks)
        
        shadowTimelines[shadowID] = newTimeline
        return shadowID
    }
}

// Extension to Timeline to support the copy constructor logic above
extension Timeline {
    public init(id: UUID, name: String, tracks: [Track]) {
        self.id = id
        self.name = name
        self.tracks = tracks
    }
}
