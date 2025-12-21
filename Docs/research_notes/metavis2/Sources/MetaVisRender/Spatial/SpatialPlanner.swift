// SpatialPlanner.swift
// MetaVisRender
//
// Created for Sprint 07: Spatial Audio
// Maps visual face positions to 3D audio coordinates

import Foundation
import CoreMedia
import CoreGraphics
import simd

// MARK: - Spatial Planner

/// Maps visual face positions to 3D audio positions
/// Face position in video → spatial audio coordinates
public actor SpatialPlanner {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Horizontal field mapping range
        public let azimuthRange: ClosedRange<Float>
        
        /// Vertical field mapping range
        public let elevationRange: ClosedRange<Float>
        
        /// Distance estimation range
        public let distanceRange: ClosedRange<Float>
        
        /// Reference face width for distance = 1m
        public let referenceFaceWidth: Float
        
        /// Smoothing factor for position changes (0-1, higher = smoother)
        public let smoothingFactor: Float
        
        /// Whether to invert Y axis (Vision framework has origin at bottom-left)
        public let invertY: Bool
        
        public init(
            azimuthRange: ClosedRange<Float> = -90...90,
            elevationRange: ClosedRange<Float> = -30...30,
            distanceRange: ClosedRange<Float> = 0.5...10,
            referenceFaceWidth: Float = 0.15,
            smoothingFactor: Float = 0.3,
            invertY: Bool = true
        ) {
            self.azimuthRange = azimuthRange
            self.elevationRange = elevationRange
            self.distanceRange = distanceRange
            self.referenceFaceWidth = referenceFaceWidth
            self.smoothingFactor = smoothingFactor
            self.invertY = invertY
        }
        
        public static let `default` = Config()
        
        /// Interview setup - narrower field, closer distances
        public static let interview = Config(
            azimuthRange: -60...60,
            elevationRange: -15...15,
            distanceRange: 1...4,
            smoothingFactor: 0.4
        )
        
        /// Wide shot - full field
        public static let wideShot = Config(
            azimuthRange: -90...90,
            elevationRange: -30...30,
            distanceRange: 2...10,
            smoothingFactor: 0.2
        )
    }
    
    private let config: Config
    
    /// Cache of previous positions for smoothing (keyed by person ID)
    private var positionCache: [UUID: SpatialPosition] = [:]
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Position Mapping
    
    /// Compute spatial position from face bounding box
    /// - Parameters:
    ///   - boundingBox: Normalized face bounding box (0-1 coordinates)
    ///   - frameTime: Time of this frame
    ///   - personId: Optional person ID for smoothing
    public func position(
        for boundingBox: CGRect,
        at frameTime: Double,
        personId: UUID? = nil
    ) -> SpatialPosition {
        // Calculate center point
        let centerX = Float(boundingBox.midX)
        var centerY = Float(boundingBox.midY)
        
        // Invert Y if needed (Vision has origin at bottom-left)
        if config.invertY {
            centerY = 1.0 - centerY
        }
        
        let faceWidth = Float(boundingBox.width)
        
        // Map X position to azimuth (left = negative, right = positive)
        let azimuth = mapToRange(
            value: centerX,
            from: 0...1,
            to: config.azimuthRange
        )
        
        // Map Y position to elevation (top = positive, bottom = negative)
        let elevation = mapToRange(
            value: 1.0 - centerY,  // Flip so top is positive
            from: 0...1,
            to: config.elevationRange
        )
        
        // Estimate distance from face size
        let distance = estimateDistance(faceWidth: faceWidth)
        
        let rawPosition = SpatialPosition(
            azimuth: azimuth,
            elevation: elevation,
            distance: distance,
            time: CMTime(seconds: frameTime, preferredTimescale: 600)
        )
        
        // Apply smoothing if we have a person ID
        if let personId = personId {
            return smoothedPosition(raw: rawPosition, personId: personId)
        }
        
        return rawPosition
    }
    
    /// Convenience overload for FaceObservation-like input
    public func position(
        boundingBox: CGRect,
        confidence: Float,
        frameTime: Double,
        personId: UUID? = nil
    ) -> SpatialPosition {
        return position(for: boundingBox, at: frameTime, personId: personId)
    }
    
    // MARK: - Timeline Generation
    
    /// Generate position timeline from face observations
    public func positionTimeline(
        observations: [(boundingBox: CGRect, time: Double, personId: UUID)]
    ) -> [SpatialPosition] {
        // Group by person and sort by time
        let sorted = observations.sorted { $0.time < $1.time }
        
        return sorted.map { obs in
            position(for: obs.boundingBox, at: obs.time, personId: obs.personId)
        }
    }
    
    /// Create spatial audio timeline from person tracking data
    public func createTimeline(
        from personTracks: [(personId: UUID, observations: [(boundingBox: CGRect, time: Double)])]
    ) -> SpatialAudioTimeline {
        var timeline = SpatialAudioTimeline()
        
        for track in personTracks {
            let positions = track.observations.map { obs in
                position(for: obs.boundingBox, at: obs.time, personId: track.personId)
            }
            timeline.addTrack(personId: track.personId, positions: positions)
        }
        
        return timeline
    }
    
    /// Create speaker placements from diarization and face linking
    public func createSpeakerPlacements(
        speakerIds: [String],
        personMappings: [String: UUID],  // speakerId -> personId
        personTracks: [UUID: [(boundingBox: CGRect, time: Double)]]
    ) -> [SpeakerPlacement] {
        var placements: [SpeakerPlacement] = []
        
        for speakerId in speakerIds {
            guard let personId = personMappings[speakerId],
                  let observations = personTracks[personId] else {
                // Speaker without face tracking - use default position
                placements.append(SpeakerPlacement(
                    speakerId: speakerId,
                    personId: nil,
                    timeline: [SpatialPosition(
                        azimuth: 0,
                        elevation: 0,
                        distance: SpatialAudioDefaults.defaultDistance,
                        time: .zero
                    )]
                ))
                continue
            }
            
            let positions = observations.map { obs in
                position(for: obs.boundingBox, at: obs.time, personId: personId)
            }
            
            placements.append(SpeakerPlacement(
                speakerId: speakerId,
                personId: personId,
                timeline: positions
            ))
        }
        
        return placements
    }
    
    /// Reset smoothing cache
    public func reset() {
        positionCache.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func mapToRange(
        value: Float,
        from inputRange: ClosedRange<Float>,
        to outputRange: ClosedRange<Float>
    ) -> Float {
        let normalizedValue = (value - inputRange.lowerBound) / (inputRange.upperBound - inputRange.lowerBound)
        return outputRange.lowerBound + normalizedValue * (outputRange.upperBound - outputRange.lowerBound)
    }
    
    private func estimateDistance(faceWidth: Float) -> Float {
        // Inverse relationship: larger face = closer
        // Reference: face width of 0.15 (15% of frame) = 1m distance
        guard faceWidth > 0 else { return config.distanceRange.upperBound }
        
        let ratio = config.referenceFaceWidth / faceWidth
        let distance = ratio * config.distanceRange.lowerBound
        
        return min(max(distance, config.distanceRange.lowerBound), config.distanceRange.upperBound)
    }
    
    private func smoothedPosition(raw: SpatialPosition, personId: UUID) -> SpatialPosition {
        guard let previous = positionCache[personId] else {
            positionCache[personId] = raw
            return raw
        }
        
        // Exponential moving average
        let alpha = config.smoothingFactor
        
        let smoothedAzimuth = previous.azimuth * alpha + raw.azimuth * (1 - alpha)
        let smoothedElevation = previous.elevation * alpha + raw.elevation * (1 - alpha)
        let smoothedDistance = previous.distance * alpha + raw.distance * (1 - alpha)
        
        let smoothed = SpatialPosition(
            azimuth: smoothedAzimuth,
            elevation: smoothedElevation,
            distance: smoothedDistance,
            time: raw.time
        )
        
        positionCache[personId] = smoothed
        return smoothed
    }
}

