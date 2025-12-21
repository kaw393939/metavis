import Foundation
import MetaVisCore

/// A Track is a container for Clips.
/// It ensures that clips do not overlap in time.
public struct Track: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var type: TrackType
    public private(set) var clips: [Clip] = []
    
    public init(id: UUID = UUID(), name: String, type: TrackType = .generic) {
        self.id = id
        self.name = name
        self.type = type
    }
    
    /// Adds a clip to the track.
    /// - Throws: `TimelineError.clipOverlap` if the clip overlaps with an existing clip.
    public mutating func add(_ clip: Clip) throws {
        // Find insertion index using binary search
        // We want the first clip that starts AFTER or AT the new clip's start.
        var low = 0
        var high = clips.count
        
        while low < high {
            let mid = (low + high) / 2
            if clips[mid].range.start < clip.range.start {
                low = mid + 1
            } else {
                high = mid
            }
        }
        
        let insertIndex = low
        
        // Check overlap with predecessor (if any)
        if insertIndex > 0 {
            let prev = clips[insertIndex - 1]
            // Overlap if prev.end > clip.start
            if prev.range.end > clip.range.start {
                throw TimelineError.clipOverlap
            }
        }
        
        // Check overlap with successor (if any)
        if insertIndex < clips.count {
            let next = clips[insertIndex]
            // Overlap if clip.end > next.start
            if clip.range.end > next.range.start {
                throw TimelineError.clipOverlap
            }
        }
        
        clips.insert(clip, at: insertIndex)
    }
    
    /// Removes a clip by its ID.
    public mutating func remove(id: UUID) {
        clips.removeAll { $0.id == id }
    }
    
    /// Finds the clip at the given time.
    /// Returns nil if no clip exists at that time.
    public func clip(at time: RationalTime) -> Clip? {
        // Binary search for performance O(log n)
        var low = 0
        var high = clips.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let clip = clips[mid]
            
            if clip.range.contains(time) {
                return clip
            }
            
            if clip.range.start > time {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    /// Updates a clip in place, ensuring no overlaps occur.
    /// - Throws: `TimelineError.clipOverlap` if the update causes a collision.
    /// - Throws: `TimelineError.notFound` if the clip ID is invalid.
    public mutating func updateClip(id: UUID, transform: (inout Clip) -> Void) throws {
        guard let index = clips.firstIndex(where: { $0.id == id }) else {
            throw TimelineError.notFound
        }
        
        var updatedClip = clips[index]
        transform(&updatedClip)
        
        // Check for overlap with ALL OTHER clips
        // We temporarily remove the old clip logic by skipping the current index
        for (i, existing) in clips.enumerated() {
            if i == index { continue }
            
            if updatedClip.range.start < existing.range.end && existing.range.start < updatedClip.range.end {
                throw TimelineError.clipOverlap
            }
        }
        
        // Apply update
        clips[index] = updatedClip
        
        // Re-sort if start time changed
        // Optimization: Only sort if needed, but for safety we sort.
        clips.sort { $0.range.start < $1.range.start }
    }
}
