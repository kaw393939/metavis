import Foundation
import MetaVisCore

public enum TimelineError: MetaVisErrorProtocol, Equatable {
    case emptyTrack
    case clipOverlap
    case notFound
    case invalidDuration
    
    public var code: Int {
        switch self {
        case .emptyTrack: return 3001
        case .clipOverlap: return 3002
        case .notFound: return 3003
        case .invalidDuration: return 3004
        }
    }
    
    public var title: String {
        switch self {
        case .emptyTrack: return "Empty Keyframe Track"
        case .clipOverlap: return "Clip Overlap"
        case .notFound: return "Item Not Found"
        case .invalidDuration: return "Invalid Duration"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .emptyTrack: return "Cannot evaluate a keyframe track with no keyframes."
        case .clipOverlap: return "The clip overlaps with an existing clip on the track."
        case .notFound: return "The requested item could not be found."
        case .invalidDuration: return "The duration is invalid (negative or mismatched)."
        }
    }
}
