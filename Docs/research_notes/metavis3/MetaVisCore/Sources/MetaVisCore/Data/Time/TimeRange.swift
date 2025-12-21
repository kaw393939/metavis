import Foundation

/// Represents a span of time defined by a start time and a duration.
/// Essential for defining clips, render ranges, and audio segments.
public struct TimeRange: Codable, Equatable, Hashable, Sendable {
    public var start: RationalTime
    public var duration: RationalTime
    
    public init(start: RationalTime, duration: RationalTime) {
        self.start = start
        self.duration = duration
    }
    
    /// The end time of the range (exclusive).
    /// start + duration
    public var end: RationalTime {
        return start + duration
    }
    
    /// Checks if a time is within the range (inclusive start, exclusive end).
    public func contains(_ time: RationalTime) -> Bool {
        return time >= start && time < end
    }
    
    /// Checks if another range is fully contained within this range.
    public func contains(_ other: TimeRange) -> Bool {
        return other.start >= start && other.end <= end
    }
    
    /// Returns the intersection of two time ranges, or nil if they don't overlap.
    public func intersection(_ other: TimeRange) -> TimeRange? {
        let maxStart = max(self.start, other.start)
        let minEnd = min(self.end, other.end)
        
        if maxStart < minEnd {
            return TimeRange(start: maxStart, duration: minEnd - maxStart)
        }
        return nil
    }
    
    /// Returns a new range shifted by the given offset.
    public func offset(by offset: RationalTime) -> TimeRange {
        return TimeRange(start: start + offset, duration: duration)
    }
    
    public static let zero = TimeRange(start: .zero, duration: .zero)
}

extension TimeRange: CustomStringConvertible {
    public var description: String {
        return "[\(start) ..< \(end)] (dur: \(duration))"
    }
}

// MARK: - Comparable Support for RationalTime
// We need to ensure RationalTime conforms to Comparable for the logic above to work.
// (It was declared Comparable in the previous step, but let's ensure the implementation supports it)
