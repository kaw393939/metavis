import Foundation
import MetaVisCore

/// A reference to a media asset or generator.
public struct AssetReference: Codable, Sendable, Equatable {
    public let id: UUID
    public let sourceFn: String // e.g. "file:///..." or "ligm://..."
    
    public init(id: UUID = UUID(), sourceFn: String) {
        self.id = id
        self.sourceFn = sourceFn
    }
}

/// A segment of media on a track.
public struct Clip: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let asset: AssetReference
    
    /// Start time in the Timeline.
    public var startTime: Time
    
    /// Duration of the clip in the Timeline.
    public var duration: Time
    
    /// Offset into the source Asset (Trim In).
    public var offset: Time
    
    /// Transition applied when clip fades IN (at startTime)
    public var transitionIn: Transition?
    
    /// Transition applied when clip fades OUT (at endTime)
    public var transitionOut: Transition?

    /// Clip-level effects (applied in order, in working color space).
    public var effects: [FeatureApplication]
    
    public init(
        id: UUID = UUID(),
        name: String,
        asset: AssetReference,
        startTime: Time,
        duration: Time,
        offset: Time = .zero,
        transitionIn: Transition? = nil,
        transitionOut: Transition? = nil,
        effects: [FeatureApplication] = []
    ) {
        self.id = id
        self.name = name
        self.asset = asset
        self.startTime = startTime
        self.duration = duration
        self.offset = offset
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
        self.effects = effects
    }

    /// Backward-compatible initializer (predates `effects`).
    public init(
        id: UUID = UUID(),
        name: String,
        asset: AssetReference,
        startTime: Time,
        duration: Time,
        offset: Time = .zero,
        transitionIn: Transition? = nil,
        transitionOut: Transition? = nil
    ) {
        self.init(
            id: id,
            name: name,
            asset: asset,
            startTime: startTime,
            duration: duration,
            offset: offset,
            transitionIn: transitionIn,
            transitionOut: transitionOut,
            effects: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case asset
        case startTime
        case duration
        case offset
        case transitionIn
        case transitionOut
        case effects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.asset = try container.decode(AssetReference.self, forKey: .asset)
        self.startTime = try container.decode(Time.self, forKey: .startTime)
        self.duration = try container.decode(Time.self, forKey: .duration)
        self.offset = try container.decodeIfPresent(Time.self, forKey: .offset) ?? .zero
        self.transitionIn = try container.decodeIfPresent(Transition.self, forKey: .transitionIn)
        self.transitionOut = try container.decodeIfPresent(Transition.self, forKey: .transitionOut)
        self.effects = try container.decodeIfPresent([FeatureApplication].self, forKey: .effects) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(asset, forKey: .asset)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
        try container.encode(offset, forKey: .offset)
        try container.encodeIfPresent(transitionIn, forKey: .transitionIn)
        try container.encodeIfPresent(transitionOut, forKey: .transitionOut)
        if !effects.isEmpty {
            try container.encode(effects, forKey: .effects)
        }
    }
    
    public var endTime: Time {
        return startTime + duration
    }
    
    /// Check if this clip overlaps with another clip in timeline
    public func overlaps(with other: Clip) -> Bool {
        return !(self.endTime <= other.startTime || other.endTime <= self.startTime)
    }
    
    /// Calculate the alpha (opacity) of this clip at a given time, accounting for transitions
    /// Returns 0.0 (transparent) to 1.0 (opaque)
    public func alpha(at time: Time) -> Float {
        // Before clip starts or after clip ends
        guard time >= startTime && time < endTime else {
            return 0.0
        }
        
        let clipLocalTime = time - startTime
        
        // Fade IN?
        if let transIn = transitionIn, clipLocalTime < transIn.duration {
            let progress = Float(clipLocalTime.seconds / transIn.duration.seconds)
            return transIn.easing.apply(progress)
        }
        
        // Fade OUT?
        let timeUntilEnd = endTime - time
        if let transOut = transitionOut, timeUntilEnd < transOut.duration {
            let progress = Float(timeUntilEnd.seconds / transOut.duration.seconds)
            return transOut.easing.apply(progress)
        }
        
        // Fully opaque
        return 1.0
    }
}


/// A collection of Clips arranged in time.
public enum TrackKind: String, Codable, Sendable, Equatable {
    case video
    case audio
    case data
}

/// A collection of Clips arranged in time.
public struct Track: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public var kind: TrackKind
    public var clips: [Clip]
    
    public init(id: UUID = UUID(), name: String, clips: [Clip] = []) {
        self.init(id: id, name: name, kind: .video, clips: clips)
    }

    public init(id: UUID = UUID(), name: String, kind: TrackKind = .video, clips: [Clip] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.clips = clips
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case clips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decodeIfPresent(TrackKind.self, forKey: .kind) ?? .video
        self.clips = try container.decode([Clip].self, forKey: .clips)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(clips, forKey: .clips)
    }
}

/// The root data model for a Project.
public struct Timeline: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var tracks: [Track]
    public var duration: Time
    
    public init(id: UUID = UUID(), tracks: [Track] = [], duration: Time = .zero) {
        self.id = id
        self.tracks = tracks
        self.duration = duration
    }

    public enum ValidationIssue: Sendable, Equatable {
        case overlappingClips(trackId: UUID, trackName: String, a: UUID, b: UUID)
    }

    /// Returns validation issues for the timeline model.
    /// Currently checks: overlapping clips within a track.
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        issues.reserveCapacity(4)

        for track in tracks {
            // Sort by time so we only need to check neighbors.
            let sorted = track.clips.sorted {
                if $0.startTime != $1.startTime { return $0.startTime < $1.startTime }
                // Deterministic tie-breaker.
                return $0.id.uuidString < $1.id.uuidString
            }

            for i in 1..<sorted.count {
                let prev = sorted[i - 1]
                let cur = sorted[i]
                if prev.overlaps(with: cur) {
                    issues.append(.overlappingClips(trackId: track.id, trackName: track.name, a: prev.id, b: cur.id))
                }
            }
        }

        return issues
    }
}
