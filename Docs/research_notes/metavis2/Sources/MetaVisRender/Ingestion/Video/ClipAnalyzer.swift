// Sources/MetaVisRender/Ingestion/Video/ClipAnalyzer.swift
// Sprint 03: Shot classification, motion analysis, and quality assessment

import AVFoundation
import CoreImage
import Accelerate
import Foundation
import simd

// MARK: - Clip Analyzer

/// Analyzes video clips for shot type, motion, and quality metrics
public actor ClipAnalyzer {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Number of frames to sample for analysis
        public let sampleFrameCount: Int
        /// Resolution to downsample frames for analysis
        public let analysisResolution: Int
        /// Motion threshold for detecting camera movement
        public let motionThreshold: Float
        /// Quality threshold for flagging issues
        public let qualityThreshold: Float
        
        public init(
            sampleFrameCount: Int = 24,
            analysisResolution: Int = 256,
            motionThreshold: Float = 0.05,
            qualityThreshold: Float = 0.3
        ) {
            self.sampleFrameCount = sampleFrameCount
            self.analysisResolution = analysisResolution
            self.motionThreshold = motionThreshold
            self.qualityThreshold = qualityThreshold
        }
        
        public static let `default` = Config()
        
        public static let fast = Config(
            sampleFrameCount: 12,
            analysisResolution: 128
        )
        
        public static let detailed = Config(
            sampleFrameCount: 48,
            analysisResolution: 512
        )
    }
    
    private let config: Config
    private let ciContext: CIContext
    
    public init(config: Config = .default) {
        self.config = config
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }
    
    // MARK: - Public API
    
    /// Perform full clip analysis
    public func analyze(url: URL) async throws -> ClipAnalysisResult {
        let asset = AVAsset(url: url)
        
        guard try await asset.load(.isReadable) else {
            throw IngestionError.unsupportedFormat(url.pathExtension)
        }
        
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            throw IngestionError.corruptedFile("Invalid duration")
        }
        
        // Sample frames
        let frames = try await sampleFrames(from: asset)
        guard !frames.isEmpty else {
            throw IngestionError.corruptedFile("Could not extract frames")
        }
        
        // Analyze components
        let shotType = classifyShot(frames: frames)
        let motionSummary = analyzeMotion(frames: frames)
        let qualityFlags = assessQuality(frames: frames)
        let colorAnalysis = analyzeColor(frames: frames)
        
        return ClipAnalysisResult(
            duration: duration,
            frameCount: frames.count,
            shotType: shotType,
            motionSummary: motionSummary,
            qualityFlags: qualityFlags,
            colorAnalysis: colorAnalysis,
            analysisTimestamp: Date()
        )
    }
    
    /// Quick shot classification only
    public func classifyShot(url: URL) async throws -> ShotClassification {
        let asset = AVAsset(url: url)
        let frames = try await sampleFrames(from: asset, count: 8)
        return classifyShot(frames: frames)
    }
    
    /// Motion analysis only
    public func analyzeMotion(url: URL) async throws -> MotionSummary {
        let asset = AVAsset(url: url)
        let frames = try await sampleFrames(from: asset)
        return analyzeMotion(frames: frames)
    }
    
    /// Quality assessment only
    public func assessQuality(url: URL) async throws -> [QualityFlag] {
        let asset = AVAsset(url: url)
        let frames = try await sampleFrames(from: asset)
        return assessQuality(frames: frames)
    }
    
    // MARK: - Frame Sampling
    
    private func sampleFrames(
        from asset: AVAsset,
        count: Int? = nil
    ) async throws -> [AnalyzedFrame] {
        let duration = try await asset.load(.duration).seconds
        let frameCount = count ?? config.sampleFrameCount
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: config.analysisResolution,
            height: config.analysisResolution
        )
        
        let interval = duration / Double(frameCount + 1)
        var frames: [AnalyzedFrame] = []
        
        for i in 1...frameCount {
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            
            do {
                let (cgImage, actualTime) = try await generator.image(at: time)
                let metrics = analyzeFrame(cgImage)
                
                frames.append(AnalyzedFrame(
                    timestamp: actualTime.seconds,
                    image: cgImage,
                    metrics: metrics
                ))
            } catch {
                continue
            }
        }
        
        return frames
    }
    
    private func analyzeFrame(_ image: CGImage) -> FrameMetrics {
        let width = image.width
        let height = image.height
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else {
            return FrameMetrics.empty
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let pixelCount = width * height
        
        var sumR: Float = 0
        var sumG: Float = 0
        var sumB: Float = 0
        var sumLum: Float = 0
        var minLum: Float = 1.0
        var maxLum: Float = 0.0
        
        // Edge detection for sharpness
        var edgeSum: Float = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Float(buffer[i]) / 255.0
                let g = Float(buffer[i + 1]) / 255.0
                let b = Float(buffer[i + 2]) / 255.0
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                sumR += r
                sumG += g
                sumB += b
                sumLum += lum
                minLum = Swift.min(minLum, lum)
                maxLum = Swift.max(maxLum, lum)
                
                // Simple Sobel edge detection for sharpness
                if x > 0 && x < width - 1 && y > 0 && y < height - 1 {
                    let left = Float(buffer[(y * width + x - 1) * 4]) / 255.0
                    let right = Float(buffer[(y * width + x + 1) * 4]) / 255.0
                    let up = Float(buffer[((y - 1) * width + x) * 4]) / 255.0
                    let down = Float(buffer[((y + 1) * width + x) * 4]) / 255.0
                    let gx = right - left
                    let gy = down - up
                    edgeSum += sqrt(gx * gx + gy * gy)
                }
            }
        }
        
        let count = Float(pixelCount)
        let meanR = sumR / count
        let meanG = sumG / count
        let meanB = sumB / count
        let meanLum = sumLum / count
        
        // Calculate variance for noise estimation
        var varianceSum: Float = 0
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Float(buffer[i]) / 255.0
                let lum = 0.2126 * r
                let diff = lum - meanLum
                varianceSum += diff * diff
            }
        }
        let variance = varianceSum / count
        
        return FrameMetrics(
            brightness: meanLum,
            contrast: maxLum - minLum,
            sharpness: edgeSum / count,
            noiseEstimate: sqrt(variance),
            dominantColor: SIMD3<Float>(meanR, meanG, meanB),
            width: width,
            height: height
        )
    }
    
    // MARK: - Shot Classification
    
    private func classifyShot(frames: [AnalyzedFrame]) -> ShotClassification {
        guard !frames.isEmpty else {
            return ShotClassification(
                type: .unknown,
                confidence: 0,
                subType: nil
            )
        }
        
        // Analyze motion patterns
        let motionSummary = analyzeMotion(frames: frames)
        
        // Analyze composition
        let avgBrightness = frames.map { $0.metrics.brightness }.reduce(0, +) / Float(frames.count)
        let brightnessDev = frames.map { abs($0.metrics.brightness - avgBrightness) }.reduce(0, +) / Float(frames.count)
        
        // Determine shot type based on motion and composition
        var shotType: ShotType = .static
        var confidence: Float = 0.8
        var subType: String?
        
        if motionSummary.overallIntensity < 0.02 {
            // Very little motion - static shot
            shotType = .static
            confidence = 0.9
        } else if motionSummary.dominantDirection != nil {
            // Directional motion
            switch motionSummary.cameraMotion {
            case .pan:
                shotType = .pan
                subType = motionSummary.dominantDirection == .horizontal ? "horizontal" : "vertical"
            case .tilt:
                shotType = .tilt
            case .zoom:
                shotType = motionSummary.overallIntensity > 0.15 ? .zoomIn : .zoomOut
            case .dolly:
                shotType = .tracking
            case .handheld:
                shotType = .handheld
            case .crane:
                shotType = .tracking
                subType = "crane"
            case .none:
                shotType = .static
            }
            confidence = motionSummary.confidence
        } else if motionSummary.overallIntensity > 0.2 {
            // High motion without clear direction - action shot
            shotType = .action
            confidence = 0.7
        }
        
        // Detect interview setup (stable, face-sized area of focus)
        if shotType == .static && brightnessDev < 0.1 {
            subType = "interview"
        }
        
        return ShotClassification(
            type: shotType,
            confidence: confidence,
            subType: subType
        )
    }
    
    // MARK: - Motion Analysis
    
    private func analyzeMotion(frames: [AnalyzedFrame]) -> MotionSummary {
        guard frames.count > 1 else {
            return MotionSummary(
                overallIntensity: 0,
                dominantDirection: nil,
                cameraMotion: .none,
                stabilityScore: 1.0,
                frameToFrameDeltas: [],
                confidence: 1.0
            )
        }
        
        var deltas: [Float] = []
        var horizontalMotion: Float = 0
        var verticalMotion: Float = 0
        
        for i in 1..<frames.count {
            let prev = frames[i - 1]
            let curr = frames[i]
            
            // Compare brightness and color
            let brightDiff = abs(curr.metrics.brightness - prev.metrics.brightness)
            let colorDiff = simd_length(curr.metrics.dominantColor - prev.metrics.dominantColor)
            let delta = (brightDiff + colorDiff) / 2.0
            deltas.append(delta)
            
            // Estimate motion direction from color distribution change
            // (simplified - real implementation would use optical flow)
            let colorShift = curr.metrics.dominantColor - prev.metrics.dominantColor
            horizontalMotion += abs(colorShift.x - colorShift.z)  // Red-blue shift for horizontal
            verticalMotion += abs(colorShift.y)  // Green channel for vertical
        }
        
        let avgDelta = deltas.reduce(0, +) / Float(deltas.count)
        let stabilityVariance = deltas.map { pow($0 - avgDelta, 2) }.reduce(0, +) / Float(deltas.count)
        let stabilityScore = 1.0 - Swift.min(1.0, sqrt(stabilityVariance) * 5)
        
        // Determine dominant direction
        var dominantDirection: MotionDirection?
        if abs(horizontalMotion) > abs(verticalMotion) * 1.5 {
            dominantDirection = .horizontal
        } else if abs(verticalMotion) > abs(horizontalMotion) * 1.5 {
            dominantDirection = .vertical
        } else if horizontalMotion + verticalMotion > config.motionThreshold * Float(frames.count) {
            dominantDirection = .diagonal
        }
        
        // Classify camera motion
        let cameraMotion: CameraMotionType
        if avgDelta < config.motionThreshold * 0.5 {
            cameraMotion = .none
        } else if stabilityScore < 0.5 {
            cameraMotion = .handheld
        } else if dominantDirection == .horizontal {
            cameraMotion = .pan
        } else if dominantDirection == .vertical {
            cameraMotion = .tilt
        } else {
            cameraMotion = .dolly
        }
        
        return MotionSummary(
            overallIntensity: avgDelta,
            dominantDirection: dominantDirection,
            cameraMotion: cameraMotion,
            stabilityScore: stabilityScore,
            frameToFrameDeltas: deltas,
            confidence: stabilityScore > 0.3 ? 0.8 : 0.5
        )
    }
    
    // MARK: - Quality Assessment
    
    private func assessQuality(frames: [AnalyzedFrame]) -> [QualityFlag] {
        var flags: [QualityFlag] = []
        
        guard !frames.isEmpty else { return flags }
        
        // Calculate aggregate metrics
        let avgBrightness = frames.map { $0.metrics.brightness }.reduce(0, +) / Float(frames.count)
        let avgSharpness = frames.map { $0.metrics.sharpness }.reduce(0, +) / Float(frames.count)
        let avgNoise = frames.map { $0.metrics.noiseEstimate }.reduce(0, +) / Float(frames.count)
        let avgContrast = frames.map { $0.metrics.contrast }.reduce(0, +) / Float(frames.count)
        
        // Check exposure
        if avgBrightness < 0.15 {
            let severity: QualitySeverity = avgBrightness < 0.08 ? .critical : .warning
            flags.append(QualityFlag(
                category: .exposure,
                severity: severity,
                description: "Underexposed footage",
                value: avgBrightness,
                recommendation: "Consider increasing exposure or adding fill light"
            ))
        } else if avgBrightness > 0.85 {
            let severity: QualitySeverity = avgBrightness > 0.92 ? .critical : .warning
            flags.append(QualityFlag(
                category: .exposure,
                severity: severity,
                description: "Overexposed footage",
                value: avgBrightness,
                recommendation: "Reduce exposure to recover highlights"
            ))
        }
        
        // Check focus/sharpness
        if avgSharpness < 0.02 {
            flags.append(QualityFlag(
                category: .focus,
                severity: .warning,
                description: "Soft or out-of-focus footage",
                value: avgSharpness,
                recommendation: "Check focus during capture"
            ))
        }
        
        // Check noise
        if avgNoise > 0.15 {
            let severity: QualitySeverity = avgNoise > 0.25 ? .warning : .info
            flags.append(QualityFlag(
                category: .noise,
                severity: severity,
                description: "High noise levels detected",
                value: avgNoise,
                recommendation: "Consider noise reduction in post"
            ))
        }
        
        // Check contrast
        if avgContrast < 0.3 {
            flags.append(QualityFlag(
                category: .contrast,
                severity: .info,
                description: "Low contrast footage",
                value: avgContrast,
                recommendation: "May benefit from contrast adjustment"
            ))
        }
        
        // Check stability
        let motion = analyzeMotion(frames: frames)
        if motion.stabilityScore < 0.4 {
            flags.append(QualityFlag(
                category: .stability,
                severity: .warning,
                description: "Shaky footage detected",
                value: motion.stabilityScore,
                recommendation: "Consider applying stabilization"
            ))
        }
        
        return flags
    }
    
    // MARK: - Color Analysis
    
    private func analyzeColor(frames: [AnalyzedFrame]) -> ColorAnalysis {
        guard !frames.isEmpty else {
            return ColorAnalysis(
                dominantColor: SIMD3(0.5, 0.5, 0.5),
                colorTemperature: .neutral,
                saturation: 0.5,
                colorCast: nil
            )
        }
        
        // Average dominant color
        var sumColor = SIMD3<Float>.zero
        for frame in frames {
            sumColor += frame.metrics.dominantColor
        }
        let avgColor = sumColor / Float(frames.count)
        
        // Determine color temperature
        let temperature: ColorTemperature
        let rb = avgColor.x - avgColor.z
        
        if rb > 0.1 {
            temperature = .warm
        } else if rb < -0.1 {
            temperature = .cool
        } else {
            temperature = .neutral
        }
        
        // Estimate saturation
        let maxC = Swift.max(avgColor.x, Swift.max(avgColor.y, avgColor.z))
        let minC = Swift.min(avgColor.x, Swift.min(avgColor.y, avgColor.z))
        let saturation = maxC > 0.01 ? (maxC - minC) / maxC : 0
        
        // Detect color cast
        var colorCast: String?
        let threshold: Float = 0.08
        if avgColor.x > avgColor.y + threshold && avgColor.x > avgColor.z + threshold {
            colorCast = "red"
        } else if avgColor.y > avgColor.x + threshold && avgColor.y > avgColor.z + threshold {
            colorCast = "green"
        } else if avgColor.z > avgColor.x + threshold && avgColor.z > avgColor.y + threshold {
            colorCast = "blue"
        } else if avgColor.x + avgColor.y > avgColor.z * 2 + threshold {
            colorCast = "yellow"
        } else if avgColor.x + avgColor.z > avgColor.y * 2 + threshold {
            colorCast = "magenta"
        } else if avgColor.y + avgColor.z > avgColor.x * 2 + threshold {
            colorCast = "cyan"
        }
        
        return ColorAnalysis(
            dominantColor: avgColor,
            colorTemperature: temperature,
            saturation: saturation,
            colorCast: colorCast
        )
    }
}

