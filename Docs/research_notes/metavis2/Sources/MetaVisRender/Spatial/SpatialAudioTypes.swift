// SpatialAudioTypes.swift
// MetaVisRender
//
// Created for Sprint 07: Spatial Audio
// Core data types for 3D audio positioning and mixing

import Foundation
import CoreMedia
import simd

// MARK: - Spatial Position

/// A position in 3D audio space using spherical coordinates
public struct SpatialPosition: Codable, Sendable, Equatable {
    /// Horizontal angle from center (-180° to +180°, 0 = front, negative = left)
    public let azimuth: Float
    
    /// Vertical angle from ear level (-90° to +90°, positive = up)
    public let elevation: Float
    
    /// Distance from listener in meters (0.5 to 10)
    public let distance: Float
    
    /// Timestamp for this position
    public let time: CMTime
    
    public init(
        azimuth: Float,
        elevation: Float,
        distance: Float,
        time: CMTime = .zero
    ) {
        self.azimuth = azimuth.clamped(to: -180...180)
        self.elevation = elevation.clamped(to: -90...90)
        self.distance = distance.clamped(to: SpatialAudioDefaults.minDistance...SpatialAudioDefaults.maxDistance)
        self.time = time
    }
    
    /// Convert to Cartesian coordinates for AVAudio3DPoint
    /// X = right, Y = up, Z = back (negative Z = forward)
    public func toCartesian() -> SIMD3<Float> {
        let azimuthRad = azimuth * .pi / 180.0
        let elevationRad = elevation * .pi / 180.0
        
        let cosElevation = cos(elevationRad)
        
        let x = distance * sin(azimuthRad) * cosElevation
        let y = distance * sin(elevationRad)
        let z = -distance * cos(azimuthRad) * cosElevation
        
        return SIMD3<Float>(x, y, z)
    }
    
    /// Linear interpolation between positions
    public static func interpolate(from a: SpatialPosition, to b: SpatialPosition, t: Float) -> SpatialPosition {
        let t = t.clamped(to: 0...1)
        
        return SpatialPosition(
            azimuth: a.azimuth + (b.azimuth - a.azimuth) * t,
            elevation: a.elevation + (b.elevation - a.elevation) * t,
            distance: a.distance + (b.distance - a.distance) * t,
            time: CMTime(
                seconds: a.time.seconds + (b.time.seconds - a.time.seconds) * Double(t),
                preferredTimescale: 600
            )
        )
    }
    
    // MARK: - Codable for CMTime
    
    enum CodingKeys: String, CodingKey {
        case azimuth, elevation, distance, timeSeconds
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        azimuth = try container.decode(Float.self, forKey: .azimuth)
        elevation = try container.decode(Float.self, forKey: .elevation)
        distance = try container.decode(Float.self, forKey: .distance)
        let timeSeconds = try container.decode(Double.self, forKey: .timeSeconds)
        time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(azimuth, forKey: .azimuth)
        try container.encode(elevation, forKey: .elevation)
        try container.encode(distance, forKey: .distance)
        try container.encode(time.seconds, forKey: .timeSeconds)
    }
}

// MARK: - Spatial Mix Parameters

/// Complete spatial mix configuration
public struct SpatialMixParams: Codable, Sendable {
    /// Output audio format
    public let outputFormat: SpatialAudioFormat
    
    /// Rendering mode (channel-based, binaural, etc.)
    public let renderingMode: SpatialRenderingMode
    
    /// Speaker placements over time
    public let speakerPlacements: [SpeakerPlacement]
    
    /// Room reverb setting
    public let environmentReverb: ReverbPreset
    
    /// Listener position and orientation
    public let listenerPosition: ListenerPosition
    
    public init(
        outputFormat: SpatialAudioFormat = .stereo,
        renderingMode: SpatialRenderingMode = .channelBased,
        speakerPlacements: [SpeakerPlacement] = [],
        environmentReverb: ReverbPreset = .mediumRoom,
        listenerPosition: ListenerPosition = .default
    ) {
        self.outputFormat = outputFormat
        self.renderingMode = renderingMode
        self.speakerPlacements = speakerPlacements
        self.environmentReverb = environmentReverb
        self.listenerPosition = listenerPosition
    }
}

