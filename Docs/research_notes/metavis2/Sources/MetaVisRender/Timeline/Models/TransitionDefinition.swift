// TransitionDefinition.swift
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// Transition types and definitions between clips

import Foundation

// MARK: - VideoTransitionType

/// Types of video transitions between clips.
/// Named VideoTransitionType to distinguish from SceneDetector's TransitionType.
public enum VideoTransitionType: String, Codable, Sendable, CaseIterable {
    /// Hard cut (no transition effect)
    case cut
    
    /// Cross dissolve between clips
    case crossfade
    
    /// Fade to black, then fade in
    case dipToBlack
    
    /// Fade to white, then fade in
    case dipToWhite
    
    /// Horizontal wipe from left to right
    case wipeLeft
    
    /// Horizontal wipe from right to left
    case wipeRight
    
    /// Vertical wipe from bottom to top
    case wipeUp
    
    /// Vertical wipe from top to bottom
    case wipeDown
    
    /// Push the outgoing clip off screen
    case push
    
    /// Slide the incoming clip over the outgoing
    case slide
    
    /// Radial wipe (iris)
    case iris
    
    /// Custom shader transition
    case custom
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .cut: return "Cut"
        case .crossfade: return "Cross Dissolve"
        case .dipToBlack: return "Dip to Black"
        case .dipToWhite: return "Dip to White"
        case .wipeLeft: return "Wipe Left"
        case .wipeRight: return "Wipe Right"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        case .push: return "Push"
        case .slide: return "Slide"
        case .iris: return "Iris"
        case .custom: return "Custom"
        }
    }
    
    /// Default duration for this transition type
    public var defaultDuration: Double {
        switch self {
        case .cut: return 0
        case .crossfade: return 1.0
        case .dipToBlack, .dipToWhite: return 1.5
        case .wipeLeft, .wipeRight, .wipeUp, .wipeDown: return 0.5
        case .push, .slide: return 0.5
        case .iris: return 0.75
        case .custom: return 1.0
        }
    }
    
    /// Whether this transition requires two frames to render
    public var requiresTwoFrames: Bool {
        self != .cut
    }
    
    /// Metal kernel function name for this transition
    public var kernelName: String {
        switch self {
        case .cut: return ""
        case .crossfade: return "crossfadeTransition"
        case .dipToBlack: return "dipToBlackTransition"
        case .dipToWhite: return "dipToWhiteTransition"
        case .wipeLeft, .wipeRight, .wipeUp, .wipeDown: return "wipeTransition"
        case .push: return "pushTransition"
        case .slide: return "slideTransition"
        case .iris: return "irisTransition"
        case .custom: return "customTransition"
        }
    }
}

// MARK: - TransitionDirection

/// Direction for directional transitions (wipe, push, slide).
public enum TransitionDirection: Int, Codable, Sendable {
    case left = 0
    case right = 1
    case up = 2
    case down = 3
    
    /// Convert transition type to direction
    public static func from(_ type: VideoTransitionType) -> TransitionDirection? {
        switch type {
        case .wipeLeft: return .left
        case .wipeRight: return .right
        case .wipeUp: return .up
        case .wipeDown: return .down
        default: return nil
        }
    }
}

// MARK: - TransitionParameters

/// Additional parameters for transition rendering.
public struct TransitionParameters: Codable, Sendable {
    
    /// Edge softness for wipe transitions (0.0 = hard edge, 0.1 = soft)
    public var softness: Float
    
    /// Hold ratio for dip transitions (0.0 - 1.0)
    /// Example: 0.2 means 20% of duration is fully black/white
    public var holdRatio: Float
    
    /// Direction for directional transitions
    public var direction: TransitionDirection?
    
    /// Feather amount for iris transitions
    public var feather: Float
    
    /// Custom shader name for custom transitions
    public var customShader: String?
    
    /// Custom parameters for custom transitions
    public var customParameters: [String: Float]?
    
    public init(
        softness: Float = 0.02,
        holdRatio: Float = 0.2,
        direction: TransitionDirection? = nil,
        feather: Float = 0.05,
        customShader: String? = nil,
        customParameters: [String: Float]? = nil
    ) {
        self.softness = softness
        self.holdRatio = holdRatio
        self.direction = direction
        self.feather = feather
        self.customShader = customShader
        self.customParameters = customParameters
    }
    
    /// Default parameters for a transition type
    public static func defaults(for type: VideoTransitionType) -> TransitionParameters {
        var params = TransitionParameters()
        params.direction = TransitionDirection.from(type)
        return params
    }
}

// MARK: - TransitionDefinition

/// Defines a transition between two clips.
///
/// Transitions are applied when clips overlap on the timeline.
/// The overlap duration determines the transition duration.
///
/// ## Example
/// ```swift
/// let transition = TransitionDefinition(
///     fromClip: ClipID("clip_1"),
///     toClip: ClipID("clip_2"),
///     type: .crossfade,
///     duration: 1.0
/// )
/// ```
///
/// ## Timing
/// For a 1-second crossfade:
/// - If clip_1 ends at 30s and clip_2 starts at 29s
/// - Transition plays from 29s to 30s
/// - At 29s: 100% clip_1
/// - At 29.5s: 50% each
/// - At 30s: 100% clip_2
public struct TransitionDefinition: Codable, Sendable, Identifiable, Hashable {
    