// MARK: - Result Types

/// Complete clip analysis result
public struct ClipAnalysisResult: Sendable {
    public let duration: Double
    public let frameCount: Int
    public let shotType: ShotClassification
    public let motionSummary: MotionSummary
    public let qualityFlags: [QualityFlag]
    public let colorAnalysis: ColorAnalysis
    public let analysisTimestamp: Date
    
    public var hasQualityIssues: Bool {
        qualityFlags.contains { $0.severity == .critical || $0.severity == .warning }
    }
}

/// Shot type classification
public struct ShotClassification: Sendable {
    public let type: ShotType
    public let confidence: Float
    public let subType: String?
}

public enum ShotType: String, Codable, Sendable {
    case static_         = "static"
    case pan
    case tilt
    case zoomIn = "zoom_in"
    case zoomOut = "zoom_out"
    case tracking
    case handheld
    case action
    case unknown
    
    // Swift identifier-friendly version
    public static var `static`: ShotType { .static_ }
}

/// Motion analysis summary
public struct MotionSummary: Sendable {
    public let overallIntensity: Float
    public let dominantDirection: MotionDirection?
    public let cameraMotion: CameraMotionType
    public let stabilityScore: Float
    public let frameToFrameDeltas: [Float]
    public let confidence: Float
}

public enum MotionDirection: String, Sendable {
    case horizontal
    case vertical
    case diagonal
    case radial
}

