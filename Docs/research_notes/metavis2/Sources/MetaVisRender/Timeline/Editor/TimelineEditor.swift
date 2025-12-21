// TimelineEditor.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Actor for timeline editing operations with undo/redo support

import Foundation

// MARK: - TimelineError

/// Errors that can occur during timeline editing operations.
public enum TimelineError: Error, Sendable {
    case clipNotFound(ClipID)
    case trackNotFound(TrackID)
    case sourceNotFound(String)
    case invalidTrim
    case invalidSplitPoint
    case invalidMovePosition
    case overlappingClips
    case trackLocked
    case noUndoAvailable
    case noRedoAvailable
    case transitionNotFound
    case invalidTransition(String)
}

extension TimelineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .clipNotFound(let id):
            return "Clip not found: \(id)"
        case .trackNotFound(let id):
            return "Track not found: \(id)"
        case .sourceNotFound(let source):
            return "Source not found: \(source)"
        case .invalidTrim:
            return "Invalid trim operation (would result in zero or negative duration)"
        case .invalidSplitPoint:
            return "Split point is outside clip bounds"
        case .invalidMovePosition:
            return "Invalid move position"
        case .overlappingClips:
            return "Operation would cause clips to overlap"
        case .trackLocked:
            return "Track is locked"
        case .noUndoAvailable:
            return "No undo history available"
        case .noRedoAvailable:
            return "No redo history available"
        case .transitionNotFound:
            return "Transition not found"
        case .invalidTransition(let reason):
            return "Invalid transition: \(reason)"
        }
    }
}

// MARK: - TrimMode

/// How trim operations affect adjacent clips.
public enum TrimMode: Sendable {
    /// Normal trim: only affects the selected clip
    case normal
    
    /// Ripple trim: moves all subsequent clips to fill/create gap
    case ripple
    
    /// Roll trim: adjusts adjacent clip to maintain timeline length
    case roll
}

// MARK: - TimelineEditor

