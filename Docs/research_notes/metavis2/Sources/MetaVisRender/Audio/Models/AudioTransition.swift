// AudioTransition.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Audio-specific transitions (crossfade, J-cut, L-cut)

import Foundation

// MARK: - AudioTransitionType

/// Type of audio transition between clips
public enum AudioTransitionType: String, Codable, Sendable, CaseIterable {
    /// Hard cut - instant switch
    case cut
    
    /// Crossfade - outgoing fades out while incoming fades in
    case crossfade
    
    /// J-cut - audio from next clip starts before video cuts
    case jCut
    
    /// L-cut - audio from previous clip continues after video cuts
    case lCut
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .cut: return "Hard Cut"
        case .crossfade: return "Crossfade"
        case .jCut: return "J-Cut"
        case .lCut: return "L-Cut"
        }
    }
    
    /// Whether this transition requires overlap
    public var requiresOverlap: Bool {
        self != .cut
    }
    
    /// Default duration for this transition type
    public var defaultDuration: Double {
        switch self {
        case .cut: return 0
        case .crossfade: return 0.5
        case .jCut, .lCut: return 1.0
        }
    }
}

// MARK: - AudioTransition

/// Audio transition between two clips
public struct AudioTransition: Codable, Sendable, Identifiable, Hashable {
    
    // MARK: - Properties
    
    /// Unique identifier
    public let id: String
    
    /// ID of outgoing clip
    public let fromClip: AudioClipID
    
    /// ID of incoming clip
    public let toClip: AudioClipID
    
    /// Transition type
    public var type: AudioTransitionType
    
    /// Duration of transition in seconds
    public var duration: Double
    
    /// Lead/tail time for J-cut/L-cut
    public var offsetTime: Double
    
    /// Easing curve for the transition
    public var curve: InterpolationCurve
    
    // MARK: - Initialization
    
    public init(
        id: String = UUID().uuidString,
        fromClip: AudioClipID,
        toClip: AudioClipID,
        type: AudioTransitionType,
        duration: Double? = nil,
        offsetTime: Double = 0,
        curve: InterpolationCurve = .linear
    ) {
        self.id = id
        self.fromClip = fromClip
        self.toClip = toClip
        self.type = type
        self.duration = duration ?? type.defaultDuration
        self.offsetTime = offsetTime
        self.curve = curve
    }
    
    // MARK: - Gain Calculation
    
    /// Calculate gain for outgoing clip at progress
    public func fromGain(at progress: Double) -> Float {
        let p = progress.clamped(to: 0...1)
        
        switch type {
        case .cut:
            return p < 0.5 ? 1.0 : 0.0
            
        case .crossfade:
            return Float(1.0 - curve.apply(p))
            
        case .jCut:
            // Audio from "from" continues, then fades
            if p < 0.5 {
                return 1.0
            } else {
                let fadeProgress = (p - 0.5) * 2
                return Float(1.0 - curve.apply(fadeProgress))
            }
            
        case .lCut:
            // Audio from "from" fades while continuing under "to"
            return Float(1.0 - curve.apply(p))
        }
    }
    
    /// Calculate gain for incoming clip at progress
    public func toGain(at progress: Double) -> Float {
        let p = progress.clamped(to: 0...1)
        
        switch type {
        case .cut:
            return p >= 0.5 ? 1.0 : 0.0
            
        case .crossfade:
            return Float(curve.apply(p))
            
        case .jCut:
            // Audio from "to" starts early, fades in
            if p < 0.5 {
                let fadeProgress = p * 2
                return Float(curve.apply(fadeProgress))
            } else {
                return 1.0
            }
            
        case .lCut:
            // Audio from "to" comes in later
            if p < 0.5 {
                return 0
            } else {
                let fadeProgress = (p - 0.5) * 2
                return Float(curve.apply(fadeProgress))
            }
        }
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: AudioTransition, rhs: AudioTransition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Transition Context

/// Context for rendering an audio transition
public struct AudioTransitionContext: Sendable {
    /// The transition definition
    public let transition: AudioTransition
    
    /// Progress through the transition (0.0 - 1.0)
    public let progress: Double
    
    /// Timeline time
    public let time: Double
    
    /// Calculated gain for outgoing audio
    public var fromGain: Float {
        transition.fromGain(at: progress)
    }
    
    /// Calculated gain for incoming audio
    public var toGain: Float {
        transition.toGain(at: progress)
    }
    
    public init(
        transition: AudioTransition,
        progress: Double,
        time: Double
    ) {
        self.transition = transition
        self.progress = progress
        self.time = time
    }
}

// MARK: - Presets

extension AudioTransition {
    /// Quick crossfade
    public static func quickCrossfade(
        from: AudioClipID,
        to: AudioClipID
    ) -> AudioTransition {
        AudioTransition(
            fromClip: from,
            toClip: to,
            type: .crossfade,
            duration: 0.25,
            curve: .easeInOut
        )
    }
    
    /// Standard crossfade
    public static func crossfade(
        from: AudioClipID,
        to: AudioClipID,
        duration: Double = 0.5
    ) -> AudioTransition {
        AudioTransition(
            fromClip: from,
            toClip: to,
            type: .crossfade,
            duration: duration,
            curve: .easeInOut
        )
    }
    
    /// J-cut with audio lead
    public static func jCut(
        from: AudioClipID,
        to: AudioClipID,
        leadTime: Double = 1.0
    ) -> AudioTransition {
        AudioTransition(
            fromClip: from,
            toClip: to,
            type: .jCut,
            duration: leadTime * 2,  // Total transition is 2x lead time
            offsetTime: leadTime,
            curve: .easeOut
        )
    }
    
    /// L-cut with audio tail
    public static func lCut(
        from: AudioClipID,
        to: AudioClipID,
        tailTime: Double = 1.0
    ) -> AudioTransition {
        AudioTransition(
            fromClip: from,
            toClip: to,
            type: .lCut,
            duration: tailTime * 2,
            offsetTime: tailTime,
            curve: .easeIn
        )
    }
}
