// AudioResolver.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Maps timeline time to audio clip positions

import Foundation

// MARK: - ResolvedAudio

/// Resolved audio clip at a specific timeline time
public struct ResolvedAudio: Sendable {
    /// The clip definition
    public let clip: AudioClipDefinition
    
    /// Track containing this clip
    public let trackID: AudioTrackID
    
    /// Source time to read from
    public let sourceTime: Double
    
    /// Effective volume at this time (includes automation, fades)
    public let volume: Float
    
    /// Pan position (-1 to 1)
    public let pan: Float
    
    /// Whether this clip is in a transition
    public let inTransition: Bool
    
    /// Transition context if in transition
    public let transitionContext: AudioTransitionContext?
    
    public init(
        clip: AudioClipDefinition,
        trackID: AudioTrackID,
        sourceTime: Double,
        volume: Float,
        pan: Float,
        inTransition: Bool = false,
        transitionContext: AudioTransitionContext? = nil
    ) {
        self.clip = clip
        self.trackID = trackID
        self.sourceTime = sourceTime
        self.volume = volume
        self.pan = pan
        self.inTransition = inTransition
        self.transitionContext = transitionContext
    }
}

// MARK: - AudioResolver

/// Resolves timeline time to active audio clips
///
/// Maps timeline positions to source audio with volume/pan evaluation.
///
/// ## Example
/// ```swift
/// let resolver = AudioResolver(tracks: [dialogueTrack, musicTrack])
/// let resolved = resolver.resolve(time: 45.5)
/// for audio in resolved {
///     print("\(audio.clip.source) at \(audio.sourceTime) vol \(audio.volume)")
/// }
/// ```
public struct AudioResolver: Sendable {
    
    // MARK: - Properties
    
    /// Audio tracks to resolve
    private let tracks: [AudioTrack]
    
    /// Transitions between clips
    private let transitions: [AudioTransition]
    
    /// Track volume overrides (from mixer)
    private var trackVolumes: [AudioTrackID: Float]
    
    /// Soloed tracks (if any soloed, only play those)
    private var soloedTracks: Set<AudioTrackID>
    
    /// Muted tracks
    private var mutedTracks: Set<AudioTrackID>
    
    // MARK: - Initialization
    
    public init(
        tracks: [AudioTrack] = [],
        transitions: [AudioTransition] = []
    ) {
        self.tracks = tracks
        self.transitions = transitions
        self.trackVolumes = [:]
        self.soloedTracks = Set(tracks.filter { $0.solo }.map { $0.id })
        self.mutedTracks = Set(tracks.filter { $0.muted }.map { $0.id })
    }
    
    // MARK: - Resolution
    
    /// Resolve all active audio at timeline time
    public func resolve(time: Double) -> [ResolvedAudio] {
        var results: [ResolvedAudio] = []
        
        for track in tracks {
            // Skip muted tracks
            if mutedTracks.contains(track.id) { continue }
            
            // If any tracks are soloed, only play soloed tracks
            if !soloedTracks.isEmpty && !soloedTracks.contains(track.id) { continue }
            
            // Resolve clips on this track
            let trackResults = resolve(time: time, track: track)
            results.append(contentsOf: trackResults)
        }
        
        return results
    }
    
    /// Resolve audio for a specific track
    public func resolve(time: Double, track: AudioTrack) -> [ResolvedAudio] {
        var results: [ResolvedAudio] = []
        
        let activeClips = track.clips(at: time)
        
        for clip in activeClips {
            guard clip.enabled else { continue }
            
            let sourceTime = clip.sourceTime(at: time)
            
            // Calculate effective volume
            var volume = clip.effectiveVolume(at: time)
            
            // Apply track volume
            let trackVol = trackVolumes[track.id] ?? track.volume
            volume *= trackVol
            
            // Check for transitions
            let transitionCtx = findTransition(for: clip.id, at: time)
            
            // If in transition, apply transition gain
            if let ctx = transitionCtx {
                if ctx.transition.fromClip == clip.id {
                    volume *= ctx.fromGain
                } else if ctx.transition.toClip == clip.id {
                    volume *= ctx.toGain
                }
            }
            
            // Apply pan (combine clip and track pan)
            let pan = (clip.pan + track.pan).clamped(to: -1...1)
            
            results.append(ResolvedAudio(
                clip: clip,
                trackID: track.id,
                sourceTime: sourceTime,
                volume: volume,
                pan: pan,
                inTransition: transitionCtx != nil,
                transitionContext: transitionCtx
            ))
        }
        
        return results
    }
    
