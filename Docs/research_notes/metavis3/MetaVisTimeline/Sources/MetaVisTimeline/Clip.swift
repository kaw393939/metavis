import Foundation
import MetaVisCore

/// A Clip represents a segment of media or effect placed on a timeline.
/// It maps a range of time on the timeline to a range of time in the source content.
public struct Clip: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    
    /// The ID of the asset this clip references.
    public var assetId: UUID
    
    /// The range of time this clip occupies on the timeline.
    public var range: TimeRange
    
    /// The range of time this clip uses from the source media.
    /// The duration of sourceRange must always equal the duration of range (unless we support speed ramps later).
    public var sourceRange: TimeRange
    
    /// The synchronization status of the clip with its underlying asset.
    public var status: ClipStatus
    
    /// Optional transition to the next clip.
    public var outTransition: Transition?
    
    /// Creates a new Clip.
    /// - Parameters:
    ///   - id: Unique identifier.
    ///   - name: Display name.
    ///   - assetId: The ID of the asset.
    ///   - range: The time range on the timeline.
    ///   - sourceStartTime: The start time in the source media. The duration is automatically derived from `range`.
    ///   - status: The initial status of the clip.
    public init(
        id: UUID = UUID(),
        name: String,
        assetId: UUID,
        range: TimeRange,
        sourceStartTime: RationalTime,
        status: ClipStatus = .synced
    ) {
        self.id = id
        self.name = name
        self.assetId = assetId
        self.range = range
        self.sourceRange = TimeRange(start: sourceStartTime, duration: range.duration)
        self.status = status
    }
    
    // MARK: - Codable Validation
    
    enum CodingKeys: String, CodingKey {
        case id, name, assetId, range, sourceRange, status, outTransition
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        assetId = try container.decode(UUID.self, forKey: .assetId)
        range = try container.decode(TimeRange.self, forKey: .range)
        sourceRange = try container.decode(TimeRange.self, forKey: .sourceRange)
        status = try container.decodeIfPresent(ClipStatus.self, forKey: .status) ?? .synced
        outTransition = try container.decodeIfPresent(Transition.self, forKey: .outTransition)
        
        // Validate invariant: Durations must match
        if range.duration != sourceRange.duration {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceRange,
                in: container,
                debugDescription: "Clip source duration (\(sourceRange.duration)) must match timeline duration (\(range.duration))."
            )
        }
        
        // Validate transition
        if let transition = outTransition, transition.duration.value < 0 {
             throw DecodingError.dataCorruptedError(
                forKey: .outTransition,
                in: container,
                debugDescription: "Transition duration cannot be negative."
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(assetId, forKey: .assetId)
        try container.encode(range, forKey: .range)
        try container.encode(sourceRange, forKey: .sourceRange)
        try container.encodeIfPresent(outTransition, forKey: .outTransition)
    }
    
    /// Validates the clip's integrity.
    public func validate() throws {
        if range.duration != sourceRange.duration {
             throw TimelineError.invalidDuration
        }
        if let transition = outTransition {
            if transition.duration.value < 0 {
                throw TimelineError.invalidDuration
            }
        }
    }
    
    /// Maps a time from the timeline to the source media time.
    /// Returns nil if the time is outside the clip's range.
    public func mapTime(_ time: RationalTime) -> RationalTime? {
        guard range.contains(time) else { return nil }
        
        let offset = time - range.start
        return sourceRange.start + offset
    }
    
    /// Moves the clip to a new start time on the timeline.
    public mutating func move(to newStart: RationalTime) {
        range = TimeRange(start: newStart, duration: range.duration)
    }
    
    /// Trims the start of the clip.
    /// This moves the start time later and reduces duration.
    /// It also moves the source start time later.
    public mutating func trimStart(by amount: RationalTime) {
        // Ensure we don't trim past the end
        guard amount < range.duration else { return }
        
        range.start = range.start + amount
        range.duration = range.duration - amount
        
        sourceRange.start = sourceRange.start + amount
        sourceRange.duration = sourceRange.duration - amount
    }
    
    /// Trims the end of the clip.
    /// This reduces the duration.
    public mutating func trimEnd(by amount: RationalTime) {
        guard amount < range.duration else { return }
        
        range.duration = range.duration - amount
        sourceRange.duration = sourceRange.duration - amount
    }
    
    /// Slips the content of the clip.
    /// Changes the source range without changing the timeline range.
    public mutating func slip(by amount: RationalTime) {
        sourceRange.start = sourceRange.start + amount
    }
}
