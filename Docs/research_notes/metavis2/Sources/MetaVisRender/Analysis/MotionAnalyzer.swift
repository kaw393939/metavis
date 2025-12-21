import Foundation
import Vision
import AVFoundation
import CoreImage

/// Analyzes motion smoothness, jitter, and frame timing in videos
public class MotionAnalyzer {
    
    public init() {}
    
    // MARK: - Main Analysis
    
    /// Analyze motion smoothness using optical flow
    public func analyzeMotion(videoURL: URL) async throws -> MotionAnalysisResult {
        
        // Extract frames for optical flow analysis
        let frames = try await extractFrames(videoURL, maxFrames: 30)
        
        guard frames.count >= 2 else {
            throw MotionAnalysisError.insufficientFrames
        }
        
        var flowResults: [OpticalFlowResult] = []
        
        // Analyze optical flow between consecutive frames
        for i in 1..<frames.count {
            let flow = try await calculateOpticalFlow(
                from: frames[i-1],
                to: frames[i]
            )
            flowResults.append(flow)
        }
        
        // Calculate metrics
        let smoothness = calculateSmoothness(flowResults)
        let jitter = detectJitter(flowResults)
        let stutter = detectStutter(flowResults)
        let consistency = analyzeFrameTiming(flowResults)
        
        let issues = detectMotionIssues(
            smoothness: smoothness,
            jitter: jitter,
            stutter: stutter
        )
        
        return MotionAnalysisResult(
            smoothness: smoothness,
            jitter: jitter,
            stutter: stutter,
            frameTimeConsistency: consistency,
            issues: issues
        )
    }
    
    // MARK: - Optical Flow
    
    private func calculateOpticalFlow(
        from sourceImage: CIImage,
        to targetImage: CIImage
    ) async throws -> OpticalFlowResult {
        
        // Create optical flow request
        let request = VNGenerateOpticalFlowRequest(targetedCIImage: targetImage, options: [:])
        request.computationAccuracy = .high
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        
        // Process source image
        let handler = VNImageRequestHandler(ciImage: sourceImage, options: [:])
        try handler.perform([request])
        
        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            throw MotionAnalysisError.opticalFlowFailed
        }
        
        // Extract flow vectors from pixel buffer
        let flowVectors = try extractFlowVectors(observation.pixelBuffer)
        