    /// Resolve audio for a specific track by ID
    public func resolve(time: Double, trackID: AudioTrackID) -> [ResolvedAudio] {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return []
        }
        return resolve(time: time, track: track)
    }
    
    // MARK: - Transition Lookup
    
    /// Find transition involving a clip at a time
    private func findTransition(for clipID: AudioClipID, at time: Double) -> AudioTransitionContext? {
        for transition in transitions {
            guard transition.fromClip == clipID || transition.toClip == clipID else { continue }
            
            // Find the clips to determine transition timing
            let fromClip = findClip(id: transition.fromClip)
            let toClip = findClip(id: transition.toClip)
            
            guard let from = fromClip, let to = toClip else { continue }
            
            // Calculate transition region
            let transitionStart: Double
            let transitionEnd: Double
            
            switch transition.type {
            case .cut:
                continue  // No transition region for cuts
                
            case .crossfade:
                // Crossfade during overlap
                transitionStart = to.timelineIn
                transitionEnd = min(from.timelineOut, transitionStart + transition.duration)
                
            case .jCut:
                // Audio leads video by offsetTime
                transitionStart = to.timelineIn - transition.offsetTime
                transitionEnd = to.timelineIn + transition.offsetTime
                
            case .lCut:
                // Audio trails video by offsetTime
                transitionStart = from.timelineOut - transition.offsetTime
                transitionEnd = from.timelineOut + transition.offsetTime
            }
            
            // Check if time is in transition region
            if time >= transitionStart && time < transitionEnd {
                let progress = (time - transitionStart) / (transitionEnd - transitionStart)
                return AudioTransitionContext(
                    transition: transition,
                    progress: progress,
                    time: time
                )
            }
        }
        
        return nil
    }
    
    /// Find a clip by ID across all tracks
    private func findClip(id: AudioClipID) -> AudioClipDefinition? {
        for track in tracks {
            if let clip = track.clip(id: id) {
                return clip
            }
        }
        return nil
    }
    
    // MARK: - Source Information
    
    /// Get all source IDs needed for a time range
    public func sourcesNeeded(from startTime: Double, to endTime: Double) -> Set<String> {
        var sources = Set<String>()
        
        for track in tracks {
            for clip in track.clips {
                if clip.timelineOut > startTime && clip.timelineIn < endTime {
                    sources.insert(clip.source)
                }
            }
        }
        
        return sources
    }
    
    /// Get all unique sources in the timeline
    public func allSources() -> Set<String> {
        var sources = Set<String>()
        for track in tracks {
            for clip in track.clips {
                sources.insert(clip.source)
            }
        }
        return sources
    }
    
    // MARK: - Track Queries
    
    /// Get dialogue/voiceover tracks (for ducking)
    public func dialogueTracks() -> [AudioTrack] {
        tracks.filter { $0.type.triggersDucking }
    }
    
    /// Get music tracks (ducking targets)
    public func musicTracks() -> [AudioTrack] {
        tracks.filter { $0.type.isDuckingTarget }
    }
    
    /// Total timeline duration
    public var duration: Double {
        tracks.map { $0.duration }.max() ?? 0
    }
}

// MARK: - Builder

extension AudioResolver {
    /// Create resolver with mutable configuration
    public func with(trackVolume: Float, for trackID: AudioTrackID) -> AudioResolver {
        var new = self
        new.trackVolumes[trackID] = trackVolume
        return new
    }
    
    public func with(muted trackID: AudioTrackID) -> AudioResolver {
        var new = self
        new.mutedTracks.insert(trackID)
        return new
    }
    
    public func with(soloed trackID: AudioTrackID) -> AudioResolver {
        var new = self
        new.soloedTracks.insert(trackID)
        return new
    }
}
