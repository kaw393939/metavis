// Sources/MetaVisRender/Ingestion/Core/FrameSampler.swift
// Sprint 03: Intelligent frame sampling for video analysis

import AVFoundation
import CoreImage
import Foundation

// MARK: - Frame Sampler

/// Intelligently samples frames from video for analysis
/// Uses scene detection hints, motion analysis, and keyframe extraction
public actor FrameSampler {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Target number of frames to sample
        public let targetFrameCount: Int
        /// Minimum interval between samples (seconds)
        public let minInterval: Double
        /// Maximum interval between samples (seconds)
        public let maxInterval: Double
        /// Include keyframes from codec
        public let preferKeyframes: Bool
        /// Sample at scene changes
        public let sampleAtSceneChanges: Bool
        /// Threshold for scene change detection (0-1)
        public let sceneChangeThreshold: Float
        
        public init(
            targetFrameCount: Int = 30,
            minInterval: Double = 0.5,
            maxInterval: Double = 5.0,
            preferKeyframes: Bool = true,
            sampleAtSceneChanges: Bool = true,
            sceneChangeThreshold: Float = 0.3
        ) {
            self.targetFrameCount = targetFrameCount
            self.minInterval = minInterval
            self.maxInterval = maxInterval
            self.preferKeyframes = preferKeyframes
            self.sampleAtSceneChanges = sampleAtSceneChanges
            self.sceneChangeThreshold = sceneChangeThreshold
        }
        
        public static let `default` = Config()
        
        public static let dense = Config(
            targetFrameCount: 60,
            minInterval: 0.25,
            maxInterval: 2.0
        )
        
        public static let sparse = Config(
            targetFrameCount: 10,
            minInterval: 2.0,
            maxInterval: 10.0
        )
    }
    
    private let config: Config
    private let ciContext: CIContext
    
    public init(config: Config = .default) {
        self.config = config
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }
    
    // MARK: - Public API
    
    /// Sample frames from a video file
    public func sampleFrames(from url: URL) async throws -> [SampledFrame] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let asset = AVAsset(url: url)
        
        guard try await asset.load(.isReadable) else {
            throw IngestionError.unsupportedFormat(url.pathExtension)
        }
        
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            throw IngestionError.corruptedFile("Invalid duration")
        }
        
        // Calculate sample times
        let sampleTimes = calculateSampleTimes(duration: duration)
        
        // Extract frames
        return try await extractFrames(from: asset, at: sampleTimes)
    }
    
    /// Sample frames with scene change detection
    public func sampleFramesWithSceneDetection(from url: URL) async throws -> [SampledFrame] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        
        // First pass: detect scene changes
        let sceneChanges = try await detectSceneChanges(in: asset)
        
        // Combine uniform sampling with scene change times
        let uniformTimes = calculateSampleTimes(duration: duration)
        let combinedTimes = mergeAndSort(uniformTimes, sceneChanges.map { $0.time })
        
        // Extract frames at combined times
        var frames = try await extractFrames(from: asset, at: combinedTimes)
        
        // Mark frames at scene changes
        for i in frames.indices {
            if let sceneChange = sceneChanges.first(where: { abs($0.time - frames[i].timestamp) < 0.1 }) {
                frames[i].isSceneChange = true
                frames[i].sceneChangeScore = sceneChange.score
            }
        }
        
        return frames
    }
    
    // MARK: - Private Methods
    
    private func calculateSampleTimes(duration: Double) -> [Double] {
        var times: [Double] = []
        
        // Always sample first frame
        times.append(0.0)
        
        // Calculate interval based on target count
        let targetInterval = duration / Double(config.targetFrameCount)
        let interval = max(config.minInterval, min(config.maxInterval, targetInterval))
        
        var currentTime = interval
        while currentTime < duration - interval / 2 {
            times.append(currentTime)
            currentTime += interval
        }
        
        // Always sample last frame (if not too close to previous)
        if duration - (times.last ?? 0) > config.minInterval {
            times.append(max(0, duration - 0.1))
        }
        
        return times
    }
    
    private func extractFrames(from asset: AVAsset, at times: [Double]) async throws -> [SampledFrame] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        if config.preferKeyframes {
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
        }
        
        var frames: [SampledFrame] = []
        
        for time in times {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            
            do {
                let (cgImage, actualTime) = try await generator.image(at: cmTime)
                
                let frame = SampledFrame(
                    index: frames.count,
                    timestamp: actualTime.seconds,
                    requestedTime: time,
                    image: cgImage,
                    isKeyframe: config.preferKeyframes,
                    isSceneChange: false,
                    sceneChangeScore: nil
                )
                frames.append(frame)
            } catch {
                // Skip frames that fail to decode
                continue
            }
        }
        
        return frames
    }
    
    private func detectSceneChanges(in asset: AVAsset) async throws -> [(time: Double, score: Float)] {
        guard config.sampleAtSceneChanges else { return [] }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let duration = try await asset.load(.duration).seconds
        let sampleInterval = 0.5 // Sample every 0.5 seconds for scene detection
        
        var sceneChanges: [(time: Double, score: Float)] = []
        var previousHistogram: [Float]?
        
        var currentTime = 0.0
        while currentTime < duration {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            
            do {
                let (cgImage, _) = try await generator.image(at: cmTime)
                let histogram = calculateHistogram(for: cgImage)
                
                if let previous = previousHistogram {
                    let difference = histogramDifference(previous, histogram)
                    
                    if difference > config.sceneChangeThreshold {
                        sceneChanges.append((time: currentTime, score: difference))
                    }
                }
                
                previousHistogram = histogram
            } catch {
                // Skip frames that fail
            }
            
            currentTime += sampleInterval
        }
        
        return sceneChanges
    }
    
    private func calculateHistogram(for image: CGImage) -> [Float] {
        // Simplified histogram calculation (16 bins per channel = 48 values)
        let width = min(image.width, 64)  // Downsample for speed
        let height = min(image.height, 64)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Array(repeating: 0, count: 48)
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            return Array(repeating: 0, count: 48)
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var histogram = Array(repeating: Float(0), count: 48)
        let pixelCount = Float(width * height)
        
        for i in 0..<(width * height) {
            let r = buffer[i * 4]
            let g = buffer[i * 4 + 1]
            let b = buffer[i * 4 + 2]
            
            histogram[Int(r) / 16] += 1
            histogram[16 + Int(g) / 16] += 1
            histogram[32 + Int(b) / 16] += 1
        }
        
        // Normalize
        for i in histogram.indices {
            histogram[i] /= pixelCount
        }
        
        return histogram
    }
    
    private func histogramDifference(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 1.0 }
        
        var sum: Float = 0
        for i in a.indices {
            sum += abs(a[i] - b[i])
        }
        
        return sum / Float(a.count)
    }
    
    private func mergeAndSort(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = Set(a)
        result.formUnion(b)
        return result.sorted()
    }
}

