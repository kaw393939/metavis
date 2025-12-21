// Sources/MetaVisRender/Ingestion/AI/DraftManifestGenerator.swift
// Sprint 03: AI-powered manifest generation for video projects

import Foundation
import simd
import CoreGraphics

// MARK: - Draft Manifest Generator

/// Generates AI-suggested render manifests based on ingested media analysis
public actor DraftManifestGenerator {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Default duration for lower thirds (seconds)
        public let lowerThirdDuration: Float
        /// Minimum time before first text appears
        public let titleDelay: Float
        /// Default fade duration for text elements
        public let defaultFadeDuration: Float
        /// Enable smart depth-based compositing
        public let enableDepthCompositing: Bool
        /// Confidence threshold for auto-placement
        public let confidenceThreshold: Float
        
        public init(
            lowerThirdDuration: Float = 5.0,
            titleDelay: Float = 1.0,
            defaultFadeDuration: Float = 0.5,
            enableDepthCompositing: Bool = true,
            confidenceThreshold: Float = 0.7
        ) {
            self.lowerThirdDuration = lowerThirdDuration
            self.titleDelay = titleDelay
            self.defaultFadeDuration = defaultFadeDuration
            self.enableDepthCompositing = enableDepthCompositing
            self.confidenceThreshold = confidenceThreshold
        }
        
        public static let `default` = Config()
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Generate a draft manifest from clip analysis
    public func generate(
        from analysis: DraftClipAnalysis,
        template: DraftTemplate = .interview,
        textSuggestions: [DraftTextSuggestion] = []
    ) async throws -> DraftManifest {
        var elements: [ManifestElement] = []
        var aiSuggestions: [DraftAISuggestion] = []
        var reviewItems: [String] = []
        var overallConfidence: Float = 1.0
        
        // Generate lower thirds for speakers
        if template.includesLowerThirds {
            let (lowerThirds, suggestions) = generateLowerThirds(
                speakers: analysis.speakers,
                faces: analysis.faces
            )
            elements.append(contentsOf: lowerThirds)
            aiSuggestions.append(contentsOf: suggestions)
        }
        
        // Generate title card if template requires
        if template.includesTitle {
            if let title = textSuggestions.first(where: { $0.type == .title }) {
                let (titleElement, titleSuggestion) = generateTitleCard(
                    content: title.content,
                    analysis: analysis
                )
                elements.append(titleElement)
                aiSuggestions.append(titleSuggestion)
            }
        }
        
        // Add user-requested text suggestions
        for suggestion in textSuggestions where suggestion.type == .custom {
            let (element, aiSuggestion) = generateCustomText(
                suggestion: suggestion,
                analysis: analysis
            )
            elements.append(element)
            aiSuggestions.append(aiSuggestion)
        }
        
        // Check for low-confidence placements
        for suggestion in aiSuggestions where suggestion.confidence < config.confidenceThreshold {
            reviewItems.append("Review placement for \(suggestion.elementId): \(suggestion.reason)")
            overallConfidence = Swift.min(overallConfidence, suggestion.confidence)
        }
        
        // Build the manifest
        let manifest = RenderManifest(
            metadata: ManifestMetadata(
                duration: Double(analysis.duration),
                fps: Double(analysis.fps),
                resolution: analysis.resolution
            ),
            scene: SceneDefinition(
                background: "transparent",
                ambientLight: 1.0
            ),
            camera: CameraDefinition(),
            elements: elements,
            compositing: config.enableDepthCompositing ? CompositingDefinition(
                mode: "behindSubject",
                enableDepthEstimation: true,
                enableSmartPlacement: true
            ) : nil
        )
        
        return DraftManifest(
            manifest: manifest,
            suggestions: aiSuggestions,
            confidence: overallConfidence,
            reviewRequired: reviewItems,
            template: template
        )
    }
    
    // MARK: - Lower Thirds Generation
    
    private func generateLowerThirds(
        speakers: [DraftSpeakerInfo],
        faces: [DraftFaceRegion]
    ) -> ([ManifestElement], [DraftAISuggestion]) {
        var elements: [ManifestElement] = []
        var suggestions: [DraftAISuggestion] = []
        
        for (index, speaker) in speakers.enumerated() {
            let elementId = "lower_third_\(index)"
            
            // Find best position for this speaker's lower third
            let (position, anchor, confidence, reason) = findOptimalLowerThirdPosition(
                speaker: speaker,
                faces: faces,
                existingCount: elements.count
            )
            
            let textElement = TextElement(
                content: speaker.label ?? "Speaker \(index + 1)",
                position: position,
                fontSize: 32,
                anchor: anchor,
                positionMode: .normalized,
                startTime: Float(speaker.firstAppearance),
                duration: config.lowerThirdDuration
            )
            
            elements.append(.text(textElement))
            
            suggestions.append(DraftAISuggestion(
                elementId: elementId,
                property: "position",
                reason: reason,
                confidence: confidence
            ))
        }
        
        return (elements, suggestions)
    }
    
    private func findOptimalLowerThirdPosition(
        speaker: DraftSpeakerInfo,
        faces: [DraftFaceRegion],
        existingCount: Int
    ) -> (SIMD3<Float>, TextAnchor, Float, String) {
        // Default lower-third position
        var position = SIMD3<Float>(0.1, 0.85, 0.0)
        var anchor = TextAnchor.bottomLeft
        var confidence: Float = 0.8
        var reason = "Standard lower-third placement"
        
        // Check for face in lower left quadrant
        let lowerLeftFaces = faces.filter { face in
            face.bounds.origin.x < 0.5 && face.bounds.origin.y > 0.5
        }
        
        if !lowerLeftFaces.isEmpty {
            // Face in lower left, move to lower right
            position = SIMD3<Float>(0.9, 0.85, 0.0)
            anchor = .bottomRight
            reason = "Moved to lower right to avoid face"
            confidence = 0.85
        }
        
        // Offset if there are existing elements
        if existingCount > 0 {
            position.y -= Float(existingCount) * 0.08
            reason += "; offset for multiple speakers"
            confidence *= 0.95
        }
        
        return (position, anchor, confidence, reason)
    }
    
    // MARK: - Title Card Generation
    
    private func generateTitleCard(
        content: String,
        analysis: DraftClipAnalysis
    ) -> (ManifestElement, DraftAISuggestion) {
        let elementId = "title_card"
        
        // Find optimal title position
        var titlePosition = SIMD3<Float>(0.5, 0.3, 0.0)
        var reason = "Centered title placement"
        var confidence: Float = 0.9
        
        // Check for faces in upper center
        let upperCenterFaces = analysis.faces.filter { face in
            face.bounds.origin.x > 0.3 && face.bounds.origin.x < 0.7 &&
            face.bounds.origin.y < 0.5
        }
        
        if !upperCenterFaces.isEmpty {
            // Move title lower
            titlePosition.y = 0.7
            reason = "Title moved lower to avoid faces"
            confidence = 0.85
        }
        
        let textElement = TextElement(
            content: content,
            position: titlePosition,
            fontSize: 48,
            anchor: .center,
            positionMode: .normalized,
            startTime: config.titleDelay,
            duration: 4.0
        )
        
        let suggestion = DraftAISuggestion(
            elementId: elementId,
            property: "position",
            reason: reason,
            confidence: confidence
        )
        
        return (.text(textElement), suggestion)
    }
    
    // MARK: - Custom Text Generation
    
    private func generateCustomText(
        suggestion: DraftTextSuggestion,
        analysis: DraftClipAnalysis
    ) -> (ManifestElement, DraftAISuggestion) {
        let elementId = "custom_\(UUID().uuidString.prefix(8))"
        
        // Determine optimal position
        var position = SIMD3<Float>(0.5, 0.5, 0.0)
        var anchor = TextAnchor.center
        var reason = "Default center placement"
        var confidence: Float = 0.7
        
        if let preferred = suggestion.preferredPosition {
            position = SIMD3<Float>(
                Float(preferred.x),
                Float(preferred.y),
                Float(preferred.z ?? 0)
            )
            anchor = preferred.anchor ?? .center
            reason = "User-specified position"
            confidence = 1.0
        }
        
        let textElement = TextElement(
            content: suggestion.content,
            position: position,
            fontSize: 32,
            anchor: anchor,
            positionMode: .normalized,
            startTime: Float(suggestion.startTime ?? 0),
            duration: Float((suggestion.endTime ?? Double(analysis.duration)) - (suggestion.startTime ?? 0))
        )
        
        let aiSuggestion = DraftAISuggestion(
            elementId: elementId,
            property: "position",
            reason: reason,
            confidence: confidence
        )
        
        return (.text(textElement), aiSuggestion)
    }
}

