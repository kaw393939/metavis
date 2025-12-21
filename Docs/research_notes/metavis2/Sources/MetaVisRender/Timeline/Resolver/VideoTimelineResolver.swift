// VideoTimelineResolver.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Resolves timeline time to source clips and handles transitions

import Foundation
import CoreMedia

// MARK: - VideoTimelineResolver

/// Resolves timeline positions to source clips and frames.
///
/// This actor maps a timeline time to:
/// - Which clip(s) are active
/// - The corresponding source time for each clip
/// - Whether a transition is in progress
/// - Transition progress (0-1)
///
/// ## Example
/// ```swift
/// let resolver = VideoTimelineResolver(timeline: timeline)
/// 
/// // Get clip at time
/// if let context = await resolver.resolve(at: 45.5) {
///     print("Source: \(context.source), Time: \(context.sourceTime)")
/// }
/// 
/// // Check for transition
/// if let transition = await resolver.transitionContext(at: 29.5, on: trackID) {
///     print("Transition: \(transition.type), Progress: \(transition.progress)")
/// }
/// ```
public actor VideoTimelineResolver {
    
    // MARK: - Properties
    
    /// The timeline to resolve
    public var timeline: TimelineModel
    
    /// Cache of recent resolutions for performance
    private var cache: [Int: ClipContext] = [:]
    
    /// Frame at which cache was last cleared
    private var cacheFrame: Int = -1
    
    /// Cache size limit
    private let cacheLimit: Int = 100
    
    // MARK: - Initialization
    
    public init(timeline: TimelineModel) {
        self.timeline = timeline
    }
    
    /// Updates the timeline (clears cache).
    public func updateTimeline(_ timeline: TimelineModel) {
        self.timeline = timeline
        clearCache()
    }
    
    /// Clears the resolution cache.
    public func clearCache() {
        cache.removeAll()
    }
    
    // MARK: - Resolution
    
    /// Resolves a timeline time to the active clip context.
    ///
    /// - Parameters:
    ///   - time: Timeline time in seconds
    ///   - trackID: Optional track ID (uses primary track if nil)
    /// - Returns: ClipContext if a clip is active, nil if no clip at this time
    public func resolve(
        at time: Double,
        on trackID: TrackID? = nil
    ) -> ClipContext? {
        // Get the appropriate track
        let track: VideoTrack
        if let trackID = trackID {
            guard let t = timeline.videoTrack(id: trackID) else { return nil }
            track = t
        } else {
            guard let t = timeline.primaryVideoTrack else { return nil }
            track = t
        }
        
        // Find the clip at this time
        guard let clip = track.clipAt(time: time) else {
            return nil
        }
        
        // Calculate source time
        guard let sourceTime = clip.sourceTime(at: time) else {
            return nil
        }
        
        // Check for transition
        if let (transition, progress) = timeline.transitionAt(time: time, track: track.id) {
            return ClipContext(
                clip: clip,
                source: clip.source,
                sourceTime: sourceTime,
                fps: timeline.fps,
                inTransition: true,
                transitionProgress: progress,
                transitionType: transition.type
            )
        }
        
        return ClipContext(
            clip: clip,
            source: clip.source,
            sourceTime: sourceTime,
            fps: timeline.fps
        )
    }
    
    /// Resolves a frame number to the active clip context.
    public func resolve(frame: Int, on trackID: TrackID? = nil) -> ClipContext? {
        let time = Double(frame) / timeline.fps
        return resolve(at: time, on: trackID)
    }
    
    /// Gets the transition context at a given time (if in a transition).
    ///
    /// - Parameters:
    ///   - time: Timeline time in seconds
    ///   - trackID: Track ID (uses primary track if nil)
    /// - Returns: TransitionContext if in a transition, nil otherwise
    public func transitionContext(
        at time: Double,
        on trackID: TrackID? = nil
    ) -> TransitionContext? {
        // Get the appropriate track
        let track: VideoTrack
        if let trackID = trackID {
            guard let t = timeline.videoTrack(id: trackID) else { return nil }
            track = t
        } else {
            guard let t = timeline.primaryVideoTrack else { return nil }
            track = t
        }
        
        // Find active transition
        guard let (transition, progress) = timeline.transitionAt(time: time, track: track.id) else {
            return nil
        }
        
        // Get the clips
        guard let fromClip = timeline.clip(id: transition.fromClip),
              let toClip = timeline.clip(id: transition.toClip) else {
            return nil
        }
        
        // Calculate source times for both clips
        guard let fromSourceTime = fromClip.sourceTime(at: time),
              let toSourceTime = toClip.sourceTime(at: time) else {
            return nil
        }
        
        return TransitionContext(
            fromClip: fromClip,
            toClip: toClip,
            fromSourceTime: fromSourceTime,
            toSourceTime: toSourceTime,
            progress: transition.easedProgress(progress),
            type: transition.type,
            parameters: transition.parameters
        )
    }
    
    // MARK: - Batch Resolution
    
    /// Resolves multiple frames at once for efficient batch processing.
    ///
    /// - Parameters:
    ///   - frames: Array of frame numbers
    ///   - trackID: Track ID
    /// - Returns: Dictionary mapping frame number to ClipContext
    public func resolveBatch(
        frames: [Int],
        on trackID: TrackID? = nil
    ) -> [Int: ClipContext] {
        var results: [Int: ClipContext] = [:]
        for frame in frames {
            if let context = resolve(frame: frame, on: trackID) {
                results[frame] = context
            }
        }
        return results
    }
    
    /// Resolves a time range and returns all clip contexts.
    ///
    /// - Parameters:
    ///   - range: Time range in seconds
    ///   - trackID: Track ID
    /// - Returns: Array of unique clips in the range
    public func resolveRange(
        _ range: ClosedRange<Double>,
        on trackID: TrackID? = nil
    ) -> [ClipDefinition] {
        let track: VideoTrack
        if let trackID = trackID {
            guard let t = timeline.videoTrack(id: trackID) else { return [] }
            track = t
        } else {
            guard let t = timeline.primaryVideoTrack else { return [] }
            track = t
        }
        
        return track.clipsIn(range: range)
    }
    
    // MARK: - Lookahead
    
    /// Returns upcoming clips and transitions for preloading.
    ///
    /// - Parameters:
    ///   - time: Current timeline time
    ///   - lookahead: How far ahead to look (seconds)
    ///   - trackID: Track ID
    /// - Returns: Array of source IDs that will be needed
    public func sourcesNeeded(
        from time: Double,
        lookahead: Double,
        on trackID: TrackID? = nil
    ) -> [String] {
        let range = time...(time + lookahead)
        let clips = resolveRange(range, on: trackID)
        return clips.map { $0.source }
    }
    
    /// Returns upcoming transitions for the given time range.
    public func upcomingTransitions(
        from time: Double,
        lookahead: Double,
        on trackID: TrackID? = nil
    ) -> [(TransitionDefinition, Double)] {
        let track: VideoTrack
        if let trackID = trackID {
            guard let t = timeline.videoTrack(id: trackID) else { return [] }
            track = t
        } else {
            guard let t = timeline.primaryVideoTrack else { return [] }
            track = t
        }
        
        var result: [(TransitionDefinition, Double)] = []
        
        for transition in timeline.transitions {
            guard let toClip = timeline.clip(id: transition.toClip),
                  track.clips.contains(where: { $0.id == transition.toClip }) else {
                continue
            }
            
            let transitionStart = toClip.timelineIn
            if transitionStart >= time && transitionStart <= time + lookahead {
                let timeUntil = transitionStart - time
                result.append((transition, timeUntil))
            }
        }
        
        return result.sorted { $0.1 < $1.1 }
    }
    
    // MARK: - Utilities
    
    /// Converts timeline time to frame number.
    public func frameNumber(at time: Double) -> Int {
        Int((time * timeline.fps).rounded())
    }
    
    /// Converts frame number to timeline time.
    public func time(at frame: Int) -> Double {
        Double(frame) / timeline.fps
    }
    
    /// Returns the active clip IDs at a given time.
    public func activeClipIDs(at time: Double) -> [ClipID] {
        timeline.clipsAt(time: time).map { $0.id }
    }
    
    /// Returns whether the timeline has any content at the given time.
    public func hasContent(at time: Double) -> Bool {
        !timeline.clipsAt(time: time).isEmpty
    }
}