// MARK: - Audio Format

/// Output audio format
public enum SpatialAudioFormat: String, Codable, Sendable, CaseIterable {
    case mono = "mono"
    case stereo = "stereo"
    case surround5_1 = "5.1"
    case surround7_1 = "7.1"
    case atmos = "atmos"
    
    public var channelCount: Int {
        switch self {
        case .mono: return 1
        case .stereo: return 2
        case .surround5_1: return 6
        case .surround7_1: return 8
        case .atmos: return 12  // 7.1.4 bed
        }
    }
    
    public var displayName: String {
        switch self {
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        case .surround5_1: return "5.1 Surround"
        case .surround7_1: return "7.1 Surround"
        case .atmos: return "Dolby Atmos"
        }
    }
}

// MARK: - Rendering Mode

/// How spatial audio is rendered
public enum SpatialRenderingMode: String, Codable, Sendable {
    /// Traditional channel-based output (5.1/7.1 speakers)
    case channelBased = "channel_based"
    
    /// Binaural for headphones with HRTF
    case binaural = "binaural"
    
    /// First-order ambisonics
    case ambisonic = "ambisonic"
}

// MARK: - Speaker Placement

/// A speaker's position over time
public struct SpeakerPlacement: Codable, Sendable, Identifiable {
    public let id: UUID
    
    /// Speaker ID from diarization
    public let speakerId: String
    
    /// Linked person ID from PersonIntelligence
    public let personId: UUID?
    
    /// Position timeline
    public let timeline: [SpatialPosition]
    
    /// Base volume (0-1)
    public let volume: Float
    
    /// Reverb send amount (0-1)
    public let reverbSend: Float
    
    public init(
        id: UUID = UUID(),
        speakerId: String,
        personId: UUID? = nil,
        timeline: [SpatialPosition] = [],
        volume: Float = 1.0,
        reverbSend: Float = 0.2
    ) {
        self.id = id
        self.speakerId = speakerId
        self.personId = personId
        self.timeline = timeline
        self.volume = volume.clamped(to: 0...1)
        self.reverbSend = reverbSend.clamped(to: 0...1)
    }
    
    /// Get interpolated position at time
    public func position(at time: CMTime) -> SpatialPosition? {
        guard !timeline.isEmpty else { return nil }
        
        // Before first keyframe
        if time <= timeline.first!.time {
            return timeline.first
        }
        
        // After last keyframe
        if time >= timeline.last!.time {
            return timeline.last
        }
        
        // Find surrounding keyframes
        for i in 0..<timeline.count - 1 {
            let current = timeline[i]
            let next = timeline[i + 1]
            
            if time >= current.time && time <= next.time {
                let duration = next.time.seconds - current.time.seconds
                guard duration > 0 else { return current }
                
                let t = Float((time.seconds - current.time.seconds) / duration)
                return SpatialPosition.interpolate(from: current, to: next, t: t)
            }
        }
        
        return timeline.last
    }
}

// MARK: - Reverb Preset

/// Room reverb characteristics
public enum ReverbPreset: String, Codable, Sendable, CaseIterable {
    case none = "none"
    case smallRoom = "small_room"
    case mediumRoom = "medium_room"
    case largeRoom = "large_room"
    case cathedral = "cathedral"
    case outdoor = "outdoor"
    
    /// AVAudioUnitReverb preset mapping
    public var reverbPresetValue: Int {
        switch self {
        case .none: return 0
        case .smallRoom: return 1
        case .mediumRoom: return 2
        case .largeRoom: return 3
        case .cathedral: return 4
        case .outdoor: return 5
        }
    }
    
    /// Wet/dry mix (0-100)
    public var wetDryMix: Float {
        switch self {
        case .none: return 0
        case .smallRoom: return 15
        case .mediumRoom: return 25
        case .largeRoom: return 35
        case .cathedral: return 50
        case .outdoor: return 20
        }
    }
}

// MARK: - Listener Position

/// Position and orientation of the listener
public struct ListenerPosition: Codable, Sendable, Equatable {
    /// Position in 3D space
    public let position: SIMD3<Float>
    
    /// Forward direction vector
    public let forward: SIMD3<Float>
    
    /// Up direction vector
    public let up: SIMD3<Float>
    
