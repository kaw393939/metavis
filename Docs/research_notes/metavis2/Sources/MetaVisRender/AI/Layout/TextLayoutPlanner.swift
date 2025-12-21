import Foundation
import CoreGraphics

// MARK: - Placement Result

/// Result of text placement optimization
public struct TextPlacement: Sendable {
    /// The optimal bounding box for the text (in pixels)
    public let bounds: CGRect
    
    /// Confidence in this placement (0-1)
    public let confidence: Float
    
    /// Reason for this placement choice
    public let reason: PlacementReason
    
    /// Suggested depth value for behind-subject compositing
    public let suggestedDepth: Float
    
    public enum PlacementReason: Sendable {
        case optimal          // Best placement found
        case fallback         // Couldn't find good placement, using fallback
        case userSpecified    // User provided position
        case avoidsSubject    // Moved to avoid detected subject
        case avoidsMotion     // Moved to avoid high-motion area
    }
    
    public init(bounds: CGRect, confidence: Float, reason: PlacementReason, suggestedDepth: Float = 0.8) {
        self.bounds = bounds
        self.confidence = confidence
        self.reason = reason
        self.suggestedDepth = suggestedDepth
    }
}

// MARK: - Layout Hint

/// Hints from AI analysis for text placement
public struct LayoutHint: Sendable {
    /// Regions to avoid (subjects, salient areas)
    public let avoidRegions: [CGRect]
    
    /// Suggested regions for text (empty areas)
    public let suggestedRegions: [CGRect]
    
    /// Dominant motion direction (if any)
    public let motionDirection: SIMD2<Float>?
    
    /// Average scene depth
    public let averageDepth: Float
    
    public init(
        avoidRegions: [CGRect] = [],
        suggestedRegions: [CGRect] = [],
        motionDirection: SIMD2<Float>? = nil,
        averageDepth: Float = 0.5
    ) {
        self.avoidRegions = avoidRegions
        self.suggestedRegions = suggestedRegions
        self.motionDirection = motionDirection
        self.averageDepth = averageDepth
    }
}

// MARK: - Occupancy Map

/// Internal occupancy map for placement optimization
struct OccupancyMap {
    private var grid: [[Float]]
    let gridWidth: Int
    let gridHeight: Int
    let cellWidth: Float
    let cellHeight: Float
    
    init(size: CGSize, gridResolution: Int = 20) {
        self.gridWidth = gridResolution
        self.gridHeight = gridResolution
        self.cellWidth = Float(size.width) / Float(gridResolution)
        self.cellHeight = Float(size.height) / Float(gridResolution)
        self.grid = Array(repeating: Array(repeating: 0.0, count: gridResolution), count: gridResolution)
    }
    
    mutating func markOccupied(_ rect: CGRect, weight: Float = 1.0) {
        let minX = max(0, Int(Float(rect.minX) / cellWidth))
        let maxX = min(gridWidth - 1, Int(Float(rect.maxX) / cellWidth))
        let minY = max(0, Int(Float(rect.minY) / cellHeight))
        let maxY = min(gridHeight - 1, Int(Float(rect.maxY) / cellHeight))
        
        for y in minY...maxY {
            for x in minX...maxX {
                grid[y][x] = max(grid[y][x], weight)
            }
        }
    }
    
    func scoreRegion(_ rect: CGRect) -> Float {
        let minX = max(0, Int(Float(rect.minX) / cellWidth))
        let maxX = min(gridWidth - 1, Int(Float(rect.maxX) / cellWidth))
        let minY = max(0, Int(Float(rect.minY) / cellHeight))
        let maxY = min(gridHeight - 1, Int(Float(rect.maxY) / cellHeight))
        
        guard maxX >= minX && maxY >= minY else { return 1.0 }
        
        var total: Float = 0
        var count = 0
        
        for y in minY...maxY {
            for x in minX...maxX {
                total += grid[y][x]
                count += 1
            }
        }
        
        return count > 0 ? total / Float(count) : 1.0
    }
}

// MARK: - TextLayoutPlanner

/// AI-powered text placement optimization
public final class TextLayoutPlanner: @unchecked Sendable {
    