        return OpticalFlowResult(
            averageMagnitude: flowVectors.magnitude,
            direction: flowVectors.direction,
            consistency: flowVectors.consistency,
            maxMagnitude: flowVectors.maxMagnitude
        )
    }
    
    private func extractFlowVectors(_ pixelBuffer: CVPixelBuffer) throws -> FlowVectors {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MotionAnalysisError.pixelBufferAccessFailed
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        var totalMagnitude: Double = 0
        var totalDirX: Double = 0
        var totalDirY: Double = 0
        var maxMagnitude: Double = 0
        var count = 0
        
        // Sample every Nth pixel to avoid processing entire buffer
        let sampleStride = 8
        
        for y in Swift.stride(from: 0, to: height, by: sampleStride) {
            for x in Swift.stride(from: 0, to: width, by: sampleStride) {
                let offset = y * bytesPerRow + x * 8  // 2 floats = 8 bytes
                let pointer = baseAddress.advanced(by: offset).assumingMemoryBound(to: Float.self)
                
                let dx = Double(pointer[0])
                let dy = Double(pointer[1])
                
                let magnitude = sqrt(dx * dx + dy * dy)
                
                totalMagnitude += magnitude
                totalDirX += dx
                totalDirY += dy
                maxMagnitude = max(maxMagnitude, magnitude)
                count += 1
            }
        }
        
        let avgMagnitude = count > 0 ? totalMagnitude / Double(count) : 0
        let avgDirX = count > 0 ? totalDirX / Double(count) : 0
        let avgDirY = count > 0 ? totalDirY / Double(count) : 0
        
        // Calculate consistency (how uniform is the flow?)
        let directionMagnitude = sqrt(avgDirX * avgDirX + avgDirY * avgDirY)
        let consistency = avgMagnitude > 0 ? directionMagnitude / avgMagnitude : 1.0
        
        return FlowVectors(
            magnitude: avgMagnitude,
            direction: atan2(avgDirY, avgDirX),
            consistency: consistency,
            maxMagnitude: maxMagnitude
        )
    }
    
    // MARK: - Smoothness Analysis
    
    private func calculateSmoothness(_ flows: [OpticalFlowResult]) -> Double {
        guard flows.count > 1 else { return 1.0 }
        
        // Calculate how smooth the motion magnitude changes are
        var magnitudeChanges: [Double] = []
        
        for i in 1..<flows.count {
            let change = abs(flows[i].averageMagnitude - flows[i-1].averageMagnitude)
            magnitudeChanges.append(change)
        }
        
        // Calculate variance of changes (lower = smoother)
        let mean = magnitudeChanges.reduce(0, +) / Double(magnitudeChanges.count)
        let variance = magnitudeChanges.map { pow($0 - mean, 2) }.reduce(0, +) / Double(magnitudeChanges.count)
        let stdDev = sqrt(variance)
        
        // Normalize to 0-1 range (1 = perfectly smooth)
        // Use sigmoid-like function to map stdDev to smoothness score
        let smoothness = 1.0 / (1.0 + stdDev * 10.0)
        
        return smoothness
    }
    
    private func detectJitter(_ flows: [OpticalFlowResult]) -> Double {
        guard flows.count > 2 else { return 0.0 }
        
        // Jitter = high-frequency oscillations in flow magnitude
        var jitterScore = 0.0
        
        for i in 2..<flows.count {
            let diff1 = flows[i].averageMagnitude - flows[i-1].averageMagnitude
            let diff2 = flows[i-1].averageMagnitude - flows[i-2].averageMagnitude
            
            // If direction keeps changing = jitter
            if (diff1 > 0 && diff2 < 0) || (diff1 < 0 && diff2 > 0) {
                jitterScore += abs(diff1 - diff2)
            }
        }
        
        // Normalize by number of comparisons
        return jitterScore / Double(flows.count - 2)
    }
    
    private func detectStutter(_ flows: [OpticalFlowResult]) -> Bool {
        guard flows.count > 3 else { return false }
        
        // Stutter = sudden large changes in motion
        let magnitudes = flows.map { $0.averageMagnitude }
        let mean = magnitudes.reduce(0, +) / Double(magnitudes.count)
        
        // Check for outliers (>3 std deviations from mean)
        let variance = magnitudes.map { pow($0 - mean, 2) }.reduce(0, +) / Double(magnitudes.count)
        let stdDev = sqrt(variance)
        
        let outliers = magnitudes.filter { abs($0 - mean) > 3 * stdDev }
        
        return !outliers.isEmpty
    }
    
    private func analyzeFrameTiming(_ flows: [OpticalFlowResult]) -> Double {
        // In real implementation, would analyze actual frame timestamps
        // For now, use flow consistency as proxy
        let avgConsistency = flows.map { $0.consistency }.reduce(0, +) / Double(flows.count)
        return avgConsistency
    }
    
    // MARK: - Issue Detection
    
    private func detectMotionIssues(
        smoothness: Double,
        jitter: Double,
        stutter: Bool
    ) -> [MotionIssue] {
        var issues: [MotionIssue] = []
        
        if smoothness < 0.9 {
            issues.append(MotionIssue(
                type: "choppy_motion",
                severity: smoothness < 0.7 ? "high" : "medium",
                description: "Motion not smooth (score: \(String(format: "%.2f", smoothness)))"
            ))
        }
        
        if jitter > 0.1 {
            issues.append(MotionIssue(
                type: "jitter",
                severity: jitter > 0.2 ? "high" : "medium",
                description: "Camera jitter detected (score: \(String(format: "%.2f", jitter)))"
            ))
        }
        
        if stutter {
            issues.append(MotionIssue(
                type: "stutter",
                severity: "high",
                description: "Frame timing stutter detected"
            ))
        }
        
        return issues
    }
    
    // MARK: - Frame Extraction
    
    private func extractFrames(_ videoURL: URL, maxFrames: Int) async throws -> [CIImage] {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw MotionAnalysisError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Extract frames at regular intervals
        let frameCount = min(maxFrames, Int(durationSeconds * 30))  // Up to 30fps
        var frames: [CIImage] = []
        
        for i in 0..<frameCount {
            let time = CMTime(
                seconds: durationSeconds * Double(i) / Double(frameCount - 1),
                preferredTimescale: 600
            )
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            frames.append(CIImage(cgImage: cgImage))
        }
        
        return frames
    }
}

// MARK: - Result Types

public struct MotionAnalysisResult: Codable {
    public let smoothness: Double  // 0.0 - 1.0 (1 = perfectly smooth)
    public let jitter: Double  // 0.0+ (0 = no jitter)
    public let stutter: Bool
    public let frameTimeConsistency: Double  // 0.0 - 1.0
    public let issues: [MotionIssue]
    
    /// Human-readable grade
    public var grade: String {
        switch smoothness {
        case 0.98...1.0: return "A+"
        case 0.95..<0.98: return "A"
        case 0.90..<0.95: return "B"
        case 0.80..<0.90: return "C"
        default: return "F"
        }
    }
}

public struct MotionIssue: Codable {
    public let type: String
    public let severity: String
    public let description: String
}

struct OpticalFlowResult {
    let averageMagnitude: Double
    let direction: Double  // radians
    let consistency: Double  // 0-1
    let maxMagnitude: Double
}

struct FlowVectors {
    let magnitude: Double
    let direction: Double
    let consistency: Double
    let maxMagnitude: Double
}

// MARK: - Errors

public enum MotionAnalysisError: Error {
    case noVideoTrack
    case insufficientFrames
    case opticalFlowFailed
    case pixelBufferAccessFailed
}
