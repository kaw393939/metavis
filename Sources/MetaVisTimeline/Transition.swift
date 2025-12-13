import Foundation
import MetaVisCore

/// Easing curve for transition animations
public enum EasingCurve: String, Codable, Sendable, Equatable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    
    /// Apply easing to a normalized progress value [0, 1]
    public func apply(_ t: Float) -> Float {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1.0 - (1.0 - t) * (1.0 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1.0 - 2 * (1 - t) * (1 - t)
        }
    }
}

/// Type of transition between clips
public enum TransitionType: Codable, Sendable, Equatable {
    case cut                    // Instant switch (0 duration)
    case crossfade              // Linear alpha blend
    case dip(color: SIMD3<Float>)  // Fade to color, then fade in next clip
    case wipe(direction: WipeDirection)
    
    public enum WipeDirection: String, Codable, Sendable, Equatable {
        case leftToRight
        case rightToLeft
        case topToBottom
        case bottomToTop
    }
}

/// Defines how a clip transitions in or out
public struct Transition: Codable, Sendable, Equatable {
    public let type: TransitionType
    public let duration: Time
    public let easing: EasingCurve
    
    public init(type: TransitionType, duration: Time, easing: EasingCurve = .linear) {
        self.type = type
        self.duration = duration
        self.easing = easing
    }
    
    /// Helper: Create instant cut (no transition)
    public static var cut: Transition {
        return Transition(type: .cut, duration: .zero)
    }
    
    /// Helper: Create crossfade with specified duration
    public static func crossfade(duration: Time, easing: EasingCurve = .linear) -> Transition {
        return Transition(type: .crossfade, duration: duration, easing: easing)
    }
    
    /// Helper: Create dip to black
    public static func dipToBlack(duration: Time) -> Transition {
        return Transition(type: .dip(color: SIMD3<Float>(0, 0, 0)), duration: duration)
    }
}
