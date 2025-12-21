// Sources/MetaVisRender/Ingestion/AI/TextPlacementSuggester.swift
// Sprint 03: Smart text placement based on video analysis

import Foundation
import simd
import CoreGraphics

// MARK: - Text Placement Suggester

/// Suggests optimal text positions based on saliency, faces, and safe zones
public actor TextPlacementSuggester {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Minimum margin from frame edges (normalized)
        public let edgeMargin: Float
        /// Minimum distance from detected faces (normalized)
        public let faceMargin: Float
        /// Minimum distance from salient regions (normalized)
        public let saliencyMargin: Float
        /// Weight for preferring lower-third positioning
        public let lowerThirdBias: Float
        /// Minimum confidence to accept a placement
        public let minConfidence: Float
        
        public init(
            edgeMargin: Float = 0.05,
            faceMargin: Float = 0.1,
            saliencyMargin: Float = 0.08,
            lowerThirdBias: Float = 0.3,
            minConfidence: Float = 0.5
        ) {
            self.edgeMargin = edgeMargin
            self.faceMargin = faceMargin
            self.saliencyMargin = saliencyMargin
            self.lowerThirdBias = lowerThirdBias
            self.minConfidence = minConfidence
        }
        
        public static let `default` = Config()
        
        public static let conservative = Config(
            edgeMargin: 0.1,
            faceMargin: 0.15,
            saliencyMargin: 0.12,
            minConfidence: 0.7
        )
        
        public static let aggressive = Config(
            edgeMargin: 0.03,
            faceMargin: 0.05,
            saliencyMargin: 0.04,
            minConfidence: 0.3
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Suggest placements for text content based on frame analysis
    public func suggestPlacements(
        content: [String],
        frameAnalysis: FramePlacementAnalysis,
        preferences: PlacementPreferences = .default
    ) async throws -> [PlacementSuggestion] {
        var suggestions: [PlacementSuggestion] = []
        
        // Find safe zones in the frame
        let safeZones = findSafeZones(
            frameSize: frameAnalysis.frameSize,
            faces: frameAnalysis.faces,
            saliencyRegions: frameAnalysis.saliencyRegions
        )
        
        for (index, text) in content.enumerated() {
            let suggestion = findOptimalPlacement(
                for: text,
                in: safeZones,
                preferences: preferences,
                existingPlacements: suggestions,
                index: index
            )
            suggestions.append(suggestion)
        }
        
        return suggestions
    }
    
    /// Suggest lower third placements for identified speakers
    public func suggestLowerThirds(
        speakers: [SpeakerPlacementInfo],
        frameAnalysis: FramePlacementAnalysis
    ) async throws -> [LowerThirdSuggestion] {
        var suggestions: [LowerThirdSuggestion] = []
        
        let safeZones = findSafeZones(
            frameSize: frameAnalysis.frameSize,
            faces: frameAnalysis.faces,
            saliencyRegions: frameAnalysis.saliencyRegions
        )
        
        // Find zones suitable for lower thirds (bottom portion)
        let lowerThirdZones = safeZones.filter { zone in
            zone.bounds.origin.y > 0.6
        }
        
        for speaker in speakers {
            let suggestion = suggestLowerThirdForSpeaker(
                speaker: speaker,
                zones: lowerThirdZones.isEmpty ? safeZones : lowerThirdZones,
                faces: frameAnalysis.faces
            )
            suggestions.append(suggestion)
        }
        
        return suggestions
    }
    
    /// Suggest title card placement
    public func suggestTitleCard(
        title: String,
        subtitle: String?,
        frameAnalysis: FramePlacementAnalysis,
        duration: Double = 3.0
    ) async throws -> TitleCardSuggestion {
        let safeZones = findSafeZones(
            frameSize: frameAnalysis.frameSize,
            faces: frameAnalysis.faces,
            saliencyRegions: frameAnalysis.saliencyRegions
        )
        
        // Find best zone for title (prefer center, upper-center, or lower-center)
        let titleZone = findBestTitleZone(zones: safeZones, faces: frameAnalysis.faces)
        
        let titlePosition = SIMD3<Float>(
            Float(titleZone.bounds.midX),
            Float(titleZone.bounds.midY),
            0.0
        )
        
        var subtitlePosition: SIMD3<Float>?
        if subtitle != nil {
            subtitlePosition = SIMD3<Float>(
                titlePosition.x,
                titlePosition.y + 0.1,  // Below title
                0.0
            )
        }
        
        return TitleCardSuggestion(
            title: title,
            titlePosition: titlePosition,
            subtitle: subtitle,
            subtitlePosition: subtitlePosition,
            anchor: .center,
            showAt: 0.5,  // Slight delay
            duration: duration,
            confidence: titleZone.confidence,
            reason: "Placed in \(titleZone.type.rawValue) zone"
        )
    }
    
    /// Find optimal position for a single text element
    public func suggestPosition(
        for content: String,
        in frameAnalysis: FramePlacementAnalysis,
        anchor: TextAnchor = .bottomLeft,
        estimatedSize: CGSize? = nil
    ) async throws -> PlacementSuggestion {
        let safeZones = findSafeZones(
            frameSize: frameAnalysis.frameSize,
            faces: frameAnalysis.faces,
            saliencyRegions: frameAnalysis.saliencyRegions
        )
        
        let preferences = PlacementPreferences(
            preferredAnchor: anchor,
            preferredVerticalRegion: anchor.isBottom ? .lower : anchor.isTop ? .upper : .center,
            preferredHorizontalRegion: anchor.isLeft ? .left : anchor.isRight ? .right : .center
        )
        
        return findOptimalPlacement(
            for: content,
            in: safeZones,
            preferences: preferences,
            existingPlacements: [],
            index: 0
        )
    }
    
    // MARK: - Safe Zone Detection
    
    private func findSafeZones(
        frameSize: SIMD2<Int>,
        faces: [PlacementFaceRegion],
        saliencyRegions: [PlacementSaliencyRegion]
    ) -> [SafePlacementZone] {
        var zones: [SafePlacementZone] = []
        
        // Define candidate regions (in normalized coordinates)
        let candidateRegions: [(CGRect, SafeZoneType)] = [
            // Lower thirds
            (CGRect(x: 0.05, y: 0.70, width: 0.4, height: 0.25), .lowerThirdLeft),
            (CGRect(x: 0.55, y: 0.70, width: 0.4, height: 0.25), .lowerThirdRight),
            (CGRect(x: 0.15, y: 0.75, width: 0.7, height: 0.20), .lowerThirdCenter),
            // Upper regions
            (CGRect(x: 0.05, y: 0.05, width: 0.4, height: 0.20), .upperLeft),
            (CGRect(x: 0.55, y: 0.05, width: 0.4, height: 0.20), .upperRight),
            (CGRect(x: 0.15, y: 0.08, width: 0.7, height: 0.15), .upperCenter),
            // Center regions
            (CGRect(x: 0.20, y: 0.35, width: 0.6, height: 0.30), .center),
            // Margins
            (CGRect(x: 0.02, y: 0.30, width: 0.15, height: 0.40), .leftMargin),
            (CGRect(x: 0.83, y: 0.30, width: 0.15, height: 0.40), .rightMargin)
        ]
        
        for (region, type) in candidateRegions {
            let confidence = evaluateZoneSafety(
                zone: region,
                faces: faces,
                saliencyRegions: saliencyRegions
            )
            
            if confidence >= config.minConfidence {
                zones.append(SafePlacementZone(
                    bounds: region,
                    type: type,
                    confidence: confidence
                ))
            }
        }
        
        // Sort by confidence
        zones.sort { $0.confidence > $1.confidence }
        
        return zones
    }
    
    private func evaluateZoneSafety(
        zone: CGRect,
        faces: [PlacementFaceRegion],
        saliencyRegions: [PlacementSaliencyRegion]
    ) -> Float {
        var confidence: Float = 1.0
        
        // Check face overlaps
        for face in faces {
            let expandedFace = face.bounds.insetBy(
                dx: -CGFloat(config.faceMargin) * face.bounds.width,
                dy: -CGFloat(config.faceMargin) * face.bounds.height
            )
            
            if zone.intersects(expandedFace) {
                let overlapArea = zone.intersection(expandedFace).area
                let zoneArea = zone.area
                let overlapRatio = Float(overlapArea / zoneArea)
                confidence -= overlapRatio * face.confidence
            }
        }
        
        // Check saliency overlaps
        for saliency in saliencyRegions {
            let expandedSaliency = saliency.bounds.insetBy(
                dx: -CGFloat(config.saliencyMargin) * saliency.bounds.width,
                dy: -CGFloat(config.saliencyMargin) * saliency.bounds.height
            )
            
            if zone.intersects(expandedSaliency) {
                let overlapArea = zone.intersection(expandedSaliency).area
                let zoneArea = zone.area
                let overlapRatio = Float(overlapArea / zoneArea)
                confidence -= overlapRatio * saliency.importance * 0.5  // Less penalty than faces
            }
        }
        
        // Edge margin check
        if zone.minX < CGFloat(config.edgeMargin) ||
           zone.maxX > CGFloat(1.0 - config.edgeMargin) ||
           zone.minY < CGFloat(config.edgeMargin) ||
           zone.maxY > CGFloat(1.0 - config.edgeMargin) {
            confidence *= 0.9
        }
        
        return Swift.max(0, confidence)
    }
    
    // MARK: - Placement Optimization
    
    private func findOptimalPlacement(
        for text: String,
        in zones: [SafePlacementZone],
        preferences: PlacementPreferences,
        existingPlacements: [PlacementSuggestion],
        index: Int
    ) -> PlacementSuggestion {
        // Filter and score zones based on preferences
        var scoredZones: [(zone: SafePlacementZone, score: Float)] = []
        
        for zone in zones {
            var score = zone.confidence
            
            // Apply preference biases
            if preferences.preferredVerticalRegion == .lower && zone.type.isLowerThird {
                score += config.lowerThirdBias
            }
            if preferences.preferredVerticalRegion == .upper && zone.type.isUpper {
                score += 0.2
            }
            if preferences.preferredHorizontalRegion == .left && zone.type.isLeft {
                score += 0.15
            }
            if preferences.preferredHorizontalRegion == .right && zone.type.isRight {
                score += 0.15
            }
            
            // Penalty for overlap with existing placements
            for existing in existingPlacements {
                let existingRect = CGRect(
                    x: CGFloat(existing.position.x) - 0.1,
                    y: CGFloat(existing.position.y) - 0.05,
                    width: 0.2,
                    height: 0.1
                )
                if zone.bounds.intersects(existingRect) {
                    score -= 0.3
                }
            }
            
            scoredZones.append((zone, score))
        }
        
        // Sort by score
        scoredZones.sort { $0.score > $1.score }
        
        // Use best zone
        let bestZone = scoredZones.first?.zone ?? SafePlacementZone(
            bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.15),
            type: .lowerThirdLeft,
            confidence: 0.5
        )
        
        let position = SIMD3<Float>(
            Float(bestZone.bounds.midX),
            Float(bestZone.bounds.midY),
            0.0
        )
        
        return PlacementSuggestion(
            content: text,
            position: position,
            anchor: preferences.preferredAnchor ?? bestZone.type.defaultAnchor,
            confidence: bestZone.confidence,
            reason: "Placed in \(bestZone.type.rawValue) (confidence: \(String(format: "%.0f", bestZone.confidence * 100))%)",
            zone: bestZone.type
        )
    }
    
    private func suggestLowerThirdForSpeaker(
        speaker: SpeakerPlacementInfo,
        zones: [SafePlacementZone],
        faces: [PlacementFaceRegion]
    ) -> LowerThirdSuggestion {
        // If speaker has associated face, place opposite side
        var preferredSide: HorizontalRegion = .left
        
        if let faceId = speaker.associatedFaceId,
           let face = faces.first(where: { $0.id == faceId }) {
            // Face on left? Place text on right
            if face.bounds.midX < 0.5 {
                preferredSide = .right
            }
        }
        
        // Find best zone on preferred side
        let sideZones = zones.filter { zone in
            switch preferredSide {
            case .left: return zone.bounds.midX < 0.5
            case .right: return zone.bounds.midX >= 0.5
            case .center: return true
            }
        }
        
        let bestZone = sideZones.first ?? zones.first ?? SafePlacementZone(
            bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.15),
            type: .lowerThirdLeft,
            confidence: 0.5
        )
        
        let anchor: TextAnchor = preferredSide == .right ? .bottomRight : .bottomLeft
        
        return LowerThirdSuggestion(
            speakerId: speaker.id,
            speakerLabel: speaker.label,
            title: speaker.title,
            position: SIMD3<Float>(
                preferredSide == .right ? 0.9 : 0.1,
                0.85,
                0.0
            ),
            anchor: anchor,
            showAt: speaker.firstAppearance,
            duration: 5.0,
            confidence: bestZone.confidence,
            reason: speaker.associatedFaceId != nil ?
                "Placed opposite speaker's face" : "Default lower-third position"
        )
    }
    
    private func findBestTitleZone(
        zones: [SafePlacementZone],
        faces: [PlacementFaceRegion]
    ) -> SafePlacementZone {
        // Prefer center zones, then upper/lower center
        let centerZones = zones.filter { zone in
            zone.type == .center || zone.type == .upperCenter || zone.type == .lowerThirdCenter
        }
        
        if let best = centerZones.first {
            return best
        }
        
        // Fall back to any zone
        return zones.first ?? SafePlacementZone(
            bounds: CGRect(x: 0.2, y: 0.4, width: 0.6, height: 0.2),
            type: .center,
            confidence: 0.5
        )
    }
}