    // MARK: - Properties
    
    /// Unique identifier
    public let id: String
    
    /// ID of the outgoing clip
    public let fromClip: ClipID
    
    /// ID of the incoming clip
    public let toClip: ClipID
    
    /// Type of transition
    public var type: VideoTransitionType
    
    /// Duration of the transition in seconds
    public var duration: Double
    
    /// Additional parameters
    public var parameters: TransitionParameters
    
    /// Easing function for the transition progress
    public var easing: TransitionEasing
    
    // MARK: - Initialization
    
    public init(
        id: String = UUID().uuidString,
        fromClip: ClipID,
        toClip: ClipID,
        type: VideoTransitionType,
        duration: Double? = nil,
        parameters: TransitionParameters? = nil,
        easing: TransitionEasing = .linear
    ) {
        self.id = id
        self.fromClip = fromClip
        self.toClip = toClip
        self.type = type
        self.duration = duration ?? type.defaultDuration
        self.parameters = parameters ?? TransitionParameters.defaults(for: type)
        self.easing = easing
    }
    
    // MARK: - Progress Calculation
    
    /// Applies easing to the progress value.
    public func easedProgress(_ progress: Double) -> Double {
        easing.apply(progress)
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: TransitionDefinition, rhs: TransitionDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - TransitionEasing

/// Easing functions for transition progress.
public enum TransitionEasing: String, Codable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case smoothStep
    case smootherStep
    
    /// Applies the easing function to a progress value (0-1).
    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .smoothStep:
            // Hermite interpolation: 3t² - 2t³
            return t * t * (3 - 2 * t)
        case .smootherStep:
            // Ken Perlin's smootherstep: 6t⁵ - 15t⁴ + 10t³
            return t * t * t * (t * (t * 6 - 15) + 10)
        }
    }
}

// MARK: - TransitionPreset

/// Predefined transition configurations.
public enum TransitionPreset {
    /// Quick cross dissolve (0.5s)
    public static let quickDissolve = TransitionDefinition(
        fromClip: ClipID(""),
        toClip: ClipID(""),
        type: .crossfade,
        duration: 0.5,
        easing: .smoothStep
    )
    
    /// Standard cross dissolve (1.0s)
    public static let standardDissolve = TransitionDefinition(
        fromClip: ClipID(""),
        toClip: ClipID(""),
        type: .crossfade,
        duration: 1.0,
        easing: .smoothStep
    )
    
    /// Slow cross dissolve (2.0s)
    public static let slowDissolve = TransitionDefinition(
        fromClip: ClipID(""),
        toClip: ClipID(""),
        type: .crossfade,
        duration: 2.0,
        easing: .smoothStep
    )
    
    /// Standard dip to black
    public static let dipToBlack = TransitionDefinition(
        fromClip: ClipID(""),
        toClip: ClipID(""),
        type: .dipToBlack,
        duration: 1.5,
        parameters: TransitionParameters(holdRatio: 0.2)
    )
    
    /// Quick wipe left
    public static let quickWipeLeft = TransitionDefinition(
        fromClip: ClipID(""),
        toClip: ClipID(""),
        type: .wipeLeft,
        duration: 0.5,
        parameters: TransitionParameters(softness: 0.02)
    )
    
    /// Creates a preset with specific clip IDs.
    public static func crossfade(
        from: ClipID,
        to: ClipID,
        duration: Double = 1.0
    ) -> TransitionDefinition {
        TransitionDefinition(
            fromClip: from,
            toClip: to,
            type: .crossfade,
            duration: duration,
            easing: .smoothStep
        )
    }
    
    /// Creates a dip to black with specific clip IDs.
    public static func dip(
        from: ClipID,
        to: ClipID,
        duration: Double = 1.5,
        holdRatio: Float = 0.2
    ) -> TransitionDefinition {
        TransitionDefinition(
            fromClip: from,
            toClip: to,
            type: .dipToBlack,
            duration: duration,
            parameters: TransitionParameters(holdRatio: holdRatio)
        )
    }
    
    /// Creates a wipe with specific clip IDs.
    public static func wipe(
        from: ClipID,
        to: ClipID,
        direction: TransitionDirection,
        duration: Double = 0.5,
        softness: Float = 0.02
    ) -> TransitionDefinition {
        let type: VideoTransitionType = {
            switch direction {
            case .left: return .wipeLeft
            case .right: return .wipeRight
            case .up: return .wipeUp
            case .down: return .wipeDown
            }
        }()
        
        return TransitionDefinition(
            fromClip: from,
            toClip: to,
            type: type,
            duration: duration,
            parameters: TransitionParameters(softness: softness, direction: direction)
        )
    }
}