    public init(
        position: SIMD3<Float> = .zero,
        forward: SIMD3<Float> = SIMD3<Float>(0, 0, -1),
        up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)
    ) {
        self.position = position
        self.forward = forward
        self.up = up
    }
    
    /// Default listener at origin, facing forward
    public static let `default` = ListenerPosition()
}

// MARK: - Spatial Audio Timeline

/// Timeline of spatial positions for multiple sources
public struct SpatialAudioTimeline: Sendable {
    /// Tracks by person/speaker ID
    public private(set) var tracks: [UUID: [SpatialPosition]]
    
    /// Total duration
    public let duration: CMTime
    
    public init(duration: CMTime = .zero) {
        self.tracks = [:]
        self.duration = duration
    }
    
    public var trackCount: Int { tracks.count }
    
    /// Add a position track for a person
    public mutating func addTrack(personId: UUID, positions: [SpatialPosition]) {
        tracks[personId] = positions.sorted { $0.time < $1.time }
    }
    
    /// Get positions for a person
    public func positions(for personId: UUID) -> [SpatialPosition] {
        tracks[personId] ?? []
    }
    
    /// Get position at specific time for a person
    public func position(for personId: UUID, at time: CMTime) -> SpatialPosition? {
        let positions = self.positions(for: personId)
        guard !positions.isEmpty else { return nil }
        
        // Before first
        if time <= positions.first!.time {
            return positions.first
        }
        
        // After last
        if time >= positions.last!.time {
            return positions.last
        }
        
        // Interpolate
        for i in 0..<positions.count - 1 {
            let current = positions[i]
            let next = positions[i + 1]
            
            if time >= current.time && time <= next.time {
                let duration = next.time.seconds - current.time.seconds
                guard duration > 0 else { return current }
                
                let t = Float((time.seconds - current.time.seconds) / duration)
                return SpatialPosition.interpolate(from: current, to: next, t: t)
            }
        }
        
        return positions.last
    }
    
    /// Chunk timeline into segments for processing
    public func chunks(duration chunkDuration: Double) -> [TimelineChunk] {
        var chunks: [TimelineChunk] = []
        var currentTime = 0.0
        let totalDuration = self.duration.seconds
        
        while currentTime < totalDuration {
            let endTime = min(currentTime + chunkDuration, totalDuration)
            let startCMTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            let endCMTime = CMTime(seconds: endTime, preferredTimescale: 600)
            
            var chunkPositions: [UUID: [SpatialPosition]] = [:]
            
            for (personId, positions) in tracks {
                let inRange = positions.filter { 
                    $0.time >= startCMTime && $0.time < endCMTime 
                }
                if !inRange.isEmpty {
                    chunkPositions[personId] = inRange
                }
            }
            
            chunks.append(TimelineChunk(
                startTime: startCMTime,
                endTime: endCMTime,
                positions: chunkPositions
            ))
            
            currentTime = endTime
        }
        
        return chunks
    }
}

/// A chunk of the timeline for batch processing
public struct TimelineChunk: Sendable {
    public let startTime: CMTime
    public let endTime: CMTime
    public let positions: [UUID: [SpatialPosition]]
    
    public var duration: Double {
        endTime.seconds - startTime.seconds
    }
}

// MARK: - Export Format

/// Audio export format specification
public struct SpatialExportFormat: Codable, Sendable {
    public let channelLayout: SpatialAudioFormat
    public let sampleRate: Int
    public let bitDepth: Int
    public let codec: SpatialAudioCodec
    
    public init(
        channelLayout: SpatialAudioFormat = .stereo,
        sampleRate: Int = 48000,
        bitDepth: Int = 24,
        codec: SpatialAudioCodec = .lpcm
    ) {
        self.channelLayout = channelLayout
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.codec = codec
    }
    
    public static let stereoAAC = SpatialExportFormat(
        channelLayout: .stereo,
        sampleRate: 48000,
        bitDepth: 16,
        codec: .aac
    )
    
    public static let surround51LPCM = SpatialExportFormat(
        channelLayout: .surround5_1,
        sampleRate: 48000,
        bitDepth: 24,
        codec: .lpcm
    )
    