// MARK: - Supporting Types

/// Generated draft manifest with AI suggestions
public struct DraftManifest: Sendable {
    public let manifest: RenderManifest
    public let suggestions: [DraftAISuggestion]
    public let confidence: Float
    public let reviewRequired: [String]
    public let template: DraftTemplate
    
    public init(
        manifest: RenderManifest,
        suggestions: [DraftAISuggestion],
        confidence: Float,
        reviewRequired: [String],
        template: DraftTemplate
    ) {
        self.manifest = manifest
        self.suggestions = suggestions
        self.confidence = confidence
        self.reviewRequired = reviewRequired
        self.template = template
    }
}

/// AI-generated suggestion for an element
public struct DraftAISuggestion: Codable, Sendable {
    public let elementId: String
    public let property: String
    public let reason: String
    public let confidence: Float
    
    public init(elementId: String, property: String, reason: String, confidence: Float) {
        self.elementId = elementId
        self.property = property
        self.reason = reason
        self.confidence = confidence
    }
}

/// Template for manifest generation
public enum DraftTemplate: String, Sendable {
    case interview      // Lower thirds, speaker labels
    case presentation   // Title cards, bullet points
    case documentary    // Captions, chapter markers
    case social         // Bold text overlays
    case minimal        // Just captions
    