// MARK: - Supporting Types

/// Suggested placement for text
public struct PlacementSuggestion: Sendable {
    public let content: String
    public let position: SIMD3<Float>
    public let anchor: TextAnchor
    public let confidence: Float
    public let reason: String
    public let zone: SafeZoneType
    
    public init(
        content: String,
        position: SIMD3<Float>,
        anchor: TextAnchor,
        confidence: Float,
        reason: String,
        zone: SafeZoneType
    ) {
        self.content = content
        self.position = position
        self.anchor = anchor
        self.confidence = confidence
        self.reason = reason
        self.zone = zone
    }
}

/// Suggested lower third placement
public struct LowerThirdSuggestion: Sendable {
    public let speakerId: String
    public let speakerLabel: String?
    public let title: String?
    public let position: SIMD3<Float>
    public let anchor: TextAnchor
    public let showAt: Double
    public let duration: Double
    public let confidence: Float
    public let reason: String
    
    public init(
        speakerId: String,
        speakerLabel: String?,
        title: String?,
        position: SIMD3<Float>,
        anchor: TextAnchor,
        showAt: Double,
        duration: Double,
        confidence: Float,
        reason: String
    ) {
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.title = title
        self.position = position
        self.anchor = anchor
        self.showAt = showAt
        self.duration = duration
        self.confidence = confidence
        self.reason = reason
    }
}

