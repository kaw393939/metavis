import Foundation
import Metal
import Accelerate
import CoreGraphics

// MARK: - Data Types

/// Exposure statistics for a frame
public struct ExposureStats: Sendable {
    public let mean: Float       // Average luminance
    public let min: Float        // Minimum luminance
    public let max: Float        // Maximum luminance
    public let standardDeviation: Float
    public let histogram: [Float]  // 256-bin histogram
    
    public init(mean: Float, min: Float, max: Float, standardDeviation: Float, histogram: [Float]) {
        self.mean = mean
        self.min = min
        self.max = max
        self.standardDeviation = standardDeviation
        self.histogram = histogram
    }
    
    /// Returns true if the image is likely underexposed
    public var isUnderexposed: Bool {
        return mean < 0.25
    }
    
    /// Returns true if the image is likely overexposed
    public var isOverexposed: Bool {
        return mean > 0.75
    }
    
    /// Returns a value from -1 (underexposed) to +1 (overexposed)
    public var exposureBias: Float {
        return (mean - 0.5) * 2.0
    }
}

/// Composition analysis using rule of thirds
public struct CompositionScore: Sendable {
    public let overallScore: Float  // 0-1, higher is better
    public let thirdLineScore: Float  // How well subjects align to third lines
    public let powerPointScore: Float  // How well subjects align to power points
    public let balanceScore: Float  // Left-right balance
    
    public init(overallScore: Float, thirdLineScore: Float, powerPointScore: Float, balanceScore: Float) {
        self.overallScore = overallScore
        self.thirdLineScore = thirdLineScore
        self.powerPointScore = powerPointScore
        self.balanceScore = balanceScore
    }
}

// MARK: - MetricCalculator

/// Pure math functions for image quality and composition metrics
public struct MetricCalculator {
    
    // MARK: - Sharpness
    
