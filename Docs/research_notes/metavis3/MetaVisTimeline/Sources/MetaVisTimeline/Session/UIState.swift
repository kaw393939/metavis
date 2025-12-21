import Foundation

/// Represents the persistent UI configuration for a session.
/// This allows the Agent to "see" what the user sees and even reconfigure the workspace.
public struct UIState: Codable, Sendable {
    public enum Theme: String, Codable, Sendable {
        case light
        case dark
        case system
    }
    
    public enum TimelinePosition: String, Codable, Sendable {
        case bottom
        case top
    }
    
    public var theme: Theme = .system
    public var timelinePosition: TimelinePosition = .bottom
    
    /// Which panels are currently open?
    public var isLeftDrawerOpen: Bool = true
    public var isRightDrawerOpen: Bool = true
    public var isInspectorOpen: Bool = true
    
    /// The active tab in the Left Drawer (e.g., "Project", "Effects", "Devices")
    public var activeLeftTab: String = "Project"
    
    public init() {}
}
