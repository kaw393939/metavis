import Foundation

/// Defines the creative intent and constraints of a project.
/// This enum drives the UI layout, available tools, and export defaults.
public enum ProjectMode: String, Codable, Sendable, CaseIterable {
    case cinematic      // Standard active timeline
    case musicVideo     // Audio-driven, beat-synced
    case documentary    // Interview/Transcript-driven
    case social         // Vertical, short-form, rapid style
    case laboratory     // Experimental / R&D
    case astrophysics   // JWST / FITS Science Pipeline
    
    public var displayName: String {
        switch self {
        case .cinematic: return "Cinematic"
        case .musicVideo: return "Music Video"
        case .documentary: return "Documentary"
        case .social: return "Social"
        case .laboratory: return "Laboratory"
        case .astrophysics: return "Astrophysics"
        }
    }
    
    public var defaultFrameRate: Double {
        switch self {
        case .cinematic, .documentary: return 23.976
        case .musicVideo: return 24.0
        case .social: return 30.0 // or 60.0
        case .laboratory: return 60.0
        case .astrophysics: return 23.976 // Cinematic default for viewing
        }
    }
}