    /// Calculate sharpness using Laplacian variance
    /// Higher values indicate sharper images
    public static func calculateSharpness(from luminanceData: [Float], width: Int, height: Int) -> Float {
        guard width > 2 && height > 2 else { return 0 }
        
        // Laplacian kernel: [0, 1, 0; 1, -4, 1; 0, 1, 0]
        var laplacianSum: Float = 0
        var laplacianSumSq: Float = 0
        var count = 0
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = luminanceData[y * width + x]
                let top = luminanceData[(y - 1) * width + x]
                let bottom = luminanceData[(y + 1) * width + x]
                let left = luminanceData[y * width + (x - 1)]
                let right = luminanceData[y * width + (x + 1)]
                
                // Laplacian = 4 * center - neighbors
                let laplacian = 4.0 * center - top - bottom - left - right
                laplacianSum += laplacian
                laplacianSumSq += laplacian * laplacian
                count += 1
            }
        }
        
        guard count > 0 else { return 0 }
        
        let mean = laplacianSum / Float(count)
        let variance = (laplacianSumSq / Float(count)) - (mean * mean)
        
        // Return variance normalized to 0-1 range (assuming max variance ~1000)
        return min(variance / 1000.0, 1.0)
    }
    
    /// Calculate sharpness from a Metal texture
    public static func calculateSharpness(from texture: MTLTexture, device: MTLDevice) -> Float {
        let width = texture.width
        let height = texture.height
        
        // Read texture data
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        
        texture.getBytes(&pixelData, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
        
        // Convert to luminance
        var luminance = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(pixelData[i * 4]) / 255.0
            let g = Float(pixelData[i * 4 + 1]) / 255.0
            let b = Float(pixelData[i * 4 + 2]) / 255.0
            // Rec. 709 luminance
            luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        
        return calculateSharpness(from: luminance, width: width, height: height)
    }
    
    // MARK: - Exposure
    
    /// Calculate exposure statistics from luminance data
    public static func calculateExposureStats(from luminanceData: [Float]) -> ExposureStats {
        guard !luminanceData.isEmpty else {
            return ExposureStats(mean: 0.5, min: 0, max: 1, standardDeviation: 0, histogram: Array(repeating: 0, count: 256))
        }
        
        // Use Accelerate for fast statistics
        var mean: Float = 0
        var stdDev: Float = 0
        var minVal: Float = 0
        var maxVal: Float = 0
        
        vDSP_meanv(luminanceData, 1, &mean, vDSP_Length(luminanceData.count))
        vDSP_minv(luminanceData, 1, &minVal, vDSP_Length(luminanceData.count))
        vDSP_maxv(luminanceData, 1, &maxVal, vDSP_Length(luminanceData.count))
        
        // Calculate standard deviation
        var sumSquares: Float = 0
        vDSP_svesq(luminanceData, 1, &sumSquares, vDSP_Length(luminanceData.count))
        let variance = (sumSquares / Float(luminanceData.count)) - (mean * mean)
        stdDev = sqrt(max(0, variance))
        
        // Build histogram
        var histogram = [Float](repeating: 0, count: 256)
        for value in luminanceData {
            let bin = min(255, max(0, Int(value * 255.0)))
            histogram[bin] += 1
        }
        
        // Normalize histogram
        let total = Float(luminanceData.count)
        for i in 0..<256 {
            histogram[i] /= total
        }
        
        return ExposureStats(
            mean: mean,
            min: minVal,
            max: maxVal,
            standardDeviation: stdDev,
            histogram: histogram
        )
    }
    
    /// Calculate exposure statistics from a Metal texture
    public static func calculateExposureStats(from texture: MTLTexture) -> ExposureStats {
        let width = texture.width
        let height = texture.height
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        
        texture.getBytes(&pixelData, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
        
        // Convert to luminance
        var luminance = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Float(pixelData[i * 4]) / 255.0
            let g = Float(pixelData[i * 4 + 1]) / 255.0
            let b = Float(pixelData[i * 4 + 2]) / 255.0
            luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        
        return calculateExposureStats(from: luminance)
    }
    
    // MARK: - Composition
    
    /// Calculate composition score based on rule of thirds
    /// - Parameters:
    ///   - saliencyRegions: Regions of interest with normalized bounds
    ///   - faceRegions: Face bounding boxes with normalized bounds
    ///   - gridWeight: Weight for third-line proximity (0-1)
    public static func calculateCompositionScore(
        saliencyRegions: [CGRect],
        faceRegions: [CGRect],
        gridWeight: Float = 0.7
    ) -> CompositionScore {
        // Rule of thirds lines at 1/3 and 2/3
        let thirdLines: [CGFloat] = [1.0/3.0, 2.0/3.0]
        
        // Power points at intersections
        let powerPoints: [CGPoint] = [
            CGPoint(x: 1.0/3.0, y: 1.0/3.0),
            CGPoint(x: 2.0/3.0, y: 1.0/3.0),
            CGPoint(x: 1.0/3.0, y: 2.0/3.0),
            CGPoint(x: 2.0/3.0, y: 2.0/3.0)
        ]
        
        let allRegions = saliencyRegions + faceRegions
        
        guard !allRegions.isEmpty else {
            return CompositionScore(overallScore: 0.5, thirdLineScore: 0.5, powerPointScore: 0.5, balanceScore: 0.5)
        }
        
        // Calculate third line score
        var thirdLineScore: Float = 0
        for region in allRegions {
            let centerX = region.midX
            let centerY = region.midY
            
            // Distance to nearest third line
            let xDistance = min(abs(centerX - thirdLines[0]), abs(centerX - thirdLines[1]))
            let yDistance = min(abs(centerY - thirdLines[0]), abs(centerY - thirdLines[1]))
            
            // Score is higher when closer to third lines (within 10% tolerance)
            let xScore = max(0, 1.0 - Float(xDistance) * 10.0)
            let yScore = max(0, 1.0 - Float(yDistance) * 10.0)
            
            thirdLineScore += (xScore + yScore) / 2.0
        }
        thirdLineScore /= Float(allRegions.count)
        
        // Calculate power point score
        var powerPointScore: Float = 0
        for region in allRegions {
            let center = CGPoint(x: region.midX, y: region.midY)
            
            var minDistance: CGFloat = 2.0  // Max possible distance
            for point in powerPoints {
                let distance = sqrt(pow(center.x - point.x, 2) + pow(center.y - point.y, 2))
                minDistance = min(minDistance, distance)
            }
            
            // Score is higher when closer to power points (within 15% tolerance)
            powerPointScore += max(0, 1.0 - Float(minDistance) * 6.67)
        }
        powerPointScore /= Float(allRegions.count)
        
        // Calculate balance score (left-right distribution)
        var leftWeight: CGFloat = 0
        var rightWeight: CGFloat = 0
        for region in allRegions {
            let weight = region.width * region.height
            if region.midX < 0.5 {
                leftWeight += weight
            } else {
                rightWeight += weight
            }
        }
        
        let totalWeight = leftWeight + rightWeight
        let balanceScore: Float = totalWeight > 0 ? 1.0 - Float(abs(leftWeight - rightWeight) / totalWeight) : 0.5
        
        // Combine scores
        let overallScore = gridWeight * thirdLineScore + (1.0 - gridWeight) * powerPointScore * 0.5 + balanceScore * 0.3
        
        return CompositionScore(
            overallScore: min(1.0, overallScore),
            thirdLineScore: thirdLineScore,
            powerPointScore: powerPointScore,
            balanceScore: balanceScore
        )
    }
    
    // MARK: - Negative Space
    
    /// Find rectangular zones with low saliency (safe for text placement)
    /// - Parameters:
    ///   - saliencyMap: 2D array of saliency values (0-1)
    ///   - mapWidth: Width of saliency map
    ///   - mapHeight: Height of saliency map
    ///   - minWidth: Minimum width of zone (normalized 0-1)
    ///   - minHeight: Minimum height of zone (normalized 0-1)
    ///   - threshold: Saliency threshold below which is considered "safe"
    /// - Returns: Array of safe zone rectangles in normalized coordinates
    public static func findNegativeSpace(
        saliencyMap: [Float],
        mapWidth: Int,
        mapHeight: Int,
        minWidth: Float,
        minHeight: Float,
        threshold: Float = 0.3
    ) -> [CGRect] {
        guard !saliencyMap.isEmpty else { return [] }
        
        // Create binary mask (true = safe)
        var safeMask = [Bool](repeating: false, count: mapWidth * mapHeight)
        for i in 0..<saliencyMap.count {
            safeMask[i] = saliencyMap[i] < threshold
        }
        
        var zones: [CGRect] = []
        let minW = Int(Float(mapWidth) * minWidth)
        let minH = Int(Float(mapHeight) * minHeight)
        
        // Simple grid search for valid rectangles
        let stepX = max(1, mapWidth / 20)
        let stepY = max(1, mapHeight / 20)
        
        for y in stride(from: 0, to: mapHeight - minH, by: stepY) {
            for x in stride(from: 0, to: mapWidth - minW, by: stepX) {
                // Check if this rectangle is mostly safe
                var safeCount = 0
                var totalCount = 0
                
                for checkY in y..<min(y + minH, mapHeight) {
                    for checkX in x..<min(x + minW, mapWidth) {
                        if safeMask[checkY * mapWidth + checkX] {
                            safeCount += 1
                        }
                        totalCount += 1
                    }
                }
                
                // If >80% safe, add as candidate zone
                if totalCount > 0 && Float(safeCount) / Float(totalCount) > 0.8 {
                    let rect = CGRect(
                        x: CGFloat(x) / CGFloat(mapWidth),
                        y: CGFloat(y) / CGFloat(mapHeight),
                        width: CGFloat(minW) / CGFloat(mapWidth),
                        height: CGFloat(minH) / CGFloat(mapHeight)
                    )
                    
                    // Avoid duplicates/overlapping
                    let overlaps = zones.contains { existing in
                        existing.intersects(rect) && existing.intersection(rect).width > rect.width * 0.5
                    }
                    
                    if !overlaps {
                        zones.append(rect)
                    }
                }
            }
        }
        
        return zones
    }
    
    // MARK: - Text Placement Scoring
    
    /// Score a potential text placement position
    /// - Parameters:
    ///   - rect: Proposed text bounding box (normalized)
    ///   - saliencyRegions: Regions to avoid
    ///   - faceRegions: Face regions to avoid
    ///   - preferredAnchor: Preferred screen region
    /// - Returns: Score from 0 (poor) to 1 (excellent)
    public static func scoreTextPlacement(
        rect: CGRect,
        saliencyRegions: [CGRect],
        faceRegions: [CGRect],
        preferredAnchor: TextAnchor
    ) -> Float {
        var score: Float = 1.0
        
        // Penalize overlap with salient regions
        for salient in saliencyRegions {
            if rect.intersects(salient) {
                let intersection = rect.intersection(salient)
                let overlapRatio = Float((intersection.width * intersection.height) / (rect.width * rect.height))
                score -= overlapRatio * 0.5
            }
        }
        
        // Heavy penalty for overlapping faces
        for face in faceRegions {
            if rect.intersects(face) {
                score -= 0.8
            }
        }
        
        // Bonus for being near preferred anchor
        let anchorScore = anchorProximityScore(rect: rect, anchor: preferredAnchor)
        score += anchorScore * 0.2
        
        // Bonus for being in safe margins
        let marginScore = marginSafetyScore(rect: rect)
        score += marginScore * 0.1
        
        return max(0, min(1, score))
    }
    
    // MARK: - Private Helpers
    
    private static func anchorProximityScore(rect: CGRect, anchor: TextAnchor) -> Float {
        let targetPoint: CGPoint
        
        switch anchor {
        case .topLeft: targetPoint = CGPoint(x: 0.15, y: 0.15)
        case .topCenter: targetPoint = CGPoint(x: 0.5, y: 0.15)
        case .topRight: targetPoint = CGPoint(x: 0.85, y: 0.15)
        case .centerLeft: targetPoint = CGPoint(x: 0.15, y: 0.5)
        case .center: targetPoint = CGPoint(x: 0.5, y: 0.5)
        case .centerRight: targetPoint = CGPoint(x: 0.85, y: 0.5)
        case .bottomLeft: targetPoint = CGPoint(x: 0.15, y: 0.85)
        case .bottomCenter: targetPoint = CGPoint(x: 0.5, y: 0.85)
        case .bottomRight: targetPoint = CGPoint(x: 0.85, y: 0.85)
        }
        
        let distance = sqrt(pow(rect.midX - targetPoint.x, 2) + pow(rect.midY - targetPoint.y, 2))
        return max(0, 1.0 - Float(distance))
    }
    
    private static func marginSafetyScore(rect: CGRect) -> Float {
        let margin: CGFloat = 0.05  // 5% margin
        
        var score: Float = 1.0
        
        // Check if too close to edges
        if rect.minX < margin || rect.maxX > 1.0 - margin {
            score *= 0.5
        }
        if rect.minY < margin || rect.maxY > 1.0 - margin {
            score *= 0.5
        }
        
        return score
    }
}
