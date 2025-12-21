// Sources/MetaVisRender/Ingestion/Video/SceneDetector.swift
// Sprint 03: Shot boundary detection for video analysis

import AVFoundation
import CoreImage
import Accelerate
import Foundation

// MARK: - Scene Detector

/// Detects shot boundaries and scene changes in video
public actor SceneDetector {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Threshold for hard cut detection (0-1)
        public let hardCutThreshold: Float
        /// Threshold for dissolve detection (0-1)
        public let dissolveThreshold: Float
        /// Minimum shot duration in seconds
        public let minShotDuration: Double
        /// Analysis interval in seconds
        public let analysisInterval: Double
        /// Use motion analysis for detection
        public let useMotionAnalysis: Bool
        /// Use color histogram for detection
        public let useColorHistogram: Bool
        /// Use edge detection for cuts
        public let useEdgeAnalysis: Bool
        
        public init(
            hardCutThreshold: Float = 0.4,
            dissolveThreshold: Float = 0.15,
            minShotDuration: Double = 0.5,
            analysisInterval: Double = 0.1,
            useMotionAnalysis: Bool = true,
            useColorHistogram: Bool = true,
            useEdgeAnalysis: Bool = false
        ) {
            self.hardCutThreshold = hardCutThreshold
            self.dissolveThreshold = dissolveThreshold
            self.minShotDuration = minShotDuration
            self.analysisInterval = analysisInterval
            self.useMotionAnalysis = useMotionAnalysis
            self.useColorHistogram = useColorHistogram
            self.useEdgeAnalysis = useEdgeAnalysis
        }
        
        public static let `default` = Config()
        
        public static let sensitive = Config(
            hardCutThreshold: 0.3,
            dissolveThreshold: 0.1,
            minShotDuration: 0.3
        )
        
        public static let conservative = Config(
            hardCutThreshold: 0.5,
            dissolveThreshold: 0.2,
            minShotDuration: 1.0
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Detect all shots in a video
    public func detectShots(in url: URL) async throws -> SceneDetectionResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        // Detect scene changes
        let changes = try await detectChanges(in: asset, duration: duration)
        
        // Convert changes to shots
        let shots = buildShots(from: changes, duration: duration)
        
        return SceneDetectionResult(
            shots: shots,
            sceneChanges: changes,
            duration: duration,
            analysisConfig: config
        )
    }
    
    /// Detect only scene change points (faster than full shot detection)
    public func detectSceneChanges(in url: URL) async throws -> [SceneChange] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        return try await detectChanges(in: asset, duration: duration)
    }
    
    // MARK: - Private Methods
    
    private func detectChanges(in asset: AVAsset, duration: Double) async throws -> [SceneChange] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.01, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.01, preferredTimescale: 600)
        
        var changes: [SceneChange] = []
        var previousFrame: FrameFeatures?
        var lastChangeTime = 0.0
        
        var currentTime = 0.0
        while currentTime < duration {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let (cgImage, actualTime) = try await generator.image(at: cmTime)
                let features = extractFeatures(from: cgImage)
                
                if let previous = previousFrame {
                    let diff = compareFeatures(previous, features)
                    
                    // Check for hard cut
                    if diff.overallScore > config.hardCutThreshold &&
                       (actualTime.seconds - lastChangeTime) > config.minShotDuration {
                        
                        let change = SceneChange(
                            timestamp: actualTime.seconds,
                            type: .hardCut,
                            confidence: min(1.0, diff.overallScore / config.hardCutThreshold),
                            histogramDiff: diff.histogramDiff,
                            motionDiff: diff.motionDiff,
                            edgeDiff: diff.edgeDiff
                        )
                        changes.append(change)
                        lastChangeTime = actualTime.seconds
                    }
                    // Check for dissolve (sustained medium difference)
                    else if diff.overallScore > config.dissolveThreshold &&
                            diff.overallScore < config.hardCutThreshold {
                        // Could be a dissolve - would need temporal analysis
                        // For now, mark as potential dissolve
                    }
                }
                
                previousFrame = features
            } catch {
                // Skip frames that fail to decode
            }
            
            currentTime += config.analysisInterval
        }
        
        return changes
    }
    
    private func extractFeatures(from image: CGImage) -> FrameFeatures {
        // Downsample for faster processing
        let size = 64
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return FrameFeatures.empty
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        
        guard let data = context.data else {
            return FrameFeatures.empty
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        
        // Calculate histogram (16 bins per channel)
        var histogram = Array(repeating: Float(0), count: 48)
        var luminance = Array(repeating: Float(0), count: size * size)
        
        for i in 0..<(size * size) {
            let r = Float(buffer[i * 4])
            let g = Float(buffer[i * 4 + 1])
            let b = Float(buffer[i * 4 + 2])
            
            histogram[Int(r) / 16] += 1
            histogram[16 + Int(g) / 16] += 1
            histogram[32 + Int(b) / 16] += 1
            
            // Calculate luminance for motion/edge analysis
            luminance[i] = 0.299 * r + 0.587 * g + 0.114 * b
        }
        
        // Normalize histogram
        let pixelCount = Float(size * size)
        for i in histogram.indices {
            histogram[i] /= pixelCount
        }
        
        // Calculate edge map using simple sobel-like filter
        var edgeSum: Float = 0
        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let idx = y * size + x
                let gx = luminance[idx + 1] - luminance[idx - 1]
                let gy = luminance[idx + size] - luminance[idx - size]
                edgeSum += sqrt(gx * gx + gy * gy)
            }
        }
        let edgeDensity = edgeSum / Float((size - 2) * (size - 2) * 255)
        
        return FrameFeatures(
            histogram: histogram,
            luminanceGrid: luminance,
            edgeDensity: edgeDensity
        )
    }
    
    private func compareFeatures(_ a: FrameFeatures, _ b: FrameFeatures) -> FeatureDifference {
        // Histogram difference (Chi-squared)
        var histDiff: Float = 0
        if config.useColorHistogram {
            for i in a.histogram.indices {
                let sum = a.histogram[i] + b.histogram[i]
                if sum > 0.001 {
                    let diff = a.histogram[i] - b.histogram[i]
                    histDiff += (diff * diff) / sum
                }
            }
            histDiff = min(1.0, histDiff / 2.0)  // Normalize to 0-1
        }
        
        // Motion/luminance difference
        var motionDiff: Float = 0
        if config.useMotionAnalysis && a.luminanceGrid.count == b.luminanceGrid.count {
            var sum: Float = 0
            for i in a.luminanceGrid.indices {
                sum += abs(a.luminanceGrid[i] - b.luminanceGrid[i])
            }
            motionDiff = sum / (Float(a.luminanceGrid.count) * 255.0)
        }
        
        // Edge density difference
        var edgeDiff: Float = 0
        if config.useEdgeAnalysis {
            edgeDiff = abs(a.edgeDensity - b.edgeDensity)
        }
        
        // Combine scores
        var weights: Float = 0
        var weighted: Float = 0
        
        if config.useColorHistogram {
            weighted += histDiff * 0.5
            weights += 0.5
        }
        if config.useMotionAnalysis {
            weighted += motionDiff * 0.4
            weights += 0.4
        }
        if config.useEdgeAnalysis {
            weighted += edgeDiff * 0.1
            weights += 0.1
        }
        
        let overall = weights > 0 ? weighted / weights : 0
        
        return FeatureDifference(
            overallScore: overall,
            histogramDiff: histDiff,
            motionDiff: motionDiff,
            edgeDiff: edgeDiff
        )
    }
    
    private func buildShots(from changes: [SceneChange], duration: Double) -> [Shot] {
        var shots: [Shot] = []
        var shotStart = 0.0
        
        for (index, change) in changes.enumerated() {
            let shot = Shot(
                id: index,
                startTime: shotStart,
                endTime: change.timestamp,
                transitionIn: index == 0 ? .none : changes[index - 1].type.asTransition,
                transitionOut: change.type.asTransition
            )
            shots.append(shot)
            shotStart = change.timestamp
        }
        
        // Add final shot
        if shotStart < duration {
            shots.append(Shot(
                id: shots.count,
                startTime: shotStart,
                endTime: duration,
                transitionIn: changes.last?.type.asTransition ?? .none,
                transitionOut: .none
            ))
        }
        
        return shots
    }
}