    public var includesLowerThirds: Bool {
        self == .interview || self == .documentary
    }
    
    public var includesTitle: Bool {
        self != .minimal
    }
    
    public var includesCaptions: Bool {
        self == .documentary || self == .minimal
    }
}

/// Text suggestion input for draft generation
public struct DraftTextSuggestion: Sendable {
    public let type: DraftTextType
    public let content: String
    public let preferredPosition: DraftTextPosition?
    public let startTime: Double?
    public let endTime: Double?
    
    public init(
        type: DraftTextType,
        content: String,
        preferredPosition: DraftTextPosition? = nil,
        startTime: Double? = nil,
        endTime: Double? = nil
    ) {
        self.type = type
        self.content = content
        self.preferredPosition = preferredPosition
        self.startTime = startTime
        self.endTime = endTime
    }
}

public enum DraftTextType: String, Sendable {
    case title
    case lowerThird
    case caption
    case custom
}

/// Position preference for text
public struct DraftTextPosition: Sendable {
    public let x: Double
    public let y: Double
    public let z: Double?
    public let anchor: TextAnchor?
    
    public init(x: Double, y: Double, z: Double? = nil, anchor: TextAnchor? = nil) {
        self.x = x
        self.y = y
        self.z = z
        self.anchor = anchor
    }
}

// MARK: - Analysis Input Types

/// Clip analysis for draft generation
public struct DraftClipAnalysis: Sendable {
    public let duration: Float
    public let fps: Float
    public let resolution: SIMD2<Int>
    public let speakers: [DraftSpeakerInfo]
    public let faces: [DraftFaceRegion]
    
    public init(
        duration: Float,
        fps: Float,
        resolution: SIMD2<Int>,
        speakers: [DraftSpeakerInfo],
        faces: [DraftFaceRegion]
    ) {
        self.duration = duration
        self.fps = fps
        self.resolution = resolution
        self.speakers = speakers
        self.faces = faces
    }
}

/// Speaker information for lower thirds
public struct DraftSpeakerInfo: Sendable {
    public let id: String
    public let label: String?
    public let firstAppearance: Double
    public let totalSpeakingTime: Double
    
    public init(id: String, label: String?, firstAppearance: Double, totalSpeakingTime: Double) {
        self.id = id
        self.label = label
        self.firstAppearance = firstAppearance
        self.totalSpeakingTime = totalSpeakingTime
    }
}

/// Face region in frame for placement avoidance
public struct DraftFaceRegion: Sendable {
    public let bounds: CGRect
    public let confidence: Float
    
    public init(bounds: CGRect, confidence: Float) {
        self.bounds = bounds
        self.confidence = confidence
    }
}
