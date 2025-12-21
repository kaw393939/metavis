import Foundation
import MetaVisCore

/// A Timeline represents a sequence of media composed of multiple tracks.
public struct Timeline: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var tracks: [Track] = []
    
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
    
    public mutating func addTrack(_ track: Track) {
        tracks.append(track)
    }
    
    public mutating func removeTrack(id: UUID) {
        tracks.removeAll { $0.id == id }
    }
    
    /// Calculates the total duration of the timeline based on the end of the last clip.
    public var duration: RationalTime {
        var maxEnd = RationalTime.zero
        
        for track in tracks {
            // Since clips are sorted by start time and non-overlapping,
            // the last clip always determines the track's end time.
            if let lastClip = track.clips.last {
                if lastClip.range.end > maxEnd {
                    maxEnd = lastClip.range.end
                }
            }
        }
        
        return maxEnd
    }
    
    /// Returns all clips active at the given time across all tracks.
    public func activeClips(at time: RationalTime) -> [Clip] {
        var active: [Clip] = []
        for track in tracks {
            if let clip = track.clip(at: time) {
                active.append(clip)
            }
        }
        return active
    }
}
