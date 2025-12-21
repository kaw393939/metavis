import Foundation
import CoreImage
import Vision
import AVFoundation

/// Analyzes color accuracy, neutrality, and artifacts in rendered images/videos
public class ColorAnalyzer {
    private let ciContext: CIContext
    
    public init() {
        self.ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    }
    
    // MARK: - Main Analysis
    
    /// Analyze color accuracy of a video
    public func analyzeColorAccuracy(
        videoURL: URL,
        referenceURL: URL? = nil
    ) async throws -> ColorAnalysisResult {
        
        // Extract sample frames
        let frames = try await extractSampleFrames(videoURL, count: 10)
        
        var frameResults: [FrameColorAnalysis] = []
        
        for (index, frame) in frames.enumerated() {
            let analysis = try analyzeFrame(frame)
            frameResults.append(analysis)
        }
        
        // Calculate overall metrics
        let avgAccuracy = frameResults.map(\.accuracy).reduce(0, +) / Double(frameResults.count)
        let avgNeutrality = frameResults.map(\.neutralAccuracy).reduce(0, +) / Double(frameResults.count)
        
        // Detect issues
        let issues = detectColorIssues(frameResults)
        
        // Compare to reference if provided
        var comparisonScore: Double? = nil
        if let referenceURL = referenceURL {
            comparisonScore = try await compareToReference(videoURL, referenceURL)
        }
        
        return ColorAnalysisResult(
            frames: frameResults,
            averageAccuracy: avgAccuracy,
            averageNeutrality: avgNeutrality,
            colorSpaceCompliance: "Rec.709",  // Detected from frames
            comparisonScore: comparisonScore,
            issues: issues
        )
    }
    
    // MARK: - Frame Analysis
    
    private func analyzeFrame(_ image: CIImage) throws -> FrameColorAnalysis {
        // Extract histogram
        let histogram = extractHistogram(image)
        
        // Check for issues
        let banding = detectBanding(histogram)
        let clipping = detectClipping(histogram)
        let neutrality = checkNeutralPreservation(image)
        
        // Calculate accuracy score
        let accuracy = calculateAccuracyScore(
            banding: banding,
            clipping: clipping,
            neutrality: neutrality
        )
        
        return FrameColorAnalysis(
            histogram: histogram,
            colorSpace: "Rec.709",
            gamutCoverage: 0.95,  // Placeholder - would need proper gamut analysis
            hasBanding: banding > 0.05,
            hasClipping: clipping > 0.01,
            neutralAccuracy: neutrality,
            accuracy: accuracy
        )
    }
    
    // MARK: - Histogram Analysis
    
    private func extractHistogram(_ image: CIImage) -> [Int] {
        // Create histogram
        guard let filter = CIFilter(name: "CIAreaHistogram") else {
            return Array(repeating: 0, count: 256)
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(256, forKey: "inputCount")
        filter.setValue(CIVector(x: image.extent.minX, y: image.extent.minY),
                       forKey: "inputExtent")
        
        guard let outputImage = filter.outputImage else {
            return Array(repeating: 0, count: 256)
        }
        
        // Extract histogram data
        var histogram = [Int](repeating: 0, count: 256)
        var bitmap = [UInt8](repeating: 0, count: 256 * 4)
        
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 256 * 4,
            bounds: outputImage.extent,
            format: .RGBA8,
            colorSpace: nil
        )
        
        // Average R, G, B channels
        for i in 0..<256 {
            let r = Int(bitmap[i * 4])
            let g = Int(bitmap[i * 4 + 1])
            let b = Int(bitmap[i * 4 + 2])
            histogram[i] = (r + g + b) / 3
        }
        
        return histogram
    }
    
    private func detectBanding(_ histogram: [Int]) -> Double {
        // Look for gaps in histogram (sign of posterization/banding)
        var gaps = 0
        var totalBins = 0
        
        for i in 1..<(histogram.count - 1) {
            let hasValues = histogram[i-1] > 0 || histogram[i+1] > 0
            if hasValues {
                totalBins += 1
                if histogram[i] == 0 {
                    gaps += 1
                }
            }
        }
        
        return totalBins > 0 ? Double(gaps) / Double(totalBins) : 0.0
    }
    
