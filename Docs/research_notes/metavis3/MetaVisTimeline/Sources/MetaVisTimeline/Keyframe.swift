import Foundation
import MetaVisCore

/// Defines how values are interpolated between keyframes.
public enum InterpolationType: String, Codable, Sendable {
    case linear
    case step
    case bezier
}

/// Defines behavior when evaluating outside the keyframe range.
public enum ExtrapolationType: String, Codable, Sendable {
    case hold
    case loop
    case pingPong
}

/// A keyframe defines a value at a specific point in time.
///
/// - Note: This implementation uses `RationalTime` for precise timing,
///   replacing the legacy `Double` based implementation.
public struct Keyframe<T: Interpolatable & Sendable>: Sendable {
    /// Time when this keyframe occurs.
    public let time: RationalTime
    
    /// The value at this keyframe.
    public let value: T
    
    /// Optional tangent for bezier interpolation (used for in-tangent).
    public let inTangent: T?
    
    /// Optional tangent for bezier interpolation (used for out-tangent).
    public let outTangent: T?
    
    /// Optional easing function to apply between this keyframe and the next.
    /// If nil, linear interpolation is used (unless track overrides).
    public let easing: Easing?
    
    public init(time: RationalTime, value: T, inTangent: T? = nil, outTangent: T? = nil, easing: Easing? = nil) {
        self.time = time
        self.value = value
        self.inTangent = inTangent
        self.outTangent = outTangent
        self.easing = easing
    }
}

extension Keyframe: Codable where T: Codable {}

/// A track contains multiple keyframes for a single property.
public struct KeyframeTrack<T: Interpolatable & Sendable>: Sendable {
    /// The keyframes, sorted by time.
    public private(set) var keyframes: [Keyframe<T>]
    
    /// The default interpolation curve to use if keyframe doesn't specify easing.
    public let interpolation: InterpolationType
    
    /// Optional: Extrapolation behavior before first keyframe.
    public let preExtrapolation: ExtrapolationType
    
    /// Optional: Extrapolation behavior after last keyframe.
    public let postExtrapolation: ExtrapolationType
    
