import Metal
import Foundation
import CoreGraphics
import QuartzCore

// MARK: - SmartPlacement

/// Uses saliency detection to find optimal positions for text/graphics
/// Avoids high-attention areas and faces for clean, non-distracting placement
public actor SmartPlacement {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Anchors to prefer (in order of preference)
        public let preferredAnchors: [TextAnchor]
        /// Whether to avoid detected faces
        public let avoidFaces: Bool
        /// Minimum distance from faces (normalized 0-1)
        public let faceMargin: Float
        /// Saliency threshold (0-1, areas below this are considered safe)
        public let saliencyThreshold: Float
        /// Margin from screen edges (normalized 0-1)
        public let edgeMargin: Float
        
        public static let `default` = Config(
            preferredAnchors: [.bottomRight, .bottomLeft, .topRight, .topLeft],
            avoidFaces: true,
            faceMargin: 0.1,
            saliencyThreshold: 0.3,
            edgeMargin: 0.05
        )
        
        public init(
            preferredAnchors: [TextAnchor] = [.bottomRight, .bottomLeft],
            avoidFaces: Bool = true,
            faceMargin: Float = 0.1,
            saliencyThreshold: Float = 0.3,
            edgeMargin: Float = 0.05
        ) {
            self.preferredAnchors = preferredAnchors
            self.avoidFaces = avoidFaces
            self.faceMargin = faceMargin
            self.saliencyThreshold = saliencyThreshold
            self.edgeMargin = edgeMargin
        }
    }
    
    // MARK: - Text Anchor
    
    public enum TextAnchor: String, Codable, CaseIterable, Sendable {
        case topLeft, topCenter, topRight
        case centerLeft, center, centerRight
        case bottomLeft, bottomCenter, bottomRight
        
        /// Normalized position for this anchor
        var position: CGPoint {
            switch self {
            case .topLeft:      return CGPoint(x: 0.1, y: 0.1)
            case .topCenter:    return CGPoint(x: 0.5, y: 0.1)
            case .topRight:     return CGPoint(x: 0.9, y: 0.1)
            case .centerLeft:   return CGPoint(x: 0.1, y: 0.5)
            case .center:       return CGPoint(x: 0.5, y: 0.5)
            case .centerRight:  return CGPoint(x: 0.9, y: 0.5)
            case .bottomLeft:   return CGPoint(x: 0.1, y: 0.9)
            case .bottomCenter: return CGPoint(x: 0.5, y: 0.9)
            case .bottomRight:  return CGPoint(x: 0.9, y: 0.9)
            }
        }
    }
    
    // MARK: - Result Types
    
    /// A placement suggestion with confidence
    public struct Suggestion: Sendable {
        /// Normalized position (0-1)
        public let position: CGPoint
        /// Confidence that this is a good position (0-1)
        public let confidence: Float
        /// The safe zone this position is within
        public let safeZone: CGRect
        /// Alternative positions, ranked
        public let alternatives: [CGPoint]
        
        public init(
            position: CGPoint,
            confidence: Float,
            safeZone: CGRect,
            alternatives: [CGPoint] = []
        ) {
            self.position = position
            self.confidence = confidence
            self.safeZone = safeZone
            self.alternatives = alternatives
        }
    }
    
    // MARK: - Errors
    
    public enum Error: Swift.Error, LocalizedError {
        case analysisUnavailable
        case noSafeZonesFound
        
        public var errorDescription: String? {
            switch self {
            case .analysisUnavailable:
                return "Scene analysis is not available"
            case .noSafeZonesFound:
                return "No suitable placement zones found"
            }
        }
    }
    
    // MARK: - Properties
    
    private let device: MTLDevice
    private let visionProvider: VisionProvider
    
    // Cache for saliency analysis
    private var cachedSaliency: SaliencyMap?
    private var cachedFaces: [FaceObservation]?
    private var cacheTimestamp: CFTimeInterval = 0
    private let cacheDuration: CFTimeInterval = 0.5  // 500ms cache
    
    // MARK: - Initialization
    
    public init(device: MTLDevice? = nil, visionProvider: VisionProvider? = nil) {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        self.device = dev
        self.visionProvider = visionProvider ?? VisionProvider(device: dev)
    }
    
    // MARK: - Public API
    
    /// Suggest optimal placement for text of given size
    /// - Parameters:
    ///   - frame: Video frame to analyze
    ///   - textSize: Size of text to place (normalized 0-1)
    ///   - config: Placement configuration
    /// - Returns: Placement suggestion with confidence
    public func suggestPlacement(
        frame: MTLTexture,
        textSize: CGSize,
        config: Config = .default
    ) async throws -> Suggestion {
        
        // Get or update cached analysis
        let (saliency, faces) = try await getAnalysis(for: frame, config: config)
        
        // Find safe zones
        let safeZones = findSafeZones(
            saliency: saliency,
            faces: faces,
            config: config
        )
        
        guard !safeZones.isEmpty else {
            // Fall back to preferred anchor
            let fallback = config.preferredAnchors.first ?? .bottomRight
            return Suggestion(
                position: fallback.position,
                confidence: 0.1,
                safeZone: CGRect(origin: fallback.position, size: textSize),
                alternatives: []
            )
        }
        
        // Score each potential position
        let candidates = scoreCandidates(
            safeZones: safeZones,
            textSize: textSize,
            preferredAnchors: config.preferredAnchors,
            faces: faces,
            config: config
        )
        
        guard let best = candidates.first else {
            throw Error.noSafeZonesFound
        }
        
        return Suggestion(
            position: best.position,
            confidence: best.score,
            safeZone: best.zone,
            alternatives: Array(candidates.dropFirst().prefix(3).map { $0.position })
        )
    }
    
    /// Find all safe zones in a frame
    public func findSafeZones(
        in frame: MTLTexture,
        config: Config = .default
    ) async throws -> [CGRect] {
        let (saliency, faces) = try await getAnalysis(for: frame, config: config)
        return findSafeZones(saliency: saliency, faces: faces, config: config)
    }
    
    /// Clear cached analysis
    public func clearCache() {
        cachedSaliency = nil
        cachedFaces = nil
        cacheTimestamp = 0
    }
    
    // MARK: - Private Methods
    
    private func getAnalysis(
        for frame: MTLTexture,
        config: Config
    ) async throws -> (SaliencyMap, [FaceObservation]) {
        
        let now = CACurrentMediaTime()
        
        // Return cached if still valid
        if let saliency = cachedSaliency,
           let faces = cachedFaces,
           now - cacheTimestamp < cacheDuration {
            return (saliency, faces)
        }
        
        // Run analysis in parallel
        async let saliencyTask = visionProvider.detectSaliency(in: frame, mode: .attention)
        async let facesTask = config.avoidFaces
            ? visionProvider.detectFaces(in: frame, landmarks: false)
            : []
        
        let saliency = try await saliencyTask
        let faces = try await facesTask
        
        // Cache results
        cachedSaliency = saliency
        cachedFaces = faces
        cacheTimestamp = now
        
        return (saliency, faces)
    }
    
    private func findSafeZones(
        saliency: SaliencyMap,
        faces: [FaceObservation],
        config: Config
    ) -> [CGRect] {
        var zones: [CGRect] = []
        
        // Define grid of potential zones
        let gridSize = 4
        let cellWidth = 1.0 / CGFloat(gridSize)
        let cellHeight = 1.0 / CGFloat(gridSize)
        
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = CGFloat(col) * cellWidth + CGFloat(config.edgeMargin)
                let y = CGFloat(row) * cellHeight + CGFloat(config.edgeMargin)
                let width = cellWidth - CGFloat(config.edgeMargin) * 2
                let height = cellHeight - CGFloat(config.edgeMargin) * 2
                
                let zone = CGRect(x: x, y: y, width: width, height: height)
                
                // Check if zone is safe
                if isZoneSafe(zone, saliency: saliency, faces: faces, config: config) {
                    zones.append(zone)
                }
            }
        }
        
        // Merge adjacent zones for larger text areas
        return mergeAdjacentZones(zones)
    }
    
    private func isZoneSafe(
        _ zone: CGRect,
        saliency: SaliencyMap,
        faces: [FaceObservation],
        config: Config
    ) -> Bool {
        // Check saliency regions
        for region in saliency.regions {
            if zone.intersects(region.bounds) {
                // High overlap with salient area = not safe
                let intersection = zone.intersection(region.bounds)
                let overlapRatio = (intersection.width * intersection.height) / (zone.width * zone.height)
                if overlapRatio > 0.3 && region.confidence > config.saliencyThreshold {
                    return false
                }
            }
        }
        
        // Check face overlap
        if config.avoidFaces {
            for face in faces {
                // Expand face bounds by margin
                let expanded = face.bounds.insetBy(
                    dx: -CGFloat(config.faceMargin),
                    dy: -CGFloat(config.faceMargin)
                )
                if zone.intersects(expanded) {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func mergeAdjacentZones(_ zones: [CGRect]) -> [CGRect] {
        guard zones.count > 1 else { return zones }
        
        var merged: [CGRect] = []
        var used = Set<Int>()
        
        for (i, zone) in zones.enumerated() {
            if used.contains(i) { continue }
            
            var current = zone
            used.insert(i)
            
            // Try to merge with adjacent zones
            for (j, other) in zones.enumerated() {
                if used.contains(j) { continue }
                
                // Check if adjacent (within small epsilon)
                let combined = current.union(other)
                let totalArea = current.width * current.height + other.width * other.height
                let unionArea = combined.width * combined.height
                
                // If union is close to total (minimal gap), merge
                if unionArea <= totalArea * 1.2 {
                    current = combined
                    used.insert(j)
                }
            }
            
            merged.append(current)
        }
        
        return merged
    }
    
    private struct ScoredCandidate {
        let position: CGPoint
        let zone: CGRect
        let score: Float
    }
    
    private func scoreCandidates(
        safeZones: [CGRect],
        textSize: CGSize,
        preferredAnchors: [TextAnchor],
        faces: [FaceObservation],
        config: Config
    ) -> [ScoredCandidate] {
        var candidates: [ScoredCandidate] = []
        
        for zone in safeZones {
            // Check if text fits in zone
            guard zone.width >= textSize.width && zone.height >= textSize.height else {
                continue
            }
            
            // Center position in zone
            let position = CGPoint(
                x: zone.midX,
                y: zone.midY
            )
            
            var score: Float = 0.5  // Base score
            
            // Boost for preferred anchors
            for (index, anchor) in preferredAnchors.enumerated() {
                let anchorPos = anchor.position
                let distance = hypot(position.x - anchorPos.x, position.y - anchorPos.y)
                if distance < 0.3 {
                    score += Float(preferredAnchors.count - index) * 0.1
                }
            }
            
            // Boost for edge positions (less intrusive)
            let edgeBoost = min(
                Float(position.x), Float(1.0 - position.x),
                Float(position.y), Float(1.0 - position.y)
            )
            if edgeBoost < 0.2 {
                score += 0.1
            }
            
            // Penalty for being near faces
            for face in faces {
                let faceCenter = CGPoint(x: face.bounds.midX, y: face.bounds.midY)
                let distance = hypot(position.x - faceCenter.x, position.y - faceCenter.y)
                if distance < CGFloat(config.faceMargin * 2) {
                    score -= 0.2
                }
            }
            
            // Boost for larger zones (more room)
            let zoneArea = zone.width * zone.height
            score += Float(zoneArea) * 0.2
            
            candidates.append(ScoredCandidate(
                position: position,
                zone: zone,
                score: min(max(score, 0), 1)
            ))
        }
        
        // Sort by score descending
        return candidates.sorted { $0.score > $1.score }
    }
}

// MARK: - Convenience Extensions

extension SmartPlacement {
    
    /// Get the best anchor position without full analysis
    public func quickSuggest(
        preferredAnchors: [TextAnchor] = [.bottomRight, .bottomLeft]
    ) -> CGPoint {
        return preferredAnchors.first?.position ?? TextAnchor.bottomRight.position
    }
}
