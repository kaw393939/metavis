// OTIOExporter.swift
// MetaVisRender
//
// Exports timeline to OpenTimelineIO (OTIO) format for universal NLE interchange

import Foundation
import CoreMedia

// MARK: - OTIO Types

/// OTIO schema types
public enum OTIOSchemaType: String, Codable {
    case timeline = "Timeline.1"
    case stack = "Stack.1"
    case track = "Track.1"
    case clip = "Clip.1"
    case gap = "Gap.1"
    case transition = "Transition.1"
    case externalReference = "ExternalReference.1"
    case missingReference = "MissingReference.1"
    case rationalTime = "RationalTime.1"
    case timeRange = "TimeRange.1"
    case linearTimeWarp = "LinearTimeWarp.1"
    case effect = "Effect.1"
    case marker = "Marker.1"
}

/// OTIO track kind
public enum OTIOTrackKind: String, Codable {
    case video = "Video"
    case audio = "Audio"
}

// MARK: - OTIO Rational Time

/// Represents time in OTIO format
public struct OTIORationalTime: Codable, Sendable {
    public static let schemaName = "RationalTime.1"
    
    public let value: Double
    public let rate: Double
    
    public init(value: Double, rate: Double) {
        self.value = value
        self.rate = rate
    }
    
    public init(seconds: Double, rate: Double = 24.0) {
        self.value = seconds * rate
        self.rate = rate
    }
    
    public init(cmTime: CMTime, rate: Double = 24.0) {
        self.value = cmTime.seconds * rate
        self.rate = rate
    }
    
    public var seconds: Double {
        return value / rate
    }
    
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case value
        case rate
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(value, forKey: .value)
        try container.encode(rate, forKey: .rate)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Double.self, forKey: .value)
        rate = try container.decode(Double.self, forKey: .rate)
    }
}

// MARK: - OTIO Time Range

/// Represents a time range in OTIO format
public struct OTIOTimeRange: Codable, Sendable {
    public static let schemaName = "TimeRange.1"
    
    public let startTime: OTIORationalTime
    public let duration: OTIORationalTime
    
    public init(startTime: OTIORationalTime, duration: OTIORationalTime) {
        self.startTime = startTime
        self.duration = duration
    }
    
    public init(start: Double, duration: Double, rate: Double = 24.0) {
        self.startTime = OTIORationalTime(seconds: start, rate: rate)
        self.duration = OTIORationalTime(seconds: duration, rate: rate)
    }
    
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case startTime = "start_time"
        case duration
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(duration, forKey: .duration)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try container.decode(OTIORationalTime.self, forKey: .startTime)
        duration = try container.decode(OTIORationalTime.self, forKey: .duration)
    }
}

// MARK: - OTIO External Reference

/// Reference to external media
public struct OTIOExternalReference: Sendable {
    public static let schemaName = "ExternalReference.1"
    
    public let targetURL: String
    public let availableRange: OTIOTimeRange?
    public let metadata: [String: AnyCodable]?
    
    public init(
        targetURL: String,
        availableRange: OTIOTimeRange? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.targetURL = targetURL
        self.availableRange = availableRange
        self.metadata = metadata
    }
}

extension OTIOExternalReference: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case targetURL = "target_url"
        case availableRange = "available_range"
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(targetURL, forKey: .targetURL)
        try container.encodeIfPresent(availableRange, forKey: .availableRange)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Clip

/// A clip in the OTIO timeline
public struct OTIOClip: Sendable {
    public static let schemaName = "Clip.1"
    
    public let name: String
    public let sourceRange: OTIOTimeRange?
    public let mediaReference: OTIOExternalReference?
    public let effects: [OTIOEffect]?
    public let markers: [OTIOMarker]?
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        sourceRange: OTIOTimeRange? = nil,
        mediaReference: OTIOExternalReference? = nil,
        effects: [OTIOEffect]? = nil,
        markers: [OTIOMarker]? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.sourceRange = sourceRange
        self.mediaReference = mediaReference
        self.effects = effects
        self.markers = markers
        self.metadata = metadata
    }
}

extension OTIOClip: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case sourceRange = "source_range"
        case mediaReference = "media_reference"
        case effects
        case markers
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(sourceRange, forKey: .sourceRange)
        try container.encodeIfPresent(mediaReference, forKey: .mediaReference)
        try container.encodeIfPresent(effects, forKey: .effects)
        try container.encodeIfPresent(markers, forKey: .markers)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Gap

/// A gap (empty space) in the timeline
public struct OTIOGap: Sendable {
    public static let schemaName = "Gap.1"
    
    public let name: String?
    public let sourceRange: OTIOTimeRange?
    
    public init(name: String? = nil, sourceRange: OTIOTimeRange? = nil) {
        self.name = name
        self.sourceRange = sourceRange
    }
}