// MARK: - ResolvedFrame

/// A fully resolved frame ready for decoding.
public struct ResolvedFrame: Sendable {
    /// Frame number on the timeline
    public let frame: Int
    
    /// Timeline time
    public let time: Double
    
    /// Whether this frame is in a transition
    public let inTransition: Bool
    
    /// Primary source to decode
    public let primarySource: String
    
    /// Primary source time
    public let primarySourceTime: CMTime
    
    /// Secondary source (for transitions)
    public let secondarySource: String?
    
    /// Secondary source time
    public let secondarySourceTime: CMTime?
    
    /// Transition progress (0-1)
    public let transitionProgress: Double?
    
    /// Transition type
    public let transitionType: VideoTransitionType?
    
    /// Transition parameters
    public let transitionParameters: TransitionParameters?
    
    public init(
        frame: Int,
        time: Double,
        primarySource: String,
        primarySourceTime: CMTime,
        inTransition: Bool = false,
        secondarySource: String? = nil,
        secondarySourceTime: CMTime? = nil,
        transitionProgress: Double? = nil,
        transitionType: VideoTransitionType? = nil,
        transitionParameters: TransitionParameters? = nil
    ) {
        self.frame = frame
        self.time = time
        self.primarySource = primarySource
        self.primarySourceTime = primarySourceTime
        self.inTransition = inTransition
        self.secondarySource = secondarySource
        self.secondarySourceTime = secondarySourceTime
        self.transitionProgress = transitionProgress
        self.transitionType = transitionType
        self.transitionParameters = transitionParameters
    }
}

// MARK: - Convenience Extensions

extension VideoTimelineResolver {
    /// Creates a ResolvedFrame for a given frame number.
    public func resolvedFrame(
        _ frame: Int,
        on trackID: TrackID? = nil
    ) -> ResolvedFrame? {
        let time = self.time(at: frame)
        
        // Check for transition first
        if let transition = transitionContext(at: time, on: trackID) {
            return ResolvedFrame(
                frame: frame,
                time: time,
                primarySource: transition.fromClip.source,
                primarySourceTime: transition.fromSourceTimeCMTime(fps: timeline.fps),
                inTransition: true,
                secondarySource: transition.toClip.source,
                secondarySourceTime: transition.toSourceTimeCMTime(fps: timeline.fps),
                transitionProgress: transition.progress,
                transitionType: transition.type,
                transitionParameters: transition.parameters
            )
        }
        
        // Regular clip
        if let context = resolve(at: time, on: trackID) {
            return ResolvedFrame(
                frame: frame,
                time: time,
                primarySource: context.source,
                primarySourceTime: context.sourceTimeCMTime
            )
        }
        
        return nil
    }
}