    public init(
        keyframes: [Keyframe<T>],
        interpolation: InterpolationType = .linear,
        preExtrapolation: ExtrapolationType = .hold,
        postExtrapolation: ExtrapolationType = .hold
    ) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
        self.interpolation = interpolation
        self.preExtrapolation = preExtrapolation
        self.postExtrapolation = postExtrapolation
    }
    
    /// Add a keyframe, maintaining sorted order.
    /// If a keyframe already exists at the same time, it is replaced.
    public mutating func addKeyframe(_ keyframe: Keyframe<T>) {
        keyframes.removeAll { $0.time == keyframe.time }
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }
    
    /// Remove keyframe at index.
    public mutating func removeKeyframe(at index: Int) {
        guard keyframes.indices.contains(index) else { return }
        keyframes.remove(at: index)
    }
    
    /// Evaluate the track at a given time.
    /// - Throws: `TimelineError.emptyTrack` if the track has no keyframes.
    public func evaluate(at time: RationalTime) throws -> T {
        guard !keyframes.isEmpty else {
            throw TimelineError.emptyTrack
        }
        
        // Single keyframe - return its value
        if keyframes.count == 1 {
            return keyframes[0].value
        }
        
        // Before first keyframe
        if time <= keyframes[0].time {
            return extrapolate(time: time, direction: .pre)
        }
        
        // After last keyframe
        if time >= keyframes[keyframes.count - 1].time {
            return extrapolate(time: time, direction: .post)
        }
        
        // Find surrounding keyframes
        // Optimization: Binary search for O(log n) performance
        let index = binarySearchKeyframeIndex(for: time)
        
        // Safety check
        if index >= keyframes.count - 1 {
            return keyframes.last!.value
        }
        
        let k1 = keyframes[index]
        let k2 = keyframes[index+1]
        
        let progress = calculateProgress(from: k1.time, to: k2.time, current: time)
        return interpolate(from: k1, to: k2, progress: progress)
    }
    
    // MARK: - Helpers
    
    private func binarySearchKeyframeIndex(for time: RationalTime) -> Int {
        var low = 0
        var high = keyframes.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let midTime = keyframes[mid].time
            
            if midTime == time {
                return mid
            } else if midTime < time {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        // If we don't find exact match, 'high' is the index of the keyframe just before 'time'
        return max(0, min(high, keyframes.count - 2))
    }
    
    private enum ExtrapolationDirection {
        case pre
        case post
    }
    
    private func extrapolate(time: RationalTime, direction: ExtrapolationDirection) -> T {
        let type = (direction == .pre) ? preExtrapolation : postExtrapolation
        
        switch type {
        case .hold:
            return (direction == .pre) ? keyframes.first!.value : keyframes.last!.value
            
        case .loop:
            let duration = keyframes.last!.time - keyframes.first!.time
            if duration.value == 0 { return keyframes.first!.value }
            
            // Calculate offset in loop
            // This requires RationalTime modulo, which we might need to implement or approximate via seconds
            let timeInLoop = (time.seconds - keyframes.first!.time.seconds).truncatingRemainder(dividingBy: duration.seconds)
            let mappedTime = keyframes.first!.time + RationalTime(seconds: timeInLoop < 0 ? timeInLoop + duration.seconds : timeInLoop)
            return (try? evaluate(at: mappedTime)) ?? keyframes.first!.value
            
        case .pingPong:
            let duration = keyframes.last!.time - keyframes.first!.time
            if duration.value == 0 { return keyframes.first!.value }
            
            let timeDiff = (time.seconds - keyframes.first!.time.seconds)
            let cycles = floor(abs(timeDiff) / duration.seconds)
            let timeInLoop = abs(timeDiff).truncatingRemainder(dividingBy: duration.seconds)
            
            // If cycle count is even, we are going forward. If odd, we are going backward (ping-pong).
            let isReverse = Int(cycles) % 2 != 0
            
            let mappedTimeSeconds = isReverse ? (duration.seconds - timeInLoop) : timeInLoop
            let mappedTime = keyframes.first!.time + RationalTime(seconds: mappedTimeSeconds)
            
            // Recursively evaluate at the mapped time (which is now inside the range)
            // Note: We must be careful not to recurse infinitely. 
            // Since mappedTime is strictly within [first, last], it won't trigger extrapolation again.
            // However, evaluate() throws, so we must try!
            return (try? evaluate(at: mappedTime)) ?? keyframes.first!.value
        }
    }
    
    private func calculateProgress(from start: RationalTime, to end: RationalTime, current: RationalTime) -> Double {
        // Use RationalTime arithmetic to preserve precision for the difference
        let duration = end - start
        let elapsed = current - start
        
        if duration.value == 0 { return 0 }
        
        // Convert to seconds only after subtraction
        return elapsed.seconds / duration.seconds
    }
    
    private func interpolate(from k1: Keyframe<T>, to k2: Keyframe<T>, progress: Double) -> T {
        // 1. Apply Easing if present on the starting keyframe
        let easedProgress: Double
        if let easing = k1.easing {
            easedProgress = easing.apply(progress)
        } else {
            easedProgress = progress
        }
        
        // 2. Apply Interpolation Logic
        switch interpolation {
        case .step:
            return k1.value
        case .linear:
            return T.interpolate(from: k1.value, to: k2.value, t: easedProgress)
        case .bezier:
            // Basic cubic bezier if tangents exist, else linear fallback
            if let outTangent = k1.outTangent, let inTangent = k2.inTangent {
                return T.interpolateCubic(from: k1.value, outTangent: outTangent, to: k2.value, inTangent: inTangent, t: easedProgress)
            }
            return T.interpolate(from: k1.value, to: k2.value, t: easedProgress)
        }
    }
}

extension KeyframeTrack: Codable where T: Codable {}

