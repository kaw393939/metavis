// AudioClipDefinition.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Audio clip with volume automation and transitions

import Foundation

// MARK: - AudioClipID

/// Unique identifier for an audio clip
public struct AudioClipID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    
    public init(_ value: String) {
        self.value = value
    }
    
    public init() {
        self.value = UUID().uuidString
    }
    
    public var description: String { value }
}

extension AudioClipID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}

// MARK: - AudioClipDefinition

/// Definition of an audio clip on the timeline
///
/// Audio clips map source audio files to positions on the timeline.
/// They support volume automation, fades, and speed changes.
///
/// ## Example
/// ```swift
/// let clip = AudioClipDefinition(
///     source: "background_music.mp3",
///     sourceIn: 0,
///     sourceOut: 180,
///     timelineIn: 0,
///     volume: 0.3,
///     fadeIn: 2.0,
///     fadeOut: 3.0
/// )
/// ```
public struct AudioClipDefinition: Codable, Sendable, Identifiable, Hashable {
    
    // MARK: - Properties
    
    /// Unique clip identifier
    public let id: AudioClipID
    
    /// Source audio identifier (path or ID)
    public let source: String
    
    /// Source start time in seconds
    public var sourceIn: Double
    
    /// Source end time in seconds
    public var sourceOut: Double
    
    /// Timeline start position in seconds
    public var timelineIn: Double
    
    /// Base volume (0.0 - 2.0, where 1.0 = original)
    public var volume: Float
    
    /// Volume automation keyframes (optional)
    public var volumeAutomation: VolumeAutomation?
    
    /// Fade in duration in seconds
    public var fadeIn: Double
    
    /// Fade out duration in seconds
    public var fadeOut: Double
    
    /// Playback speed multiplier (0.5 - 2.0)
    public var speed: Double
    
    /// Pan position (-1.0 = left, 0.0 = center, 1.0 = right)
    public var pan: Float
    
    /// Whether clip is enabled
    public var enabled: Bool
    
    /// Human-readable name
    public var name: String?
    
    // MARK: - Computed Properties
    
    /// Source duration in seconds
    public var sourceDuration: Double {
        sourceOut - sourceIn
    }
    
    /// Duration on timeline (accounting for speed)
    public var duration: Double {
        sourceDuration / speed
    }
    
    /// Timeline end position
    public var timelineOut: Double {
        timelineIn + duration
    }
    
    // MARK: - Initialization
    
    public init(
        id: AudioClipID = AudioClipID(),
        source: String,
        sourceIn: Double = 0,
        sourceOut: Double,
        timelineIn: Double = 0,
        volume: Float = 1.0,
        volumeAutomation: VolumeAutomation? = nil,
        fadeIn: Double = 0,
        fadeOut: Double = 0,
        speed: Double = 1.0,
        pan: Float = 0,
        enabled: Bool = true,
        name: String? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
        self.timelineIn = timelineIn
        self.volume = volume.clamped(to: 0...2)
        self.volumeAutomation = volumeAutomation
        self.fadeIn = max(0, fadeIn)
        self.fadeOut = max(0, fadeOut)
        self.speed = speed.clamped(to: 0.25...4.0)
        self.pan = pan.clamped(to: -1...1)
        self.enabled = enabled
        self.name = name
    }
    
    // MARK: - Time Calculations
    
    /// Whether this clip is active at a timeline time
    public func containsTime(_ time: Double) -> Bool {
        time >= timelineIn && time < timelineOut
    }
    
    /// Convert timeline time to source time
    public func sourceTime(at timelineTime: Double) -> Double {
        guard containsTime(timelineTime) else { return sourceIn }
        
        let clipOffset = timelineTime - timelineIn
        let sourceOffset = clipOffset * speed
        return sourceIn + sourceOffset
    }
    
    /// Get effective volume at a timeline time (including automation and fades)
    public func effectiveVolume(at timelineTime: Double) -> Float {
        guard containsTime(timelineTime) && enabled else { return 0 }
        
        var effectiveVol = volume
        
        // Apply automation
        if let automation = volumeAutomation {
            let clipTime = timelineTime - timelineIn
            effectiveVol *= automation.value(at: clipTime)
        }
        
        // Apply fades
        let fadeMultiplier = fadeMultiplier(at: timelineTime)
        effectiveVol *= fadeMultiplier
        
        return effectiveVol
    }
    
    /// Get fade multiplier at a timeline time
    public func fadeMultiplier(at timelineTime: Double) -> Float {
        let clipTime = timelineTime - timelineIn
        
        // Fade in
        if clipTime < fadeIn && fadeIn > 0 {
            return Float(clipTime / fadeIn)
        }
        
        // Fade out
        let timeToEnd = duration - clipTime
        if timeToEnd < fadeOut && fadeOut > 0 {
            return Float(timeToEnd / fadeOut)
        }
        
        return 1.0
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: AudioClipDefinition, rhs: AudioClipDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Convenience Initializers

extension AudioClipDefinition {
    /// Create a clip from full source duration
    public static func fullSource(
        source: String,
        duration: Double,
        at timelineIn: Double = 0,
        volume: Float = 1.0,
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) -> AudioClipDefinition {
        AudioClipDefinition(
            source: source,
            sourceIn: 0,
            sourceOut: duration,
            timelineIn: timelineIn,
            volume: volume,
            fadeIn: fadeIn,
            fadeOut: fadeOut
        )
    }
    
    /// Create a music clip with typical settings
    public static func music(
        source: String,
        duration: Double,
        at timelineIn: Double = 0,
        volume: Float = 0.3,
        fadeIn: Double = 2.0,
        fadeOut: Double = 3.0
    ) -> AudioClipDefinition {
        AudioClipDefinition(
            source: source,
            sourceIn: 0,
            sourceOut: duration,
            timelineIn: timelineIn,
            volume: volume,
            fadeIn: fadeIn,
            fadeOut: fadeOut,
            name: "Music"
        )
    }
}


