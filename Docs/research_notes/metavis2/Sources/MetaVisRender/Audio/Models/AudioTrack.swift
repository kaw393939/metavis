// AudioTrack.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Audio track model for multi-track timeline editing

import Foundation
import AVFoundation

// MARK: - AudioTrackID

/// Unique identifier for an audio track
public struct AudioTrackID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    
    public init(_ value: String) {
        self.value = value
    }
    
    public var description: String { value }
}

extension AudioTrackID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}

// MARK: - AudioTrackType

/// Type of audio track determining behavior
public enum AudioTrackType: String, Codable, Sendable, CaseIterable {
    /// Linked to a video track (source audio)
    case linked
    
    /// Dialogue or interview audio
    case dialogue
    
    /// Background music
    case music
    
    /// Voiceover narration
    case voiceover
    
    /// Sound effects
    case sfx
    
    /// General audio (no special behavior)
    case audio
    
    /// Is this track a trigger for ducking?
    public var triggersDucking: Bool {
        switch self {
        case .dialogue, .voiceover:
            return true
        default:
            return false
        }
    }
    
    /// Is this track a target for ducking?
    public var isDuckingTarget: Bool {
        self == .music
    }
    
    /// Default volume for this track type
    public var defaultVolume: Float {
        switch self {
        case .dialogue, .voiceover: return 1.0
        case .music: return 0.3
        case .sfx: return 0.8
        case .linked, .audio: return 1.0
        }
    }
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .linked: return "Linked Audio"
        case .dialogue: return "Dialogue"
        case .music: return "Music"
        case .voiceover: return "Voiceover"
        case .sfx: return "Sound Effects"
        case .audio: return "Audio"
        }
    }
}

// MARK: - AudioTrack

/// An audio track in the timeline
///
/// Audio tracks contain clips and have their own volume/pan settings.
/// They can be linked to video tracks or independent.
///
/// ## Example
/// ```swift
/// let musicTrack = AudioTrack(
///     id: AudioTrackID("music"),
///     name: "Background Music",
///     type: .music,
///     volume: 0.3
/// )
/// ```
public struct AudioTrack: Codable, Sendable, Identifiable, Hashable {
    
    // MARK: - Properties
    
    /// Unique track identifier
    public let id: AudioTrackID
    
    /// Human-readable track name
    public var name: String
    
    /// Track type (dialogue, music, etc.)
    public let type: AudioTrackType
    
    /// If linked, the video track this follows
    public var linkedVideoTrack: String?
    
    /// Clips on this track
    public var clips: [AudioClipDefinition]
    
    /// Track volume (0.0 - 1.0)
    public var volume: Float
    
    /// Track pan (-1.0 = left, 0.0 = center, 1.0 = right)
    public var pan: Float
    
    /// Whether track is muted
    public var muted: Bool
    
    /// Whether track is soloed
    public var solo: Bool
    
    /// Track color for UI (hex string)
    public var color: String?
    
    // MARK: - Initialization
    
    public init(
        id: AudioTrackID,
        name: String? = nil,
        type: AudioTrackType = .audio,
        linkedVideoTrack: String? = nil,
        clips: [AudioClipDefinition] = [],
        volume: Float = 1.0,
        pan: Float = 0.0,
        muted: Bool = false,
        solo: Bool = false,
        color: String? = nil
    ) {
        self.id = id
        self.name = name ?? type.displayName
        self.type = type
        self.linkedVideoTrack = linkedVideoTrack
        self.clips = clips
        self.volume = volume.clamped(to: 0...2)  // Allow boost up to 2x
        self.pan = pan.clamped(to: -1...1)
        self.muted = muted
        self.solo = solo
        self.color = color
    }
    
    // MARK: - Clip Management
    
    /// Get clips active at a specific time
    public func clips(at time: Double) -> [AudioClipDefinition] {
        clips.filter { $0.containsTime(time) }
    }
    
    /// Get clip by ID
    public func clip(id: AudioClipID) -> AudioClipDefinition? {
        clips.first { $0.id == id }
    }
    
    /// Add a clip to the track
    public mutating func addClip(_ clip: AudioClipDefinition) {
        clips.append(clip)
        sortClips()
    }
    
    /// Remove a clip from the track
    public mutating func removeClip(id: AudioClipID) {
        clips.removeAll { $0.id == id }
    }
    
    /// Sort clips by timeline position
    private mutating func sortClips() {
        clips.sort { $0.timelineIn < $1.timelineIn }
    }
    
    // MARK: - Duration
    
    /// Total duration covered by clips on this track
    public var duration: Double {
        guard let lastClip = clips.max(by: { $0.timelineOut < $1.timelineOut }) else {
            return 0
        }
        return lastClip.timelineOut
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Linked Track Creation

extension AudioTrack {
    /// Create a linked audio track for a video track
    public static func linked(
        to videoTrackID: String,
        id: AudioTrackID? = nil
    ) -> AudioTrack {
        AudioTrack(
            id: id ?? AudioTrackID("linked_\(videoTrackID)"),
            name: "Audio (\(videoTrackID))",
            type: .linked,
            linkedVideoTrack: videoTrackID
        )
    }
    
    /// Create a music track with typical settings
    public static func music(
        id: AudioTrackID = "music",
        name: String = "Music",
        volume: Float = 0.3
    ) -> AudioTrack {
        AudioTrack(
            id: id,
            name: name,
            type: .music,
            volume: volume,
            color: "#8B5CF6"  // Purple
        )
    }
    
    /// Create a voiceover track
    public static func voiceover(
        id: AudioTrackID = "voiceover",
        name: String = "Voiceover"
    ) -> AudioTrack {
        AudioTrack(
            id: id,
            name: name,
            type: .voiceover,
            color: "#10B981"  // Green
        )
    }
    
    /// Create a sound effects track
    public static func sfx(
        id: AudioTrackID = "sfx",
        name: String = "Sound Effects",
        volume: Float = 0.8
    ) -> AudioTrack {
        AudioTrack(
            id: id,
            name: name,
            type: .sfx,
            volume: volume,
            color: "#F59E0B"  // Amber
        )
    }
}