/// Actor for performing editing operations on a timeline.
///
/// Provides undo/redo support and validates all operations before applying.
///
/// ## Example
/// ```swift
/// let editor = TimelineEditor(timeline: myTimeline)
///
/// // Add a clip
/// let clipID = try await editor.addClip(
///     source: "interview",
///     sourceIn: 10.0,
///     sourceOut: 45.0,
///     at: 0.0,
///     on: primaryTrack
/// )
///
/// // Undo
/// try await editor.undo()
/// ```
public actor TimelineEditor {
    
    // MARK: - Properties
    
    /// The timeline being edited
    public private(set) var timeline: TimelineModel
    
    /// Undo history (previous states)
    private var undoStack: [TimelineModel] = []
    
    /// Redo history (undone states)
    private var redoStack: [TimelineModel] = []
    
    /// Maximum undo history size
    private let maxUndoLevels: Int
    
    /// Whether to automatically validate after each operation
    private let autoValidate: Bool
    
    // MARK: - Initialization
    
    /// Creates a new timeline editor.
    public init(
        timeline: TimelineModel,
        maxUndoLevels: Int = 50,
        autoValidate: Bool = true
    ) {
        self.timeline = timeline
        self.maxUndoLevels = maxUndoLevels
        self.autoValidate = autoValidate
    }
    
    // MARK: - Undo/Redo
    
    /// Saves the current state to undo history.
    private func saveUndo() {
        undoStack.append(timeline)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }
    
    /// Undoes the last operation.
    public func undo() throws {
        guard let previousState = undoStack.popLast() else {
            throw TimelineError.noUndoAvailable
        }
        redoStack.append(timeline)
        timeline = previousState
    }
    
    /// Redoes the last undone operation.
    public func redo() throws {
        guard let nextState = redoStack.popLast() else {
            throw TimelineError.noRedoAvailable
        }
        undoStack.append(timeline)
        timeline = nextState
    }
    
    /// Returns whether undo is available.
    public var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    /// Returns whether redo is available.
    public var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    /// Clears all undo/redo history.
    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    // MARK: - Source Management
    
    /// Registers a source file.
    public func registerSource(id: String, path: String, duration: Double? = nil) {
        timeline.registerSource(id: id, path: path, duration: duration)
    }
    
    // MARK: - Track Operations
    
    /// Adds a new video track.
    @discardableResult
    public func addVideoTrack(name: String? = nil) -> TrackID {
        saveUndo()
        return timeline.addVideoTrack(name: name)
    }
    
    /// Removes a video track.
    public func removeVideoTrack(id: TrackID) throws {
        guard let index = timeline.videoTracks.firstIndex(where: { $0.id == id }) else {
            throw TimelineError.trackNotFound(id)
        }
        saveUndo()
        timeline.videoTracks.remove(at: index)
    }
    
    // MARK: - Clip Operations
    
    /// Adds a clip to a track.
    ///
    /// - Parameters:
    ///   - source: Source ID (must be registered)
    ///   - sourceIn: Start time in source
    ///   - sourceOut: End time in source
    ///   - at: Position on timeline (nil = append to end)
    ///   - on: Track ID (nil = primary video track)
    ///   - speed: Playback speed
    /// - Returns: The ID of the new clip
    @discardableResult
    public func addClip(
        source: String,
        sourceIn: Double,
        sourceOut: Double,
        at position: Double? = nil,
        on trackID: TrackID? = nil,
        speed: Double = 1.0
    ) throws -> ClipID {
        // Resolve track
        let targetTrackID = trackID ?? timeline.videoTracks.first?.id
        guard let trackIndex = timeline.videoTracks.firstIndex(where: { $0.id == targetTrackID }) else {
            throw TimelineError.trackNotFound(targetTrackID ?? TrackID("unknown"))
        }
        
        // Check if track is locked
        guard !timeline.videoTracks[trackIndex].isLocked else {
            throw TimelineError.trackLocked
        }
        
        // Verify source exists
        guard timeline.sources[source] != nil else {
            throw TimelineError.sourceNotFound(source)
        }
        
        // Calculate position
        let timelineIn = position ?? timeline.videoTracks[trackIndex].duration
        
        // Create clip
        let clip = ClipDefinition(
            source: source,
            sourceIn: sourceIn,
            sourceOut: sourceOut,
            timelineIn: timelineIn,
            speed: speed
        )
        
        saveUndo()
        
        // Add clip and sort by position
        timeline.videoTracks[trackIndex].clips.append(clip)
        timeline.videoTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
        
        return clip.id
    }
    
    /// Removes a clip from the timeline.
    public func removeClip(id: ClipID) throws {
        for trackIndex in timeline.videoTracks.indices {
            if let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                guard !timeline.videoTracks[trackIndex].isLocked else {
                    throw TimelineError.trackLocked
                }
                
                saveUndo()
                
                // Remove any transitions involving this clip
                timeline.transitions.removeAll { $0.fromClip == id || $0.toClip == id }
                
                // Remove the clip
                timeline.videoTracks[trackIndex].clips.remove(at: clipIndex)
                return
            }
        }
        throw TimelineError.clipNotFound(id)
    }
    
    /// Moves a clip to a new position on the timeline.
    public func moveClip(id: ClipID, to newPosition: Double) throws {
        guard newPosition >= 0 else {
            throw TimelineError.invalidMovePosition
        }
        
        for trackIndex in timeline.videoTracks.indices {
            if let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                guard !timeline.videoTracks[trackIndex].isLocked else {
                    throw TimelineError.trackLocked
                }
                
                saveUndo()
                timeline.videoTracks[trackIndex].clips[clipIndex].timelineIn = newPosition
                timeline.videoTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
                return
            }
        }
        throw TimelineError.clipNotFound(id)
    }
    
    /// Trims a clip's in/out points.
    ///
    /// - Parameters:
    ///   - id: Clip ID
    ///   - inDelta: Change to in point (positive = move in later, negative = move in earlier)
    ///   - outDelta: Change to out point (positive = extend, negative = shorten)
    ///   - mode: Trim mode (normal, ripple, roll)
    public func trimClip(
        id: ClipID,
        inDelta: Double = 0,
        outDelta: Double = 0,
        mode: TrimMode = .normal
    ) throws {
        for trackIndex in timeline.videoTracks.indices {
            if let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                guard !timeline.videoTracks[trackIndex].isLocked else {
                    throw TimelineError.trackLocked
                }
                
                var clip = timeline.videoTracks[trackIndex].clips[clipIndex]
                
                // Apply in-point change
                if inDelta != 0 {
                    clip.sourceIn += inDelta * clip.speed
                    clip.timelineIn += inDelta
                }
                
                // Apply out-point change
                if outDelta != 0 {
                    clip.sourceOut += outDelta * clip.speed
                }
                
                // Validate result
                guard clip.duration > 0 else {
                    throw TimelineError.invalidTrim
                }
                
                saveUndo()
                timeline.videoTracks[trackIndex].clips[clipIndex] = clip
                
                // Handle ripple mode
                if mode == .ripple {
                    let delta = -inDelta + outDelta
                    rippleFrom(trackIndex: trackIndex, clipIndex: clipIndex + 1, by: delta)
                }
                
                return
            }
        }
        throw TimelineError.clipNotFound(id)
    }
    
    /// Splits a clip at the given timeline time.
    ///
    /// - Parameters:
    ///   - id: Clip ID to split
    ///   - at: Timeline time to split at
    /// - Returns: Tuple of the two new clip IDs
    public func splitClip(id: ClipID, at time: Double) throws -> (ClipID, ClipID) {
        for trackIndex in timeline.videoTracks.indices {
            if let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                guard !timeline.videoTracks[trackIndex].isLocked else {
                    throw TimelineError.trackLocked
                }
                
                let clip = timeline.videoTracks[trackIndex].clips[clipIndex]
                
                guard let (clip1, clip2) = clip.split(at: time) else {
                    throw TimelineError.invalidSplitPoint
                }
                
                saveUndo()
                
                // Remove original and insert new clips
                timeline.videoTracks[trackIndex].clips.remove(at: clipIndex)
                timeline.videoTracks[trackIndex].clips.insert(clip2, at: clipIndex)
                timeline.videoTracks[trackIndex].clips.insert(clip1, at: clipIndex)
                
                return (clip1.id, clip2.id)
            }
        }
        throw TimelineError.clipNotFound(id)
    }
    
    /// Duplicates a clip.
    ///
    /// - Parameters:
    ///   - id: Clip ID to duplicate
    ///   - at: Position for the duplicate (nil = immediately after original)
    /// - Returns: The ID of the new clip
    @discardableResult
    public func duplicateClip(id: ClipID, at position: Double? = nil) throws -> ClipID {
        for trackIndex in timeline.videoTracks.indices {
            if let clipIndex = timeline.videoTracks[trackIndex].clips.firstIndex(where: { $0.id == id }) {
                guard !timeline.videoTracks[trackIndex].isLocked else {
                    throw TimelineError.trackLocked
                }
                
                let original = timeline.videoTracks[trackIndex].clips[clipIndex]
                var duplicate = original.duplicate()
                duplicate.timelineIn = position ?? (original.timelineIn + original.duration)
                
                saveUndo()
                timeline.videoTracks[trackIndex].clips.append(duplicate)
                timeline.videoTracks[trackIndex].clips.sort { $0.timelineIn < $1.timelineIn }
                
                return duplicate.id
            }
        }
        throw TimelineError.clipNotFound(id)
    }
    
    // MARK: - Transition Operations
    
    /// Adds a transition between two clips.
    ///
    /// The clips must be adjacent (to clip starts before from clip ends).
    @discardableResult
    public func addTransition(
        from fromClip: ClipID,
        to toClip: ClipID,
        type: VideoTransitionType,
        duration: Double? = nil
    ) throws -> TransitionDefinition {
        // Verify clips exist
        guard let from = timeline.clip(id: fromClip) else {
            throw TimelineError.clipNotFound(fromClip)
        }
        guard let to = timeline.clip(id: toClip) else {
            throw TimelineError.clipNotFound(toClip)
        }
        
        // Verify clips overlap (for transition)
        let transitionDuration = duration ?? type.defaultDuration
        guard to.timelineIn < from.timelineOut else {
            throw TimelineError.invalidTransition("Clips do not overlap for transition")
        }
        
        // Check that overlap is sufficient for transition
        let overlap = from.timelineOut - to.timelineIn
        guard overlap >= transitionDuration else {
            throw TimelineError.invalidTransition("Clip overlap (\(overlap)s) is less than transition duration (\(transitionDuration)s)")
        }
        
        let transition = TransitionDefinition(
            fromClip: fromClip,
            toClip: toClip,
            type: type,
            duration: transitionDuration
        )
        
        saveUndo()
        
        // Remove any existing transition between these clips
        timeline.transitions.removeAll { $0.fromClip == fromClip && $0.toClip == toClip }
        
        // Add the new transition
        timeline.transitions.append(transition)
        
        return transition
    }
    
    /// Removes a transition between two clips.
    public func removeTransition(from fromClip: ClipID, to toClip: ClipID) throws {
        guard timeline.transitions.contains(where: { $0.fromClip == fromClip && $0.toClip == toClip }) else {
            throw TimelineError.transitionNotFound
        }
        
        saveUndo()
        timeline.transitions.removeAll { $0.fromClip == fromClip && $0.toClip == toClip }
    }
    
    /// Updates a transition's properties.
    public func updateTransition(
        from fromClip: ClipID,
        to toClip: ClipID,
        type: VideoTransitionType? = nil,
        duration: Double? = nil
    ) throws {
        guard let index = timeline.transitions.firstIndex(where: { $0.fromClip == fromClip && $0.toClip == toClip }) else {
            throw TimelineError.transitionNotFound
        }
        
        saveUndo()
        
        if let type = type {
            timeline.transitions[index].type = type
        }
        if let duration = duration {
            timeline.transitions[index].duration = duration
        }
    }
    
    // MARK: - Marker Operations
    
    /// Adds a marker to the timeline.
    public func addMarker(at time: Double, label: String, type: TimelineMarker.MarkerType = .comment) {
        saveUndo()
        timeline.markers.append(TimelineMarker(time: time, label: label, type: type))
        timeline.markers.sort { $0.time < $1.time }
    }
    
    /// Removes markers at the given time.
    public func removeMarkers(at time: Double, tolerance: Double = 0.1) {
        saveUndo()
        timeline.markers.removeAll { abs($0.time - time) < tolerance }
    }
    
    // MARK: - Helper Methods
    
    /// Ripples clips after the given index by the specified amount.
    private func rippleFrom(trackIndex: Int, clipIndex: Int, by delta: Double) {
        for i in clipIndex..<timeline.videoTracks[trackIndex].clips.count {
            timeline.videoTracks[trackIndex].clips[i].timelineIn += delta
        }
    }
    
    /// Validates the timeline and returns any errors.
    public func validate() -> [TimelineValidationError] {
        timeline.validate()
    }
    
    /// Replaces the entire timeline (for advanced operations).
    public func replaceTimeline(_ newTimeline: TimelineModel) {
        saveUndo()
        timeline = newTimeline
    }
}

// MARK: - Convenience Extensions

extension TimelineEditor {
    /// Gets all clips on the primary video track.
    public var primaryTrackClips: [ClipDefinition] {
        timeline.primaryVideoTrack?.clips ?? []
    }
    
    /// Gets the total timeline duration.
    public var duration: Double {
        timeline.duration
    }
    
    /// Gets a clip by ID.
    public func clip(id: ClipID) -> ClipDefinition? {
        timeline.clip(id: id)
    }
}
