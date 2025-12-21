// TimelineModel+Validation.swift
// MetaVisRender
//
// Created for Sprint 3: Manifest Unification
// Enhanced validation logic for TimelineModel

import Foundation
import simd

// MARK: - TimelineValidationError

/// Errors that can occur during timeline validation.
public enum TimelineValidationError: Error, Equatable, Sendable {
    case overlappingClips(ClipID, ClipID)
    case invalidClipReference(ClipID)
    case invalidSourceReference(String)
    case invalidTimeRange
    case negativeDuration(ClipID)
    case sourceNotFound(String)
    
    // Enhanced validation errors
    case invalidFPS(Double)
    case invalidResolution(SIMD2<Int>)
    case invalidDuration(Double)
    case invalidFOV(Float)
    case cameraNaN
    case invalidSourceRange(ClipID, String)
}

extension TimelineValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .overlappingClips(let a, let b):
            return "Clips \(a) and \(b) overlap on the same track"
        case .invalidClipReference(let id):
            return "Invalid clip reference: \(id)"
        case .invalidSourceReference(let source):
            return "Invalid source reference: \(source)"
        case .invalidTimeRange:
            return "Invalid time range"
        case .negativeDuration(let id):
            return "Clip \(id) has negative duration"
        case .sourceNotFound(let source):
            return "Source not found: \(source)"
        case .invalidFPS(let fps):
            return "FPS must be in range (0, 240], got \(fps)"
        case .invalidResolution(let res):
            return "Resolution must be positive, got \(res.x)x\(res.y)"
        case .invalidDuration(let duration):
            return "Duration must be non-negative, got \(duration)"
        case .invalidFOV(let fov):
            return "Camera FOV must be in range (0, 180), got \(fov)"
        case .cameraNaN:
            return "Camera properties contain NaN values"
        case .invalidSourceRange(let clipId, let sourceId):
            return "Clip \(clipId) uses invalid range for source \(sourceId)"
        }
    }
}

// MARK: - Validation Extension

extension TimelineModel {
    
    /// Validates the timeline structure for common errors and strict constraints.
    /// - Returns: An array of validation errors. If empty, the timeline is valid.
    public func validate() -> [TimelineValidationError] {
        var errors: [TimelineValidationError] = []
        
        // 1. Validate Metadata
        if fps <= 0 || fps > 240 {
            errors.append(.invalidFPS(fps))
        }
        if resolution.x <= 0 || resolution.y <= 0 {
            errors.append(.invalidResolution(resolution))
        }
        // Note: Duration is computed, but if explicitDuration is set, check it
        if let explicit = explicitDuration, explicit < 0 {
            errors.append(.invalidDuration(explicit))
        }
        
        // 2. Validate Camera (if present)
        if let camera = camera {
            if camera.fov <= 0 || camera.fov >= 180 {
                errors.append(.invalidFOV(camera.fov))
            }
            if camera.position.x.isNaN || camera.position.y.isNaN || camera.position.z.isNaN ||
               camera.target.x.isNaN || camera.target.y.isNaN || camera.target.z.isNaN {
                errors.append(.cameraNaN)
            }
        }
        
        // 3. Validate Tracks & Clips
        for track in videoTracks {
            // Check for overlapping clips on same track
            let sortedClips = track.clips.sorted { $0.timelineIn < $1.timelineIn }
            for i in 0..<sortedClips.count {
                let current = sortedClips[i]
                
                // Check clip duration
                if current.duration <= 0 {
                    errors.append(.negativeDuration(current.id))
                }
                
                // Check source reference
                if let sourceInfo = sources[current.source] {
                    // Check if clip range is valid for source (if source duration is known)
                    if let sourceDuration = sourceInfo.duration {
                        if current.sourceOut > sourceDuration {
                            errors.append(.invalidSourceRange(current.id, current.source))
                        }
                    }
                } else {
                    errors.append(.invalidSourceReference(current.source))
                }
                
                // Check overlap with next clip
                if i < sortedClips.count - 1 {
                    let next = sortedClips[i + 1]
                    let currentEnd = current.timelineIn + current.duration
                    // Use a small epsilon for floating point comparison
                    if currentEnd > next.timelineIn + 0.0001 {
                        errors.append(.overlappingClips(current.id, next.id))
                    }
                }
            }
        }
        
        // 4. Validate Transitions
        for transition in transitions {
            if clip(id: transition.fromClip) == nil {
                errors.append(.invalidClipReference(transition.fromClip))
            }
            if clip(id: transition.toClip) == nil {
                errors.append(.invalidClipReference(transition.toClip))
            }
            // TODO: Validate transition duration fits within clip handles
        }
        
        return errors
    }
}