// MARK: - Position Mapping Utilities

extension SpatialPlanner {
    
    /// Quick position calculation for a single face at center
    public static func centerPosition(distance: Float = 2.0) -> SpatialPosition {
        SpatialPosition(azimuth: 0, elevation: 0, distance: distance, time: .zero)
    }
    
    /// Calculate azimuth from normalized X position
    public static func azimuth(fromNormalizedX x: Float, range: ClosedRange<Float> = -90...90) -> Float {
        let centered = x - 0.5  // -0.5 to 0.5
        return centered * (range.upperBound - range.lowerBound)
    }
    
    /// Calculate elevation from normalized Y position
    public static func elevation(fromNormalizedY y: Float, range: ClosedRange<Float> = -30...30) -> Float {
        let centered = (1.0 - y) - 0.5  // Flip Y, center
        return centered * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Shot Type Detection

/// Shot type for distance estimation in spatial audio
public enum SpatialShotType: String, Sendable {
    case closeUp = "close_up"
    case medium = "medium"
    case wide = "wide"
    case extreme = "extreme"
    
    /// Typical audio distance for this shot type
    public var typicalDistance: Float {
        switch self {
        case .closeUp: return 1.0
        case .medium: return 2.0
        case .wide: return 4.0
        case .extreme: return 8.0
        }
    }
    
    /// Detect shot type from face bounding box
    public static func detect(from faceBox: CGRect) -> SpatialShotType {
        let faceHeight = Float(faceBox.height)
        
        if faceHeight > 0.5 {
            return .closeUp
        } else if faceHeight > 0.25 {
            return .medium
        } else if faceHeight > 0.1 {
            return .wide
        } else {
            return .extreme
        }
    }
}