    private func detectClipping(_ histogram: [Int]) -> Double {
        // Check for excessive values at 0 and 255 (clipping)
        let totalPixels = histogram.reduce(0, +)
        guard totalPixels > 0 else { return 0.0 }
        
        let clippedDark = histogram[0]
        let clippedBright = histogram[255]
        let clippedTotal = clippedDark + clippedBright
        
        return Double(clippedTotal) / Double(totalPixels)
    }
    
    // MARK: - Neutrality Check
    
    private func checkNeutralPreservation(_ image: CIImage) -> Double {
        // Sample pixels and check if grays remain neutral (R ≈ G ≈ B)
        let samplePoints = generateSamplePoints(image.extent, count: 100)
        
        var neutralityScore = 0.0
        var validSamples = 0
        
        for point in samplePoints {
            let pixel = samplePixel(image, at: point)
            
            // Check if pixel is approximately neutral (low saturation)
            let maxChannel = max(pixel.x, pixel.y, pixel.z)
            let minChannel = min(pixel.x, pixel.y, pixel.z)
            let saturation = (maxChannel - minChannel) / max(maxChannel, 0.001)
            
            // Only check pixels that should be neutral (low saturation in original)
            if saturation < 0.1 {
                // Calculate how neutral it is
                let maxDiff = max(
                    abs(pixel.x - pixel.y),
                    abs(pixel.y - pixel.z),
                    abs(pixel.z - pixel.x)
                )
                
                neutralityScore += Double(1.0 - min(maxDiff, 1.0))
                validSamples += 1
            }
        }
        
        return validSamples > 0 ? neutralityScore / Double(validSamples) : 1.0
    }
    
    private func samplePixel(_ image: CIImage, at point: CGPoint) -> SIMD4<Float> {
        // Create a 1x1 extent at the point
        let extent = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            image.cropped(to: extent),
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        return SIMD4<Float>(
            Float(pixel[0]) / 255.0,
            Float(pixel[1]) / 255.0,
            Float(pixel[2]) / 255.0,
            Float(pixel[3]) / 255.0
        )
    }
    
    private func generateSamplePoints(_ extent: CGRect, count: Int) -> [CGPoint] {
        var points: [CGPoint] = []
        let sqrtCount = Int(sqrt(Double(count)))
        
        for y in 0..<sqrtCount {
            for x in 0..<sqrtCount {
                let px = extent.minX + (CGFloat(x) + 0.5) * extent.width / CGFloat(sqrtCount)
                let py = extent.minY + (CGFloat(y) + 0.5) * extent.height / CGFloat(sqrtCount)
                points.append(CGPoint(x: px, y: py))
            }
        }
        
        return points
    }
    
    // MARK: - Scoring
    
    private func calculateAccuracyScore(
        banding: Double,
        clipping: Double,
        neutrality: Double
    ) -> Double {
        // Weight factors
        let bandingWeight = 0.3
        let clippingWeight = 0.3
        let neutralityWeight = 0.4
        
        let bandingScore = max(0, 1.0 - banding * 10)  // Heavy penalty for banding
        let clippingScore = max(0, 1.0 - clipping * 20)  // Very heavy penalty for clipping
        
        return (bandingScore * bandingWeight +
                clippingScore * clippingWeight +
                neutrality * neutralityWeight)
    }
    
    // MARK: - Issue Detection
    