extension OTIOGap: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case sourceRange = "source_range"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(sourceRange, forKey: .sourceRange)
    }
}

// MARK: - OTIO Transition

/// A transition between clips
public struct OTIOTransition: Sendable {
    public static let schemaName = "Transition.1"
    
    public let name: String
    public let transitionType: String
    public let inOffset: OTIORationalTime?
    public let outOffset: OTIORationalTime?
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        transitionType: String = "SMPTE_Dissolve",
        inOffset: OTIORationalTime? = nil,
        outOffset: OTIORationalTime? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.transitionType = transitionType
        self.inOffset = inOffset
        self.outOffset = outOffset
        self.metadata = metadata
    }
}

extension OTIOTransition: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case transitionType = "transition_type"
        case inOffset = "in_offset"
        case outOffset = "out_offset"
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encode(transitionType, forKey: .transitionType)
        try container.encodeIfPresent(inOffset, forKey: .inOffset)
        try container.encodeIfPresent(outOffset, forKey: .outOffset)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Effect

/// An effect applied to a clip
public struct OTIOEffect: Sendable {
    public static let schemaName = "Effect.1"
    
    public let name: String
    public let effectName: String
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        effectName: String,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.effectName = effectName
        self.metadata = metadata
    }
}

extension OTIOEffect: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case effectName = "effect_name"
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encode(effectName, forKey: .effectName)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Marker

/// A marker in the timeline
public struct OTIOMarker: Sendable {
    public static let schemaName = "Marker.1"
    
    public let name: String
    public let markedRange: OTIOTimeRange
    public let color: String
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        markedRange: OTIOTimeRange,
        color: String = "RED",
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.markedRange = markedRange
        self.color = color
        self.metadata = metadata
    }
}

extension OTIOMarker: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case markedRange = "marked_range"
        case color
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encode(markedRange, forKey: .markedRange)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Track Item

/// An item in a track (clip, gap, or transition)
public enum OTIOTrackItem: Sendable {
    case clip(OTIOClip)
    case gap(OTIOGap)
    case transition(OTIOTransition)
}

extension OTIOTrackItem: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .clip(let clip):
            try clip.encode(to: encoder)
        case .gap(let gap):
            try gap.encode(to: encoder)
        case .transition(let transition):
            try transition.encode(to: encoder)
        }
    }
}

// MARK: - OTIO Track

/// A track in the timeline
public struct OTIOTrack: @unchecked Sendable {
    public static let schemaName = "Track.1"
    
    public let name: String
    public let kind: OTIOTrackKind
    public let children: [OTIOTrackItem]
    public let sourceRange: OTIOTimeRange?
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        kind: OTIOTrackKind = .video,
        children: [OTIOTrackItem] = [],
        sourceRange: OTIOTimeRange? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.kind = kind
        self.children = children
        self.sourceRange = sourceRange
        self.metadata = metadata
    }
}

extension OTIOTrack: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case kind
        case children
        case sourceRange = "source_range"
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(children, forKey: .children)
        try container.encodeIfPresent(sourceRange, forKey: .sourceRange)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Stack

/// A stack of tracks
public struct OTIOStack: Sendable {
    public static let schemaName = "Stack.1"
    
    public let name: String
    public let children: [OTIOTrack]
    public let sourceRange: OTIOTimeRange?
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        children: [OTIOTrack] = [],
        sourceRange: OTIOTimeRange? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.children = children
        self.sourceRange = sourceRange
        self.metadata = metadata
    }
}

extension OTIOStack: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case children
        case sourceRange = "source_range"
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encode(children, forKey: .children)
        try container.encodeIfPresent(sourceRange, forKey: .sourceRange)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Timeline

/// The root timeline object
public struct OTIOTimeline: Sendable {
    public static let schemaName = "Timeline.1"
    
    public let name: String
    public let tracks: OTIOStack
    public let globalStartTime: OTIORationalTime?
    public let metadata: [String: AnyCodable]?
    
    public init(
        name: String,
        tracks: OTIOStack,
        globalStartTime: OTIORationalTime? = nil,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.name = name
        self.tracks = tracks
        self.globalStartTime = globalStartTime
        self.metadata = metadata
    }
}

extension OTIOTimeline: Encodable {
    enum CodingKeys: String, CodingKey {
        case schemaName = "OTIO_SCHEMA"
        case name
        case tracks
        case globalStartTime = "global_start_time"
        case metadata
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaName, forKey: .schemaName)
        try container.encode(name, forKey: .name)
        try container.encode(tracks, forKey: .tracks)
        try container.encodeIfPresent(globalStartTime, forKey: .globalStartTime)
        try container.encodeIfPresent(metadata, forKey: .metadata)
    }
}