    public static let surround71LPCM = SpatialExportFormat(
        channelLayout: .surround7_1,
        sampleRate: 48000,
        bitDepth: 24,
        codec: .lpcm
    )
}

/// Audio codec
public enum SpatialAudioCodec: String, Codable, Sendable {
    case lpcm = "lpcm"
    case aac = "aac"
    case ac3 = "ac3"
    case flac = "flac"
}

// MARK: - Spatial Preset

/// Pre-configured spatial settings for common use cases
public enum SpatialPreset: String, Codable, Sendable, CaseIterable {
    case youtube = "youtube"
    case cinema = "cinema"
    case podcast = "podcast"
    case homeTheater = "home_theater"
    case headphones = "headphones"
    
    public var config: SpatialMixParams {
        switch self {
        case .youtube:
            return SpatialMixParams(
                outputFormat: .stereo,
                renderingMode: .binaural,
                environmentReverb: .smallRoom
            )
        case .cinema:
            return SpatialMixParams(
                outputFormat: .surround5_1,
                renderingMode: .channelBased,
                environmentReverb: .largeRoom
            )
        case .podcast:
            return SpatialMixParams(
                outputFormat: .stereo,
                renderingMode: .channelBased,
                environmentReverb: .smallRoom
            )
        case .homeTheater:
            return SpatialMixParams(
                outputFormat: .surround7_1,
                renderingMode: .channelBased,
                environmentReverb: .mediumRoom
            )
        case .headphones:
            return SpatialMixParams(
                outputFormat: .stereo,
                renderingMode: .binaural,
                environmentReverb: .none
            )
        }
    }
    
    public var exportFormat: SpatialExportFormat {
        switch self {
        case .youtube:
            return .stereoAAC
        case .cinema:
            return .surround51LPCM
        case .podcast:
            return .stereoAAC
        case .homeTheater:
            return .surround71LPCM
        case .headphones:
            return .stereoAAC
        }
    }
}

// MARK: - Defaults

/// Default values for spatial audio
public enum SpatialAudioDefaults {
    public static let defaultDistance: Float = 2.0
    public static let minDistance: Float = 0.5
    public static let maxDistance: Float = 10.0
    public static let smoothingFactor: Float = 0.3
    public static let defaultReverbSend: Float = 0.2
    public static let defaultAzimuthRange: ClosedRange<Float> = -90...90
    public static let defaultElevationRange: ClosedRange<Float> = -30...30
    public static let referenceFaceWidth: Float = 0.15
}

// MARK: - Channel Mapping

/// 5.1 channel positions
public enum SurroundChannel51: Int, CaseIterable {
    case left = 0           // L  @ -30°
    case right = 1          // R  @ +30°
    case center = 2         // C  @ 0°
    case lfe = 3            // LFE (subwoofer)
    case leftSurround = 4   // Ls @ -110°
    case rightSurround = 5  // Rs @ +110°
    
    public var azimuth: Float {
        switch self {
        case .left: return -30
        case .right: return 30
        case .center: return 0
        case .lfe: return 0
        case .leftSurround: return -110
        case .rightSurround: return 110
        }
    }
}

/// 7.1 additional channels
public enum SurroundChannel71: Int, CaseIterable {
    case left = 0
    case right = 1
    case center = 2
    case lfe = 3
    case leftSurround = 4
    case rightSurround = 5
    case leftSide = 6       // Lss @ -90°
    case rightSide = 7      // Rss @ +90°
    
    public var azimuth: Float {
        switch self {
        case .left: return -30
        case .right: return 30
        case .center: return 0
        case .lfe: return 0
        case .leftSurround: return -135
        case .rightSurround: return 135
        case .leftSide: return -90
        case .rightSide: return 90
        }
    }
}

// MARK: - Spatial Audio Result

/// Result of spatial audio processing
public struct SpatialAudioResult: Sendable {
    public let outputURL: URL
    public let format: SpatialExportFormat
    public let duration: Double
    public let sourceCount: Int
    public let processingTime: Double
    
    public init(
        outputURL: URL,
        format: SpatialExportFormat,
        duration: Double,
        sourceCount: Int,
        processingTime: Double
    ) {
        self.outputURL = outputURL
        self.format = format
        self.duration = duration
        self.sourceCount = sourceCount
        self.processingTime = processingTime
    }
}