public enum CameraMotionType: String, Sendable {
    case none
    case pan
    case tilt
    case zoom
    case dolly
    case handheld
    case crane
}

/// Quality flag
public struct QualityFlag: Sendable {
    public let category: QualityCategory
    public let severity: QualitySeverity
    public let description: String
    public let value: Float
    public let recommendation: String
}

public enum QualityCategory: String, Sendable {
    case exposure
    case focus
    case noise
    case contrast
    case stability
    case colorSpace
    case audio
}

public enum QualitySeverity: String, Sendable {
    case info
    case warning
    case critical
}

/// Color analysis result
public struct ColorAnalysis: Sendable {
    public let dominantColor: SIMD3<Float>
    public let colorTemperature: ColorTemperature
    public let saturation: Float
    public let colorCast: String?
}

public enum ColorTemperature: String, Sendable {
    case warm
    case neutral
    case cool
}

// MARK: - Private Types

private struct AnalyzedFrame {
    let timestamp: Double
    let image: CGImage
    let metrics: FrameMetrics
}

private struct FrameMetrics {
    let brightness: Float
    let contrast: Float
    let sharpness: Float
    let noiseEstimate: Float
    let dominantColor: SIMD3<Float>
    let width: Int
    let height: Int
    
    static let empty = FrameMetrics(
        brightness: 0,
        contrast: 0,
        sharpness: 0,
        noiseEstimate: 0,
        dominantColor: .zero,
        width: 0,
        height: 0
    )
}
