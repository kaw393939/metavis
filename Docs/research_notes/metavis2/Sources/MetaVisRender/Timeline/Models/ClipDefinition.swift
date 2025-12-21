// ClipDefinition.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Individual clip definition with source references and timing

import Foundation
import CoreMedia

// MARK: - ClipDefinition

/// Defines a single clip on the timeline.
///
/// A clip references a portion of a source video and places it on the timeline:
/// - `source`: ID of the source in the timeline's source registry
/// - `sourceIn/sourceOut`: The portion of the source to use
/// - `timelineIn`: Where the clip starts on the timeline
/// - `speed`: Playback speed multiplier (1.0 = normal)
///
/// ## Duration Calculation
/// The clip's duration on the timeline is calculated as:
/// ```
/// duration = (sourceOut - sourceIn) / speed
/// ```
///
/// ## Example
/// ```swift
/// let clip = ClipDefinition(
///     source: "interview",
///     sourceIn: 10.0,
///     sourceOut: 45.0,
///     timelineIn: 0.0,
///     speed: 1.0
/// )
/// // Duration: 35 seconds
/// // Plays interview.mov from 10s to 45s, starting at 0s on timeline
/// ```
public struct ClipDefinition: Codable, Sendable, Identifiable, Hashable {
    
    // MARK: - Properties
    
    /// Unique identifier for this clip
    public let id: ClipID
    
    /// Source identifier (key in timeline's sources dictionary)
    public var source: String
    
    /// Start time in the source file (seconds)
    public var sourceIn: Double
    
    /// End time in the source file (seconds)
    public var sourceOut: Double
    
    /// Start time on the timeline (seconds)
    public var timelineIn: Double
    
    /// Playback speed multiplier (1.0 = normal, 2.0 = double speed, 0.5 = half speed)
    public var speed: Double
    
    /// Volume level (0.0 - 1.0)
    public var volume: Float
    
    /// Whether to use frame blending for speed changes
    public var frameBlending: Bool
    
    /// Optional clip name for display
    public var name: String?
    
    /// Whether the clip is disabled/muted
    public var isDisabled: Bool
    
    /// Optional color label for organization
    public var colorLabel: String?
    
    // MARK: - Computed Properties
    
    /// Duration of the source segment (in source time)
    public var sourceDuration: Double {
        sourceOut - sourceIn
    }
    
    /// Duration of the clip on the timeline (accounts for speed)
    public var duration: Double {
        sourceDuration / speed
    }
    
    /// End time on the timeline
    public var timelineOut: Double {
        timelineIn + duration
    }
    
    /// Source in as CMTime
    public var sourceInTime: CMTime {
        CMTime(seconds: sourceIn, preferredTimescale: 90000)
    }
    
    /// Source out as CMTime
    public var sourceOutTime: CMTime {
        CMTime(seconds: sourceOut, preferredTimescale: 90000)
    }
    
    /// Timeline in as CMTime
    public var timelineInTime: CMTime {
        CMTime(seconds: timelineIn, preferredTimescale: 90000)
    }
    
    /// Timeline out as CMTime
    public var timelineOutTime: CMTime {
        CMTime(seconds: timelineOut, preferredTimescale: 90000)
    }
    
    // MARK: - Initialization
    
    /// Creates a new clip definition.
    public init(
        id: ClipID = ClipID(),
        source: String,
        sourceIn: Double,
        sourceOut: Double,
        timelineIn: Double,
        speed: Double = 1.0,
        volume: Float = 1.0,
        frameBlending: Bool = false,
        name: String? = nil,
        isDisabled: Bool = false,
        colorLabel: String? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.timelineIn = timelineIn
        self.speed = max(0.01, speed) // Prevent division by zero
        self.volume = volume
        self.frameBlending = frameBlending
        self.name = name
        self.isDisabled = isDisabled
        self.colorLabel = colorLabel
    }
    
    // MARK: - Time Conversion
    
    /// Converts a timeline time to the corresponding source time.
    ///
    /// - Parameter timelineTime: Time on the timeline in seconds.
    /// - Returns: Corresponding time in the source file, or nil if outside clip bounds.
    public func sourceTime(at timelineTime: Double) -> Double? {
        guard containsTimelineTime(timelineTime) else { return nil }
        
        let offsetInClip = timelineTime - timelineIn
        let sourceOffset = offsetInClip * speed
        return sourceIn + sourceOffset
    }
    
    /// Converts a source time to the corresponding timeline time.
    ///
    /// - Parameter sourceTime: Time in the source file in seconds.
    /// - Returns: Corresponding time on the timeline, or nil if outside source bounds.
    public func timelineTime(at sourceTime: Double) -> Double? {
        guard sourceTime >= sourceIn && sourceTime <= sourceOut else { return nil }
        
        let sourceOffset = sourceTime - sourceIn
        let timelineOffset = sourceOffset / speed
        return timelineIn + timelineOffset
    }
    
    /// Converts a timeline time to the corresponding source CMTime.
    public func sourceTimeAsCMTime(at timelineTime: Double, fps: Double = 30) -> CMTime? {
        guard let time = self.sourceTime(at: timelineTime) else { return nil }
        return CMTime(seconds: time, preferredTimescale: CMTimeScale(fps * 1000))
    }
    
    // MARK: - Bounds Checking
    
    /// Returns whether the given timeline time falls within this clip.
    /// The clip spans [timelineIn, timelineOut) - exclusive end.
    public func containsTimelineTime(_ time: Double) -> Bool {
        time >= timelineIn && time < timelineOut
    }
    
    /// Returns whether the given source time falls within this clip's source range.
    public func containsSourceTime(_ time: Double) -> Bool {
        time >= sourceIn && time < sourceOut
    }
    