/// Suggested title card placement
public struct TitleCardSuggestion: Sendable {
    public let title: String
    public let titlePosition: SIMD3<Float>
    public let subtitle: String?
    public let subtitlePosition: SIMD3<Float>?
    public let anchor: TextAnchor
    public let showAt: Double
    public let duration: Double
    public let confidence: Float
    public let reason: String
    
    public init(
        title: String,
        titlePosition: SIMD3<Float>,
        subtitle: String?,
        subtitlePosition: SIMD3<Float>?,
        anchor: TextAnchor,
        showAt: Double,
        duration: Double,
        confidence: Float,
        reason: String
    ) {
        self.title = title
        self.titlePosition = titlePosition
        self.subtitle = subtitle
        self.subtitlePosition = subtitlePosition
        self.anchor = anchor
        self.showAt = showAt
        self.duration = duration
        self.confidence = confidence
        self.reason = reason
    }
}

/// Placement preferences
public struct PlacementPreferences: Sendable {
    public let preferredAnchor: TextAnchor?
    public let preferredVerticalRegion: VerticalRegion
    public let preferredHorizontalRegion: HorizontalRegion
    
    public init(
        preferredAnchor: TextAnchor? = nil,
        preferredVerticalRegion: VerticalRegion = .lower,
        preferredHorizontalRegion: HorizontalRegion = .left
    ) {
        self.preferredAnchor = preferredAnchor
        self.preferredVerticalRegion = preferredVerticalRegion
        self.preferredHorizontalRegion = preferredHorizontalRegion
    }
    
