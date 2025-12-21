import Foundation
import MetaVisCore

/// A segment of the timeline where the active clips are constant.
/// This represents a "node" in the compiled render graph.
public struct TimelineSegment: Identifiable, Equatable {
    public let id: UUID
    public let range: TimeRange
    public let activeClips: [ResolvedClip]
    public let transition: Transition?
    
    public init(id: UUID = UUID(), range: TimeRange, activeClips: [ResolvedClip], transition: Transition? = nil) {
        self.id = id
        self.range = range
        self.activeClips = activeClips
        self.transition = transition
    }
}

/// A resolved clip within a segment, including its computed timing.
public struct ResolvedClip: Identifiable, Equatable {
    public let id: UUID
    public let assetId: UUID
    public let trackIndex: Int
    
    /// The time range of this clip *within the segment*.
    /// This is a subset of the clip's full range.
    public let segmentRange: TimeRange
    
    /// The corresponding time range in the source media.
    public let sourceRange: TimeRange
    
    public init(clip: Clip, trackIndex: Int, segmentRange: TimeRange) {
        self.id = clip.id
        self.assetId = clip.assetId
        self.trackIndex = trackIndex
        self.segmentRange = segmentRange
        
        // Calculate source range based on the segment's position relative to the clip
        let offset = segmentRange.start - clip.range.start
        let sourceStart = clip.sourceRange.start + offset
        
        // Note: sourceStart might be negative if the segment starts before the clip's original start time
        // (e.g., during an incoming transition). The renderer must handle this (e.g., by clamping or looping).
        self.sourceRange = TimeRange(start: sourceStart, duration: segmentRange.duration)
    }
}

/// Compiles a Timeline into a flat sequence of segments.
public class TimelineResolver {
    
    public init() {}
    
    /// Resolves the timeline into a sequence of segments.
    /// Each segment represents a time range where the set of active clips does not change.
    /// Uses a sweep-line algorithm for O(N log N) efficiency.
    public func resolve(timeline: Timeline) -> [TimelineSegment] {
        enum EventType: Int, Comparable {
            case start = 0
            case end = 1
            
            static func < (lhs: EventType, rhs: EventType) -> Bool {
                return lhs.rawValue < rhs.rawValue
            }
        }
        
        struct Event: Comparable {
            let time: RationalTime
            let type: EventType
            let clip: Clip
            let trackIndex: Int
            
            static func < (lhs: Event, rhs: Event) -> Bool {
                if lhs.time != rhs.time {
                    return lhs.time < rhs.time
                }
                // Process END events before START events at the same time
                // This ensures [0, 10) and [10, 20) don't overlap at 10.
                return lhs.type.rawValue > rhs.type.rawValue
            }
            
            static func == (lhs: Event, rhs: Event) -> Bool {
                return lhs.time == rhs.time && lhs.type == rhs.type && lhs.clip == rhs.clip && lhs.trackIndex == rhs.trackIndex
            }
        }
        
        // 1. Collect all events
        var events: [Event] = []
        for (index, track) in timeline.tracks.enumerated() {
            for (clipIndex, clip) in track.clips.enumerated() {
                var startTime = clip.range.start
                var endTime = clip.range.end
                
                // Handle Out Transition (Centered)
                if let transition = clip.outTransition {
                    let halfDuration = RationalTime(value: transition.duration.value, timescale: transition.duration.timescale * 2)
                    endTime = endTime + halfDuration
                }
                
                // Handle In Transition (from previous clip)
                if clipIndex > 0 {
                    let prevClip = track.clips[clipIndex - 1]
                    if let transition = prevClip.outTransition {
                        let halfDuration = RationalTime(value: transition.duration.value, timescale: transition.duration.timescale * 2)
                        startTime = startTime - halfDuration
                    }
                }
                
                events.append(Event(time: startTime, type: .start, clip: clip, trackIndex: index))
                events.append(Event(time: endTime, type: .end, clip: clip, trackIndex: index))
            }
        }
        
        events.sort()
        
        // 2. Sweep line
        var segments: [TimelineSegment] = []
        var activeClips: [Int: [Clip]] = [:] // Track Index -> List of Clips
        var currentTime = events.first?.time ?? .zero
        
        for event in events {
            if event.time > currentTime {
                let duration = event.time - currentTime
                if duration.value > 0 {
                    let segmentRange = TimeRange(start: currentTime, duration: duration)
                    
                    var resolvedClips: [ResolvedClip] = []
                    var activeTransition: Transition? = nil
                    
                    // Process active clips
                    let sortedTracks = activeClips.keys.sorted()
                    for trackIndex in sortedTracks {
                        guard let clips = activeClips[trackIndex], !clips.isEmpty else { continue }
                        
                        for clip in clips {
                            resolvedClips.append(ResolvedClip(clip: clip, trackIndex: trackIndex, segmentRange: segmentRange))
                        }
                        
                        // Detect transition: If a track has > 1 clip, it's a transition.
                        if clips.count > 1 {
                            // Find the clip that has an outTransition
                            if let transitionClip = clips.first(where: { $0.outTransition != nil }) {
                                activeTransition = transitionClip.outTransition
                            }
                        }
                    }
                    
                    if !resolvedClips.isEmpty {
                        segments.append(TimelineSegment(range: segmentRange, activeClips: resolvedClips, transition: activeTransition))
                    }
                }
                currentTime = event.time
            }
            
            // Update state
            switch event.type {
            case .start:
                var clips = activeClips[event.trackIndex] ?? []
                clips.append(event.clip)
                activeClips[event.trackIndex] = clips
            case .end:
                if var clips = activeClips[event.trackIndex] {
                    clips.removeAll(where: { $0.id == event.clip.id })
                    if clips.isEmpty {
                        activeClips.removeValue(forKey: event.trackIndex)
                    } else {
                        activeClips[event.trackIndex] = clips
                    }
                }
            }
        }
        
        return segments
    }
}