    /// Returns whether this clip overlaps with another clip.
    public func overlaps(with other: ClipDefinition) -> Bool {
        timelineIn < other.timelineOut && timelineOut > other.timelineIn
    }
    
    /// Returns the overlap duration with another clip.
    public func overlapDuration(with other: ClipDefinition) -> Double {
        let overlapStart = max(timelineIn, other.timelineIn)
        let overlapEnd = min(timelineOut, other.timelineOut)
        return max(0, overlapEnd - overlapStart)
    }
    
    // MARK: - Modification
    
    /// Creates a copy of this clip with a new ID.
    public func duplicate() -> ClipDefinition {
        ClipDefinition(
            id: ClipID(),
            source: source,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            timelineIn: timelineIn,
            speed: speed,
            volume: volume,
            frameBlending: frameBlending,
            name: name.map { $0 + " copy" },
            isDisabled: isDisabled,
            colorLabel: colorLabel
        )
    }
    
    /// Creates a copy of this clip at a new timeline position.
    public func moved(to newTimelineIn: Double) -> ClipDefinition {
        var copy = self
        copy.timelineIn = newTimelineIn
        return copy
    }
    
    /// Creates a copy with trimmed in-point (relative adjustment).
    public func trimmedIn(by delta: Double) -> ClipDefinition {
        var copy = self
        copy.sourceIn += delta * speed
        copy.timelineIn += delta
        return copy
    }
    
    /// Creates a copy with trimmed out-point (relative adjustment).
    public func trimmedOut(by delta: Double) -> ClipDefinition {
        var copy = self
        copy.sourceOut += delta * speed
        return copy
    }
    
    /// Splits this clip at the given timeline time.
    ///
    /// - Parameter time: Timeline time to split at.
    /// - Returns: Two new clips if split is valid, nil otherwise.
    public func split(at time: Double) -> (ClipDefinition, ClipDefinition)? {
        guard containsTimelineTime(time) && time > timelineIn && time < timelineOut else {
            return nil
        }
        
        // Calculate source time at split point
        guard let sourceAtSplit = sourceTime(at: time) else { return nil }
        
        // First part: original start to split point
        let clip1 = ClipDefinition(
            id: ClipID(),
            source: source,
            sourceIn: sourceIn,
            sourceOut: sourceAtSplit,
            timelineIn: timelineIn,
            speed: speed,
            volume: volume,
            frameBlending: frameBlending,
            name: name,
            colorLabel: colorLabel
        )
        
        // Second part: split point to original end
        let clip2 = ClipDefinition(
            id: ClipID(),
            source: source,
            sourceIn: sourceAtSplit,
            sourceOut: sourceOut,
            timelineIn: time,
            speed: speed,
            volume: volume,
            frameBlending: frameBlending,
            name: name,
            colorLabel: colorLabel
        )
        
        return (clip1, clip2)
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: ClipDefinition, rhs: ClipDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ClipContext

/// Context returned when resolving a timeline time to a clip.
///
/// This provides all the information needed to decode and render
/// the correct frame from the source.
public struct ClipContext: Sendable {
    
    /// The clip that is active at this time
    public let clip: ClipDefinition
    
    /// The source identifier
    public let source: String
    
    /// The time in the source file to decode
    public let sourceTime: Double
    
    /// The source time as CMTime
    public let sourceTimeCMTime: CMTime
    
    /// Whether this is during a transition
    public let inTransition: Bool
    
    /// Progress through the transition (0-1), nil if not in transition
    public let transitionProgress: Double?
    
    /// The transition type, nil if not in transition
    public let transitionType: VideoTransitionType?
    
    public init(
        clip: ClipDefinition,
        source: String,
        sourceTime: Double,
        fps: Double = 30,
        inTransition: Bool = false,
        transitionProgress: Double? = nil,
        transitionType: VideoTransitionType? = nil
    ) {
        self.clip = clip
        self.source = source
        self.sourceTime = sourceTime
        self.sourceTimeCMTime = CMTime(seconds: sourceTime, preferredTimescale: CMTimeScale(fps * 1000))
        self.inTransition = inTransition
        self.transitionProgress = transitionProgress
        self.transitionType = transitionType
    }
}

// MARK: - TransitionContext

/// Context for rendering a transition between two clips.
public struct TransitionContext: Sendable {
    
    /// The outgoing clip
    public let fromClip: ClipDefinition
    
    /// The incoming clip
    public let toClip: ClipDefinition
    
    /// Time in the from clip's source
    public let fromSourceTime: Double
    
    /// Time in the to clip's source
    public let toSourceTime: Double
    
    /// Progress through the transition (0.0 = full from, 1.0 = full to)
    public let progress: Double
    
    /// Type of transition
    public let type: VideoTransitionType
    
    /// Additional transition parameters
    public let parameters: TransitionParameters
    
    public init(
        fromClip: ClipDefinition,
        toClip: ClipDefinition,
        fromSourceTime: Double,
        toSourceTime: Double,
        progress: Double,
        type: VideoTransitionType,
        parameters: TransitionParameters = TransitionParameters()
    ) {
        self.fromClip = fromClip
        self.toClip = toClip
        self.fromSourceTime = fromSourceTime
        self.toSourceTime = toSourceTime
        self.progress = progress
        self.type = type
        self.parameters = parameters
    }
    
    /// From source time as CMTime
    public func fromSourceTimeCMTime(fps: Double = 30) -> CMTime {
        CMTime(seconds: fromSourceTime, preferredTimescale: CMTimeScale(fps * 1000))
    }
    
    /// To source time as CMTime
    public func toSourceTimeCMTime(fps: Double = 30) -> CMTime {
        CMTime(seconds: toSourceTime, preferredTimescale: CMTimeScale(fps * 1000))
    }
}