// MARK: - Supporting Types

private struct FrameFeatures: Sendable {
    let histogram: [Float]
    let luminanceGrid: [Float]
    let edgeDensity: Float
    
    static let empty = FrameFeatures(histogram: [], luminanceGrid: [], edgeDensity: 0)
}

private struct FeatureDifference: Sendable {
    let overallScore: Float
    let histogramDiff: Float
    let motionDiff: Float
    let edgeDiff: Float
}

// MARK: - Public Result Types

/// A detected scene change point
public struct SceneChange: Codable, Sendable, Equatable {
    /// Timestamp of the scene change
    public let timestamp: Double
    /// Type of scene change
    public let type: SceneChangeType
    /// Detection confidence (0-1)
    public let confidence: Float
    /// Histogram difference score
    public let histogramDiff: Float
    /// Motion difference score
    public let motionDiff: Float
    /// Edge difference score
    public let edgeDiff: Float
}

/// Type of scene change
public enum SceneChangeType: String, Codable, Sendable {
    case hardCut = "cut"
    case dissolve = "dissolve"
    case fade = "fade"
    case wipe = "wipe"
    case unknown = "unknown"
    
    var asTransition: TransitionType {
        switch self {
        case .hardCut: return .cut
        case .dissolve: return .dissolve
        case .fade: return .fade
        case .wipe: return .wipe
        case .unknown: return .none
        }
    }
}

/// Transition type between shots
public enum TransitionType: String, Codable, Sendable {
    case none = "none"
    case cut = "cut"
    case dissolve = "dissolve"
    case fade = "fade"
    case wipe = "wipe"
}

/// A single shot in the video
public struct Shot: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let startTime: Double
    public let endTime: Double
    public let transitionIn: TransitionType
    public let transitionOut: TransitionType
    
    public var duration: Double { endTime - startTime }
}

/// Complete scene detection result
public struct SceneDetectionResult: Codable, Sendable {
    /// All detected shots
    public let shots: [Shot]
    /// Scene change points
    public let sceneChanges: [SceneChange]
    /// Total video duration
    public let duration: Double
    /// Configuration used for analysis
    public let analysisConfig: SceneDetector.Config
    
    /// Number of shots detected
    public var shotCount: Int { shots.count }
    
    /// Average shot duration
    public var averageShotDuration: Double {
        guard !shots.isEmpty else { return 0 }
        return shots.reduce(0) { $0 + $1.duration } / Double(shots.count)
    }
    
    /// Shortest shot
    public var shortestShot: Shot? {
        shots.min(by: { $0.duration < $1.duration })
    }
    
    /// Longest shot
    public var longestShot: Shot? {
        shots.max(by: { $0.duration < $1.duration })
    }
}

// MARK: - Config Codable

extension SceneDetector.Config: Codable {
    enum CodingKeys: String, CodingKey {
        case hardCutThreshold, dissolveThreshold, minShotDuration
        case analysisInterval, useMotionAnalysis, useColorHistogram, useEdgeAnalysis
    }
}