    public static let `default` = PlacementPreferences()
}

public enum VerticalRegion: String, Sendable {
    case upper
    case center
    case lower
}

public enum HorizontalRegion: String, Sendable {
    case left
    case center
    case right
}

// MARK: - Analysis Input Types

/// Frame analysis data for placement decisions
public struct FramePlacementAnalysis: Sendable {
    public let frameSize: SIMD2<Int>
    public let faces: [PlacementFaceRegion]
    public let saliencyRegions: [PlacementSaliencyRegion]
    
    public init(
        frameSize: SIMD2<Int>,
        faces: [PlacementFaceRegion],
        saliencyRegions: [PlacementSaliencyRegion]
    ) {
        self.frameSize = frameSize
        self.faces = faces
        self.saliencyRegions = saliencyRegions
    }
}

/// Face region for placement avoidance
public struct PlacementFaceRegion: Sendable {
    public let id: String
    public let bounds: CGRect
    public let confidence: Float
    
    public init(id: String, bounds: CGRect, confidence: Float) {
        self.id = id
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// Salient region for placement avoidance
public struct PlacementSaliencyRegion: Sendable {
    public let bounds: CGRect
    public let importance: Float
    
    public init(bounds: CGRect, importance: Float) {
        self.bounds = bounds
        self.importance = importance
    }
}

/// Speaker info for lower third placement
public struct SpeakerPlacementInfo: Sendable {
    public let id: String
    public let label: String?
    public let title: String?
    public let firstAppearance: Double
    public let associatedFaceId: String?
    
    public init(
        id: String,
        label: String?,
        title: String?,
        firstAppearance: Double,
        associatedFaceId: String?
    ) {
        self.id = id
        self.label = label
        self.title = title
        self.firstAppearance = firstAppearance
        self.associatedFaceId = associatedFaceId
    }
}

// MARK: - Safe Zone Types

/// A safe zone for text placement
public struct SafePlacementZone: Sendable {
    public let bounds: CGRect
    public let type: SafeZoneType
    public let confidence: Float
    
    public init(bounds: CGRect, type: SafeZoneType, confidence: Float) {
        self.bounds = bounds
        self.type = type
        self.confidence = confidence
    }
}

/// Type of safe zone
public enum SafeZoneType: String, Sendable {
    case lowerThirdLeft
    case lowerThirdRight
    case lowerThirdCenter
    case upperLeft
    case upperRight
    case upperCenter
    case center
    case leftMargin
    case rightMargin
    
    public var isLowerThird: Bool {
        switch self {
        case .lowerThirdLeft, .lowerThirdRight, .lowerThirdCenter: return true
        default: return false
        }
    }
    
    public var isUpper: Bool {
        switch self {
        case .upperLeft, .upperRight, .upperCenter: return true
        default: return false
        }
    }
    
    public var isLeft: Bool {
        switch self {
        case .lowerThirdLeft, .upperLeft, .leftMargin: return true
        default: return false
        }
    }
    
    public var isRight: Bool {
        switch self {
        case .lowerThirdRight, .upperRight, .rightMargin: return true
        default: return false
        }
    }
    
    public var defaultAnchor: TextAnchor {
        switch self {
        case .lowerThirdLeft: return .bottomLeft
        case .lowerThirdRight: return .bottomRight
        case .lowerThirdCenter: return .bottomCenter
        case .upperLeft: return .topLeft
        case .upperRight: return .topRight
        case .upperCenter: return .topCenter
        case .center: return .center
        case .leftMargin: return .centerLeft
        case .rightMargin: return .centerRight
        }
    }
}

// MARK: - Extensions

extension TextAnchor {
    var isBottom: Bool {
        switch self {
        case .bottomLeft, .bottomCenter, .bottomRight: return true
        default: return false
        }
    }
    
    var isTop: Bool {
        switch self {
        case .topLeft, .topCenter, .topRight: return true
        default: return false
        }
    }
    
    var isLeft: Bool {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: return true
        default: return false
        }
    }
    
    var isRight: Bool {
        switch self {
        case .topRight, .centerRight, .bottomRight: return true
        default: return false
        }
    }
}

extension CGRect {
    var area: CGFloat {
        width * height
    }
}