    public enum PreferredRegion: Sendable {
        case lowerThird     // Bottom 1/3 of screen (subtitles)
        case upperThird     // Top 1/3 of screen
        case center         // Center of screen
        case auto           // Let AI decide
    }
    
    /// Preferred placement region
    public var preferredRegion: PreferredRegion = .auto
    
    /// Safe area insets (pixels)
    public var safeAreaInsets: EdgeInsets = EdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
    
    /// Minimum margin from edges (pixels)
    public var minimumMargin: CGFloat = 20
    
    /// Font size for measurement
    public var defaultFontSize: CGFloat = 48
    
    public init() {}
    
    // MARK: - Optimal Placement
    
    /// Find optimal placement for text avoiding subjects and salient areas
    public func findOptimalPlacement(
        for text: String,
        saliency: SaliencyMap?,
        segmentation: SegmentationMask?,
        frameSize: CGSize,
        opticalFlow: OpticalFlow? = nil
    ) async throws -> TextPlacement {
        
        // Measure text size
        let textSize = measureText(text, fontSize: defaultFontSize)
        
        // Build occupancy map
        var occupancy = OccupancyMap(size: frameSize)
        
        // Add salient regions
        if let saliency = saliency {
            for region in saliency.regions {
                let pixelRect = CGRect(
                    x: region.bounds.minX * frameSize.width,
                    y: region.bounds.minY * frameSize.height,
                    width: region.bounds.width * frameSize.width,
                    height: region.bounds.height * frameSize.height
                )
                occupancy.markOccupied(pixelRect, weight: region.confidence)
            }
        }
        
        // Add segmented people
        if let segmentation = segmentation {
            let pixelRect = CGRect(
                x: segmentation.bounds.minX * frameSize.width,
                y: segmentation.bounds.minY * frameSize.height,
                width: segmentation.bounds.width * frameSize.width,
                height: segmentation.bounds.height * frameSize.height
            )
            occupancy.markOccupied(pixelRect, weight: 1.0)
        }
        
        // Add safe area as occupied (inverted - mark edges as occupied)
        occupancy.markOccupied(CGRect(x: 0, y: 0, width: frameSize.width, height: safeAreaInsets.top), weight: 1.0)
        occupancy.markOccupied(CGRect(x: 0, y: frameSize.height - safeAreaInsets.bottom, width: frameSize.width, height: safeAreaInsets.bottom), weight: 1.0)
        occupancy.markOccupied(CGRect(x: 0, y: 0, width: safeAreaInsets.left, height: frameSize.height), weight: 1.0)
        occupancy.markOccupied(CGRect(x: frameSize.width - safeAreaInsets.right, y: 0, width: safeAreaInsets.right, height: frameSize.height), weight: 1.0)
        
        // Generate candidates based on preferred region
        let candidates = generateCandidates(textSize: textSize, frameSize: frameSize)
        
        // Score each candidate
        var bestCandidate: CGRect?
        var bestScore: Float = Float.infinity
        
        for candidate in candidates {
            let score = occupancy.scoreRegion(candidate)
            if score < bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }
        
        // Fallback to center if no good placement found
        guard let placement = bestCandidate else {
            return TextPlacement(
                bounds: CGRect(
                    x: (frameSize.width - textSize.width) / 2,
                    y: (frameSize.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                ),
                confidence: 0.5,
                reason: .fallback,
                suggestedDepth: 0.8
            )
        }
        
        let reason: TextPlacement.PlacementReason
        if bestScore < 0.1 {
            reason = .optimal
        } else if segmentation != nil {
            reason = .avoidsSubject
        } else {
            reason = .optimal
        }
        
        return TextPlacement(
            bounds: placement,
            confidence: 1.0 - bestScore,
            reason: reason,
            suggestedDepth: 0.85  // Place text behind foreground
        )
    }
    
    // MARK: - Depth Suggestion
    
    /// Suggest depth value for text at a given position
    public func suggestDepth(
        for bounds: CGRect,
        depthMap: DepthMap,
        mode: CompositeMode
    ) async throws -> Float {
        
        switch mode {
        case .behindSubject:
            // Sample depth in the region and place text behind
            let avgDepth = sampleAverageDepth(depthMap, in: bounds)
            return min(1.0, avgDepth + 0.2)  // Place 0.2 behind average
            
        case .inFrontOfAll:
            return 0.0  // Nearest to camera
            
        case .depthSorted:
            return sampleAverageDepth(depthMap, in: bounds)
            
        case .parallax:
            return 0.5  // Mid-depth for parallax
        }
    }
    
    // MARK: - Layout Hints from AI
    
    /// Generate layout hints from AI analysis
    public func generateLayoutHints(
        saliency: SaliencyMap?,
        segmentation: SegmentationMask?,
        depthMap: DepthMap?,
        opticalFlow: OpticalFlow?
    ) -> LayoutHint {
        var avoidRegions: [CGRect] = []
        
        // Add salient regions to avoid
        if let saliency = saliency {
            avoidRegions.append(contentsOf: saliency.regions.map { $0.bounds })
        }
        
        // Add segmented people to avoid
        if let segmentation = segmentation {
            avoidRegions.append(segmentation.bounds)
        }
        
        // Motion direction
        let motionDir = opticalFlow?.dominantDirection
        
        // Average depth (if available)
        let avgDepth: Float = 0.5  // Default mid-depth
        
        return LayoutHint(
            avoidRegions: avoidRegions,
            suggestedRegions: [],  // Could compute inverse of avoid regions
            motionDirection: motionDir,
            averageDepth: avgDepth
        )
    }
    
    // MARK: - Private Helpers
    
    private func measureText(_ text: String, fontSize: CGFloat) -> CGSize {
        // Approximate measurement
        let avgCharWidth = fontSize * 0.6
        let lines = text.components(separatedBy: "\n")
        let maxLineLength = lines.map { $0.count }.max() ?? 0
        let lineHeight = fontSize * 1.4
        
        return CGSize(
            width: CGFloat(maxLineLength) * avgCharWidth,
            height: CGFloat(lines.count) * lineHeight
        )
    }
    
    private func generateCandidates(textSize: CGSize, frameSize: CGSize) -> [CGRect] {
        var candidates: [CGRect] = []
        
        let margin = minimumMargin
        let stepX: CGFloat = 50
        let stepY: CGFloat = 30
        
        switch preferredRegion {
        case .lowerThird:
            let startY = frameSize.height * 0.66
            for y in stride(from: startY, to: frameSize.height - textSize.height - margin, by: stepY) {
                for x in stride(from: margin, to: frameSize.width - textSize.width - margin, by: stepX) {
                    candidates.append(CGRect(x: x, y: y, width: textSize.width, height: textSize.height))
                }
            }
            
        case .upperThird:
            let endY = frameSize.height * 0.33
            for y in stride(from: margin + safeAreaInsets.top, to: endY, by: stepY) {
                for x in stride(from: margin, to: frameSize.width - textSize.width - margin, by: stepX) {
                    candidates.append(CGRect(x: x, y: y, width: textSize.width, height: textSize.height))
                }
            }
            
        case .center:
            let centerY = (frameSize.height - textSize.height) / 2
            let rangeY: CGFloat = 100
            for y in stride(from: centerY - rangeY, to: centerY + rangeY, by: stepY) {
                for x in stride(from: margin, to: frameSize.width - textSize.width - margin, by: stepX) {
                    candidates.append(CGRect(x: x, y: y, width: textSize.width, height: textSize.height))
                }
            }
            
        case .auto:
            // Generate candidates everywhere
            for y in stride(from: margin + safeAreaInsets.top, to: frameSize.height - textSize.height - margin - safeAreaInsets.bottom, by: stepY) {
                for x in stride(from: margin + safeAreaInsets.left, to: frameSize.width - textSize.width - margin - safeAreaInsets.right, by: stepX) {
                    candidates.append(CGRect(x: x, y: y, width: textSize.width, height: textSize.height))
                }
            }
        }
        
        return candidates
    }
    
    private func sampleAverageDepth(_ depthMap: DepthMap, in bounds: CGRect) -> Float {
        // For now, return a default value
        // In production, we'd sample the depth texture
        return 0.5
    }
}

// MARK: - Edge Insets (cross-platform)

public struct EdgeInsets: Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
    
    public static var zero: EdgeInsets { EdgeInsets() }
}