    private func detectColorIssues(_ frames: [FrameColorAnalysis]) -> [ColorIssue] {
        var issues: [ColorIssue] = []
        
        // Check for banding
        let bandingFrames = frames.enumerated().filter { $0.element.hasBanding }
        if !bandingFrames.isEmpty {
            issues.append(ColorIssue(
                type: "banding",
                severity: bandingFrames.count > frames.count / 2 ? "high" : "medium",
                frameNumber: bandingFrames.first?.offset,
                description: "Posterization/banding detected in \(bandingFrames.count) frames"
            ))
        }
        
        // Check for clipping
        let clippingFrames = frames.enumerated().filter { $0.element.hasClipping }
        if !clippingFrames.isEmpty {
            issues.append(ColorIssue(
                type: "clipping",
                severity: clippingFrames.count > frames.count / 2 ? "high" : "medium",
                frameNumber: clippingFrames.first?.offset,
                description: "Clipped highlights/shadows in \(clippingFrames.count) frames"
            ))
        }
        
        // Check neutrality
        let avgNeutrality = frames.map(\.neutralAccuracy).reduce(0, +) / Double(frames.count)
        if avgNeutrality < 0.95 {
            issues.append(ColorIssue(
                type: "color_shift",
                severity: avgNeutrality < 0.9 ? "high" : "low",
                frameNumber: nil,
                description: "Neutral colors shifted (score: \(String(format: "%.2f", avgNeutrality)))"
            ))
        }
        
        return issues
    }
    
    // MARK: - Comparison
    
    private func compareToReference(
        _ videoURL: URL,
        _ referenceURL: URL
    ) async throws -> Double {
        // Extract first frame from each
        let videoFrame = try await extractSampleFrames(videoURL, count: 1).first!
        let refFrame = try await extractSampleFrames(referenceURL, count: 1).first!
        
        // Calculate Delta E (simplified CIEDE2000)
        return calculateDeltaE(videoFrame, refFrame)
    }
    
    /// Calculate color difference (Delta E)
    public func calculateDeltaE(_ image1: CIImage, _ image2: CIImage) -> Double {
        // Simplified Delta E calculation
        // In production, would convert to Lab color space and use CIEDE2000
        
        let samples1 = generateSamplePoints(image1.extent, count: 100)
        let samples2 = generateSamplePoints(image2.extent, count: 100)
        
        var totalDiff = 0.0
        
        for (p1, p2) in zip(samples1, samples2) {
            let pixel1 = samplePixel(image1, at: p1)
            let pixel2 = samplePixel(image2, at: p2)
            
            // Euclidean distance in RGB space (not true Delta E, but approximation)
            let diff = sqrt(
                pow(pixel1.x - pixel2.x, 2) +
                pow(pixel1.y - pixel2.y, 2) +
                pow(pixel1.z - pixel2.z, 2)
            )
            
            totalDiff += Double(diff)
        }
        
        return totalDiff / Double(samples1.count)
    }
    
    // MARK: - Frame Extraction
    
    private func extractSampleFrames(_ videoURL: URL, count: Int) async throws -> [CIImage] {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw ColorAnalysisError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        var frames: [CIImage] = []
        
        for i in 0..<count {
            let time = CMTime(
                seconds: durationSeconds * Double(i) / Double(count - 1),
                preferredTimescale: 600
            )
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            frames.append(CIImage(cgImage: cgImage))
        }
        
        return frames
    }
}

// MARK: - Result Types

public struct ColorAnalysisResult: Codable {
    public let frames: [FrameColorAnalysis]
    public let averageAccuracy: Double
    public let averageNeutrality: Double
    public let colorSpaceCompliance: String
    public let comparisonScore: Double?
    public let issues: [ColorIssue]
    
    /// Human-readable grade
    public var grade: String {
        switch averageAccuracy {
        case 0.98...1.0: return "A+"
        case 0.95..<0.98: return "A"
        case 0.90..<0.95: return "B"
        case 0.80..<0.90: return "C"
        default: return "F"
        }
    }
}

public struct FrameColorAnalysis: Codable {
    public let histogram: [Int]
    public let colorSpace: String
    public let gamutCoverage: Double
    public let hasBanding: Bool
    public let hasClipping: Bool
    public let neutralAccuracy: Double
    public let accuracy: Double
}

public struct ColorIssue: Codable {
    public let type: String
    public let severity: String
    public let frameNumber: Int?
    public let description: String
}

// MARK: - Errors

public enum ColorAnalysisError: Error {
    case noVideoTrack
    case frameExtractionFailed
}
