import Foundation
import CoreGraphics
import simd

public protocol Interpolatable {
    static func interpolate(from: Self, to: Self, t: Double) -> Self
}

extension Float: Interpolatable {
    public static func interpolate(from: Float, to: Float, t: Double) -> Float {
        return from + (to - from) * Float(t)
    }
}

extension Double: Interpolatable {
    public static func interpolate(from: Double, to: Double, t: Double) -> Double {
        return from + (to - from) * t
    }
}

extension CGFloat: Interpolatable {
    public static func interpolate(from: CGFloat, to: CGFloat, t: Double) -> CGFloat {
        return from + (to - from) * CGFloat(t)
    }
}

extension CGPoint: Interpolatable {
    public static func interpolate(from: CGPoint, to: CGPoint, t: Double) -> CGPoint {
        return CGPoint(
            x: CGFloat.interpolate(from: from.x, to: to.x, t: t),
            y: CGFloat.interpolate(from: from.y, to: to.y, t: t)
        )
    }
}

extension SIMD4<Float>: Interpolatable {
    public static func interpolate(from: SIMD4<Float>, to: SIMD4<Float>, t: Double) -> SIMD4<Float> {
        return from + (to - from) * Float(t)
    }
}

public struct Tween<T: Interpolatable> {
    public let start: T
    public let end: T
    public let startTime: Double
    public let duration: Double
    public let easing: Easing
    
    public init(from: T, to: T, startTime: Double, duration: Double, easing: Easing = .linear) {
        self.start = from
        self.end = to
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
    }
    
    public func value(at time: Double) -> T {
        if time < startTime { return start }
        if time >= startTime + duration { return end }
        
        let progress = (time - startTime) / duration
        let easedProgress = easing.apply(progress)
        
        return T.interpolate(from: start, to: end, t: easedProgress)
    }
}

// A simple timeline manager to hold multiple tweens
public class AnimationTrack<T: Interpolatable> {
    private var tweens: [Tween<T>] = []
    private var baseValue: T
    
    public init(baseValue: T) {
        self.baseValue = baseValue
    }
    
    public func add(tween: Tween<T>) {
        tweens.append(tween)
        // Sort by start time
        tweens.sort { $0.startTime < $1.startTime }
    }
    
    public func to(_ value: T, startTime: Double, duration: Double, easing: Easing = .linear) {
        // Find the value at startTime to use as start value
        let startVal = self.value(at: startTime)
        let tween = Tween(from: startVal, to: value, startTime: startTime, duration: duration, easing: easing)
        add(tween: tween)
    }
    
    public func value(at time: Double) -> T {
        // Find active tween
        // If multiple overlap, the latest one usually wins or we blend.
        // For simplicity, let's just find the last one that started before 'time'.
        
        // If we are in a gap, we hold the end value of the previous tween.
        
        var currentValue = baseValue
        
        for tween in tweens {
            if time >= tween.startTime {
                currentValue = tween.value(at: time)
            } else {
                // Future tween, stop checking if we assume sorted
                break
            }
        }
        
        return currentValue
    }
}