// MARK: - Sampled Frame

/// A single frame extracted from video
public struct SampledFrame: Sendable {
    /// Sequential index in sample set
    public let index: Int
    /// Actual timestamp of extracted frame
    public let timestamp: Double
    /// Originally requested timestamp
    public let requestedTime: Double
    /// The frame image
    public let image: CGImage
    /// Whether this was a codec keyframe
    public let isKeyframe: Bool
    /// Whether this marks a scene change
    public var isSceneChange: Bool
    /// Scene change confidence score
    public var sceneChangeScore: Float?
    
    /// Difference between requested and actual time
    public var timeOffset: Double {
        timestamp - requestedTime
    }
}

// MARK: - Frame Analysis Results

/// Results from analyzing multiple sampled frames
public struct FrameAnalysisResults: Codable, Sendable {
    /// Total frames sampled
    public let frameCount: Int
    /// Timestamps of all sampled frames
    public let timestamps: [Double]
    /// Detected scene change timestamps
    public let sceneChanges: [Double]
    /// Average frame brightness
    public let averageBrightness: Float
    /// Brightness range (min, max)
    public let brightnessRange: (min: Float, max: Float)
    /// Dominant color per frame (RGB)
    public let dominantColors: [[Float]]
    /// Motion intensity between frames
    public let motionIntensity: [Float]
    
    enum CodingKeys: String, CodingKey {
        case frameCount, timestamps, sceneChanges, averageBrightness
        case brightnessMin, brightnessMax, dominantColors, motionIntensity
    }
    
    public init(
        frameCount: Int,
        timestamps: [Double],
        sceneChanges: [Double],
        averageBrightness: Float,
        brightnessRange: (min: Float, max: Float),
        dominantColors: [[Float]],
        motionIntensity: [Float]
    ) {
        self.frameCount = frameCount
        self.timestamps = timestamps
        self.sceneChanges = sceneChanges
        self.averageBrightness = averageBrightness
        self.brightnessRange = brightnessRange
        self.dominantColors = dominantColors
        self.motionIntensity = motionIntensity
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
        timestamps = try container.decode([Double].self, forKey: .timestamps)
        sceneChanges = try container.decode([Double].self, forKey: .sceneChanges)
        averageBrightness = try container.decode(Float.self, forKey: .averageBrightness)
        let minB = try container.decode(Float.self, forKey: .brightnessMin)
        let maxB = try container.decode(Float.self, forKey: .brightnessMax)
        brightnessRange = (minB, maxB)
        dominantColors = try container.decode([[Float]].self, forKey: .dominantColors)
        motionIntensity = try container.decode([Float].self, forKey: .motionIntensity)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameCount, forKey: .frameCount)
        try container.encode(timestamps, forKey: .timestamps)
        try container.encode(sceneChanges, forKey: .sceneChanges)
        try container.encode(averageBrightness, forKey: .averageBrightness)
        try container.encode(brightnessRange.min, forKey: .brightnessMin)
        try container.encode(brightnessRange.max, forKey: .brightnessMax)
        try container.encode(dominantColors, forKey: .dominantColors)
        try container.encode(motionIntensity, forKey: .motionIntensity)
    }
}
