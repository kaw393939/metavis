// VolumeAutomation.swift
// MetaVisRender
//
// Created for Sprint 12: Audio Mixing
// Keyframe-based volume automation

import Foundation

// MARK: - VolumeKeyframe

/// A single volume automation keyframe
public struct VolumeKeyframe: Codable, Sendable, Equatable {
    /// Time within clip (seconds from clip start)
    public let time: Double
    
    /// Volume value (0.0 - 2.0)
    public let value: Float
    
    /// Interpolation curve to next keyframe
    public let curve: InterpolationCurve
    
    public init(
        time: Double,
        value: Float,
        curve: InterpolationCurve = .linear
    ) {
        self.time = time
        self.value = value.clamped(to: 0...2)
        self.curve = curve
    }
}

// MARK: - InterpolationCurve

/// Interpolation curve between keyframes
public enum InterpolationCurve: String, Codable, Sendable, CaseIterable {
    /// Linear interpolation
    case linear
    
    /// Ease in (slow start)
    case easeIn
    
    /// Ease out (slow end)
    case easeOut
    
    /// Ease in and out
    case easeInOut
    
    /// Hold until next keyframe
    case hold
    
    /// Exponential (for audio-natural fades)
    case exponential
    
    /// Apply curve to progress value
    public func apply(_ t: Double) -> Double {
        let t = t.clamped(to: 0...1)
        
        switch self {
        case .linear:
            return t
            
        case .easeIn:
            return t * t
            
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
            
        case .easeInOut:
            return t < 0.5
                ? 2 * t * t
                : 1 - pow(-2 * t + 2, 2) / 2
            
        case .hold:
            return 0  // Always use start value
            
        case .exponential:
            // More natural for audio - logarithmic perception
            return t == 0 ? 0 : pow(2, 10 * (t - 1))
        }
    }
}

// MARK: - VolumeAutomation

/// Volume automation with keyframes
///
/// Allows precise volume control over time with keyframes.
///
/// ## Example
/// ```swift
/// var automation = VolumeAutomation()
/// automation.add(keyframe: VolumeKeyframe(time: 0, value: 0))
/// automation.add(keyframe: VolumeKeyframe(time: 2, value: 1.0))
/// automation.add(keyframe: VolumeKeyframe(time: 8, value: 1.0))
/// automation.add(keyframe: VolumeKeyframe(time: 10, value: 0))
/// ```
public struct VolumeAutomation: Codable, Sendable {
    
    // MARK: - Properties
    
    /// Sorted keyframes
    public private(set) var keyframes: [VolumeKeyframe]
    
    /// Default interpolation for new keyframes
    public var defaultCurve: InterpolationCurve
    
    // MARK: - Initialization
    