// MARK: - OTIO Exporter

/// Exports timelines to OpenTimelineIO format
public struct OTIOExporter {
    
    /// Frame rate for the timeline
    public let frameRate: Double
    
    /// Whether to include metadata
    public let includeMetadata: Bool
    
    public init(frameRate: Double = 24.0, includeMetadata: Bool = true) {
        self.frameRate = frameRate
        self.includeMetadata = includeMetadata
    }
    
    // MARK: - Export Methods
    
    /// Export timeline to OTIO JSON
    public func export(timeline: OTIOTimeline) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(timeline)
        guard let json = String(data: data, encoding: .utf8) else {
            throw OTIOError.encodingFailed
        }
        
        return json
    }
    
    /// Export timeline to file
    public func export(timeline: OTIOTimeline, to url: URL) throws {
        let content = try export(timeline: timeline)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Export from RenderManifest
    /// Note: RenderManifest doesn't contain timeline/assets data.
    /// For full timeline export, use export(timeline:) with OTIOTimeline directly.
    /// This method exports scene elements as placeholder clips for reference.
    public func export(from manifest: RenderManifest) throws -> String {
        var videoTracks: [OTIOTrack] = []
        
        // Build a single video track from scene elements
        var items: [OTIOTrackItem] = []
        var currentTime: Double = 0
        
        guard let elements = manifest.elements else {
            let emptyTimeline = OTIOTimeline(
                name: manifest.metadata.quality ?? "MetaVisRender Export",
                tracks: OTIOStack(name: "tracks", children: []),
                globalStartTime: OTIORationalTime(value: 0, rate: frameRate)
            )
            return try export(timeline: emptyTimeline)
        }
        for element in elements {
            let (name, source, duration) = extractElementInfo(element)
            
            // Create media reference
            let mediaRef: OTIOExternalReference?
            if let src = source {
                mediaRef = OTIOExternalReference(
                    targetURL: src,
                    availableRange: OTIOTimeRange(
                        start: 0,
                        duration: duration,
                        rate: frameRate
                    )
                )
            } else {
                mediaRef = nil
            }
            
            // Create clip
            let otioClip = OTIOClip(
                name: name,
                sourceRange: OTIOTimeRange(
                    start: 0,
                    duration: duration,
                    rate: frameRate
                ),
                mediaReference: mediaRef
            )
            items.append(.clip(otioClip))
            
            currentTime += duration
        }
        
        if !items.isEmpty {
            let otioTrack = OTIOTrack(
                name: "Video 1",
                kind: .video,
                children: items
            )
            videoTracks.append(otioTrack)
        }
        
        // Build stack with video tracks
        let stack = OTIOStack(
            name: "Tracks",
            children: videoTracks
        )
        
        // Build timeline
        let timelineName = manifest.metadata.quality ?? "MetaVisRender Export"
        let timeline = OTIOTimeline(
            name: timelineName,
            tracks: stack,
            globalStartTime: OTIORationalTime(value: 0, rate: frameRate),
            metadata: includeMetadata ? buildTimelineMetadata(manifest) : nil
        )
        
        return try export(timeline: timeline)
    }
    
    // MARK: - Private Methods
    
    private func extractElementInfo(_ element: ManifestElement) -> (name: String, source: String?, duration: Double) {
        switch element {
        case .text(let textElement):
            let name = textElement.content
            let duration = textElement.duration > 0 ? Double(textElement.duration) : 10.0
            return (name, nil, duration)
        case .model(let modelElement):
            let name = URL(fileURLWithPath: modelElement.path).deletingPathExtension().lastPathComponent
            let source = modelElement.path
            return (name, source, 10.0) // Default duration for models
        }
    }
    
    private func buildTimelineMetadata(_ manifest: RenderManifest) -> [String: AnyCodable]? {
        var metadata: [String: AnyCodable] = [:]
        
        metadata["generator"] = AnyCodable("MetaVisRender")
        metadata["fps"] = AnyCodable(manifest.metadata.fps)
        metadata["duration"] = AnyCodable(manifest.metadata.duration)
        metadata["width"] = AnyCodable(manifest.metadata.resolution.x)
        metadata["height"] = AnyCodable(manifest.metadata.resolution.y)
        
        if let quality = manifest.metadata.quality {
            metadata["quality"] = AnyCodable(quality)
        }
        
        return metadata
    }
}

// MARK: - OTIO Error

public enum OTIOError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed(String)
    case invalidFormat
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode OTIO"
        case .decodingFailed(let message):
            return "Failed to decode OTIO: \(message)"
        case .invalidFormat:
            return "Invalid OTIO format"
        }
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for metadata
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

extension AnyCodable: @unchecked Sendable {}