    public init(
        keyframes: [VolumeKeyframe] = [],
        defaultCurve: InterpolationCurve = .linear
    ) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
        self.defaultCurve = defaultCurve
    }
    
    // MARK: - Keyframe Management
    
    /// Add a keyframe
    public mutating func add(keyframe: VolumeKeyframe) {
        // Remove existing keyframe at same time
        keyframes.removeAll { abs($0.time - keyframe.time) < 0.001 }
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }
    
    /// Add a keyframe at time with value
    public mutating func add(
        at time: Double,
        value: Float,
        curve: InterpolationCurve? = nil
    ) {
        let keyframe = VolumeKeyframe(
            time: time,
            value: value,
            curve: curve ?? defaultCurve
        )
        add(keyframe: keyframe)
    }
    
    /// Remove keyframe at time
    public mutating func remove(at time: Double) {
        keyframes.removeAll { abs($0.time - time) < 0.001 }
    }
    
    /// Remove all keyframes
    public mutating func clear() {
        keyframes.removeAll()
    }
    
    // MARK: - Value Evaluation
    
    /// Get interpolated value at time
    public func value(at time: Double) -> Float {
        guard !keyframes.isEmpty else { return 1.0 }
        
        // Before first keyframe
        if let first = keyframes.first, time <= first.time {
            return first.value
        }
        
        // After last keyframe
        if let last = keyframes.last, time >= last.time {
            return last.value
        }
        
        // Find surrounding keyframes
        var prev: VolumeKeyframe?
        var next: VolumeKeyframe?
        
        for (index, keyframe) in keyframes.enumerated() {
            if keyframe.time <= time {
                prev = keyframe
                if index + 1 < keyframes.count {
                    next = keyframes[index + 1]
                }
            } else {
                break
            }
        }
        
        guard let from = prev, let to = next else {
            return prev?.value ?? next?.value ?? 1.0
        }
        
        // Interpolate
        let duration = to.time - from.time
        guard duration > 0 else { return from.value }
        
        let progress = (time - from.time) / duration
        let curvedProgress = from.curve.apply(progress)
        
        return from.value + Float(curvedProgress) * (to.value - from.value)
    }
    
    // MARK: - Convenience
    
    /// Create a fade in automation
    public static func fadeIn(duration: Double, curve: InterpolationCurve = .easeOut) -> VolumeAutomation {
        VolumeAutomation(keyframes: [
            VolumeKeyframe(time: 0, value: 0, curve: curve),
            VolumeKeyframe(time: duration, value: 1.0, curve: .linear)
        ])
    }
    
    /// Create a fade out automation
    public static func fadeOut(
        at startTime: Double,
        duration: Double,
        curve: InterpolationCurve = .easeIn
    ) -> VolumeAutomation {
        VolumeAutomation(keyframes: [
            VolumeKeyframe(time: startTime, value: 1.0, curve: curve),
            VolumeKeyframe(time: startTime + duration, value: 0, curve: .linear)
        ])
    }
    
    /// Create a fade in/out automation
    public static func fadeInOut(
        fadeIn: Double,
        hold: Double,
        fadeOut: Double,
        holdVolume: Float = 1.0
    ) -> VolumeAutomation {
        let fadeOutStart = fadeIn + hold
        
        return VolumeAutomation(keyframes: [
            VolumeKeyframe(time: 0, value: 0, curve: .easeOut),
            VolumeKeyframe(time: fadeIn, value: holdVolume, curve: .linear),
            VolumeKeyframe(time: fadeOutStart, value: holdVolume, curve: .easeIn),
            VolumeKeyframe(time: fadeOutStart + fadeOut, value: 0, curve: .linear)
        ])
    }
    
    /// Create ducking automation
    /// - Parameters:
    ///   - startTime: When ducking starts
    ///   - duration: How long to stay ducked
    ///   - duckLevel: Volume during duck (0-1)
    ///   - attackTime: Fade down time
    ///   - releaseTime: Fade up time
    public static func duck(
        at startTime: Double,
        duration: Double,
        duckLevel: Float = 0.3,
        attackTime: Double = 0.3,
        releaseTime: Double = 0.5
    ) -> VolumeAutomation {
        VolumeAutomation(keyframes: [
            VolumeKeyframe(time: startTime, value: 1.0, curve: .exponential),
            VolumeKeyframe(time: startTime + attackTime, value: duckLevel, curve: .linear),
            VolumeKeyframe(time: startTime + duration - releaseTime, value: duckLevel, curve: .exponential),
            VolumeKeyframe(time: startTime + duration, value: 1.0, curve: .linear)
        ])
    }
}

// MARK: - Volume Unit Conversions

/// Convert linear volume to decibels
public func linearToDB(_ linear: Float) -> Float {
    guard linear > 0 else { return -.infinity }
    return 20 * log10(linear)
}

/// Convert decibels to linear volume
public func dBToLinear(_ dB: Float) -> Float {
    guard dB > -.infinity else { return 0 }
    return pow(10, dB / 20)
}

/// Convert decibel string (e.g., "-12dB") to linear
public func parseDuckLevel(_ string: String) -> Float? {
    let cleaned = string.lowercased().replacingOccurrences(of: "db", with: "").trimmingCharacters(in: .whitespaces)
    guard let dB = Float(cleaned) else { return nil }
    return dBToLinear(dB)
}
