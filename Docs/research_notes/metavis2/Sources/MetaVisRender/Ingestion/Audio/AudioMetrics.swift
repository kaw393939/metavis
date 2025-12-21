// Sources/MetaVisRender/Ingestion/Audio/AudioMetrics.swift
// Sprint 03: Detailed audio quality analysis

import AVFoundation
import Accelerate
import Foundation

// MARK: - Audio Metrics Analyzer

/// Analyzes audio quality metrics: levels, noise, clipping, dynamic range
public actor AudioMetricsAnalyzer {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Sample size for analysis (seconds)
        public let analysisSampleDuration: Double
        /// Noise floor threshold (dBFS)
        public let noiseFloorThreshold: Float
        /// Clipping threshold (0-1)
        public let clippingThreshold: Float
        /// Target loudness (LUFS)
        public let targetLUFS: Float
        /// Block size for loudness calculation
        public let loudnessBlockSize: Int
        
        public init(
            analysisSampleDuration: Double = 0.4,
            noiseFloorThreshold: Float = -60,
            clippingThreshold: Float = 0.99,
            targetLUFS: Float = -14,
            loudnessBlockSize: Int = 4096
        ) {
            self.analysisSampleDuration = analysisSampleDuration
            self.noiseFloorThreshold = noiseFloorThreshold
            self.clippingThreshold = clippingThreshold
            self.targetLUFS = targetLUFS
            self.loudnessBlockSize = loudnessBlockSize
        }
        
        public static let `default` = Config()
        
        public static let broadcast = Config(
            noiseFloorThreshold: -50,
            clippingThreshold: 0.95,
            targetLUFS: -23  // EBU R128
        )
        
        public static let streaming = Config(
            noiseFloorThreshold: -60,
            clippingThreshold: 0.99,
            targetLUFS: -14  // Spotify/YouTube
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Analyze audio metrics for a file
    public func analyze(url: URL) async throws -> AudioMetrics {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        let sampleRate = format.sampleRate
        let duration = Double(frameCount) / sampleRate
        
        // Read audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw IngestionError.insufficientMemory
        }
        try audioFile.read(into: buffer)
        
        // Analyze
        let levels = analyzeLevels(buffer: buffer)
        let clipping = detectClipping(buffer: buffer)
        let noise = analyzeNoise(buffer: buffer, sampleRate: sampleRate)
        let loudness = calculateLoudness(buffer: buffer, sampleRate: sampleRate)
        let quality = assessQuality(levels: levels, clipping: clipping, noise: noise, loudness: loudness)
        
        return AudioMetrics(
            duration: duration,
            sampleRate: Int(sampleRate),
            channels: Int(format.channelCount),
            peakLevel: levels.peak,
            rmsLevel: levels.rms,
            lufs: loudness.integrated,
            loudnessRange: loudness.range,
            dynamicRange: levels.dynamicRange,
            noiseFloor: noise.floor,
            signalToNoise: noise.snr,
            hasClipping: clipping.hasClipping,
            clippingRatio: clipping.ratio,
            clippingSamples: clipping.count,
            needsDenoising: noise.needsDenoising,
            needsNormalization: loudness.needsNormalization,
            isUsable: quality.isUsable,
            qualityScore: quality.score,
            issues: quality.issues
        )
    }
    
    /// Quick analysis (faster, less detailed)
    public func quickAnalyze(url: URL) async throws -> QuickAudioMetrics {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IngestionError.fileNotFound(url)
        }
        
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        
        // Sample a portion of the audio
        let sampleFrames = AVAudioFrameCount(config.analysisSampleDuration * sampleRate)
        let totalFrames = AVAudioFrameCount(audioFile.length)
        let framesToRead = min(sampleFrames, totalFrames)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead) else {
            throw IngestionError.insufficientMemory
        }
        try audioFile.read(into: buffer)
        
        let levels = analyzeLevels(buffer: buffer)
        let hasClipping = detectClipping(buffer: buffer).hasClipping
        
        return QuickAudioMetrics(
            peakLevel: levels.peak,
            rmsLevel: levels.rms,
            hasClipping: hasClipping,
            dynamicRange: levels.dynamicRange
        )
    }
    
    // MARK: - Analysis Methods
    
    private func analyzeLevels(buffer: AVAudioPCMBuffer) -> LevelAnalysis {
        guard let channelData = buffer.floatChannelData else {
            return LevelAnalysis(peak: -Float.infinity, rms: -Float.infinity, dynamicRange: 0)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var maxPeak: Float = 0
        var sumSquares: Float = 0
        var minRMS: Float = Float.infinity
        var maxRMS: Float = -Float.infinity
        
        // Block-based RMS for dynamic range
        let blockSize = 4096
        let blockCount = frameLength / blockSize
        
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            
            // Find peak
            var channelMax: Float = 0
            vDSP_maxmgv(samples, 1, &channelMax, vDSP_Length(frameLength))
            maxPeak = max(maxPeak, channelMax)
            
            // Calculate RMS
            var channelSumSquares: Float = 0
            vDSP_svesq(samples, 1, &channelSumSquares, vDSP_Length(frameLength))
            sumSquares += channelSumSquares
            
            // Block-based RMS for dynamic range
            for block in 0..<blockCount {
                let offset = block * blockSize
                var blockSumSquares: Float = 0
                vDSP_svesq(samples + offset, 1, &blockSumSquares, vDSP_Length(blockSize))
                let blockRMS = sqrt(blockSumSquares / Float(blockSize))
                
                if blockRMS > 0.001 {  // Ignore silence
                    minRMS = min(minRMS, blockRMS)
                    maxRMS = max(maxRMS, blockRMS)
                }
            }
        }
        
        let totalSamples = Float(frameLength * channelCount)
        let rmsLinear = sqrt(sumSquares / totalSamples)
        
        let peakDB = maxPeak > 0 ? 20 * log10(maxPeak) : -Float.infinity
        let rmsDB = rmsLinear > 0 ? 20 * log10(rmsLinear) : -Float.infinity
        
        // Dynamic range in dB
        let dynamicRange: Float
        if minRMS > 0 && maxRMS > 0 && minRMS < Float.infinity {
            dynamicRange = 20 * log10(maxRMS / minRMS)
        } else {
            dynamicRange = 0
        }
        
        return LevelAnalysis(peak: peakDB, rms: rmsDB, dynamicRange: dynamicRange)
    }
    
    private func detectClipping(buffer: AVAudioPCMBuffer) -> ClippingAnalysis {
        guard let channelData = buffer.floatChannelData else {
            return ClippingAnalysis(hasClipping: false, ratio: 0, count: 0)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var clippedCount = 0
        let threshold = config.clippingThreshold
        
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for i in 0..<frameLength {
                if abs(samples[i]) >= threshold {
                    clippedCount += 1
                }
            }
        }
        
        let totalSamples = frameLength * channelCount
        let ratio = Float(clippedCount) / Float(totalSamples)
        
        return ClippingAnalysis(
            hasClipping: clippedCount > 0,
            ratio: ratio,
            count: clippedCount
        )
    }
    
    private func analyzeNoise(buffer: AVAudioPCMBuffer, sampleRate: Double) -> NoiseAnalysis {
        guard let channelData = buffer.floatChannelData else {
            return NoiseAnalysis(floor: -Float.infinity, snr: 0, needsDenoising: false)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Find quiet sections (potential noise floor)
        let blockSize = Int(sampleRate * 0.1)  // 100ms blocks
        let blockCount = frameLength / blockSize
        
        var quietestRMS: Float = Float.infinity
        var signalRMS: Float = 0
        var signalBlocks = 0
        
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            
            for block in 0..<blockCount {
                let offset = block * blockSize
                var blockSumSquares: Float = 0
                vDSP_svesq(samples + offset, 1, &blockSumSquares, vDSP_Length(blockSize))
                let blockRMS = sqrt(blockSumSquares / Float(blockSize))
                
                // Track quietest block as potential noise floor
                if blockRMS > 0.0001 {  // Not complete silence
                    quietestRMS = min(quietestRMS, blockRMS)
                }
                
                // Track louder blocks as signal
                if blockRMS > 0.01 {
                    signalRMS += blockRMS
                    signalBlocks += 1
                }
            }
        }
        
        let noiseFloorDB = quietestRMS < Float.infinity && quietestRMS > 0 ?
            20 * log10(quietestRMS) : config.noiseFloorThreshold
        
        let avgSignalRMS = signalBlocks > 0 ? signalRMS / Float(signalBlocks) : 0
        let snr: Float
        if avgSignalRMS > 0 && quietestRMS > 0 && quietestRMS < Float.infinity {
            snr = 20 * log10(avgSignalRMS / quietestRMS)
        } else {
            snr = 60  // Assume good SNR if can't calculate
        }
        
        let needsDenoising = noiseFloorDB > config.noiseFloorThreshold || snr < 20
        
        return NoiseAnalysis(floor: noiseFloorDB, snr: snr, needsDenoising: needsDenoising)
    }
    
    private func calculateLoudness(buffer: AVAudioPCMBuffer, sampleRate: Double) -> LoudnessAnalysis {
        guard let channelData = buffer.floatChannelData else {
            return LoudnessAnalysis(integrated: -Float.infinity, range: 0, needsNormalization: true)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let blockSize = config.loudnessBlockSize
        let blockCount = frameLength / blockSize
        
        // Simplified LUFS calculation (K-weighted)
        // Full implementation would use proper K-weighting filter
        var blockLoudness: [Float] = []
        
        for block in 0..<blockCount {
            var blockPower: Float = 0
            
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                let offset = block * blockSize
                
                var sumSquares: Float = 0
                vDSP_svesq(samples + offset, 1, &sumSquares, vDSP_Length(blockSize))
                blockPower += sumSquares / Float(blockSize)
            }
            
            blockPower /= Float(channelCount)
            
            if blockPower > 0 {
                // Convert to LUFS-like value
                let lufs = -0.691 + 10 * log10(blockPower)
                blockLoudness.append(lufs)
            }
        }
        
        guard !blockLoudness.isEmpty else {
            return LoudnessAnalysis(integrated: -70, range: 0, needsNormalization: true)
        }
        
        // Integrated loudness (gated)
        let sortedLoudness = blockLoudness.sorted()
        let gateThreshold = sortedLoudness[sortedLoudness.count / 10]  // Bottom 10% as gate
        let gatedLoudness = blockLoudness.filter { $0 > gateThreshold }
        
        let integrated = gatedLoudness.reduce(0, +) / Float(gatedLoudness.count)
        
        // Loudness range (simplified)
        let p10 = sortedLoudness[Int(Float(sortedLoudness.count) * 0.1)]
        let p95 = sortedLoudness[Int(Float(sortedLoudness.count) * 0.95)]
        let range = p95 - p10
        
        let needsNormalization = abs(integrated - config.targetLUFS) > 3  // More than 3 LUFS off
        
        return LoudnessAnalysis(integrated: integrated, range: range, needsNormalization: needsNormalization)
    }
    
    private func assessQuality(
        levels: LevelAnalysis,
        clipping: ClippingAnalysis,
        noise: NoiseAnalysis,
        loudness: LoudnessAnalysis
    ) -> QualityAssessment {
        var score: Float = 1.0
        var issues: [AudioQualityIssue] = []
        
        // Check for clipping
        if clipping.hasClipping {
            if clipping.ratio > 0.01 {
                score -= 0.4
                issues.append(.severeClipping)
            } else if clipping.ratio > 0.001 {
                score -= 0.2
                issues.append(.minorClipping)
            } else {
                score -= 0.1
                issues.append(.occasionalClipping)
            }
        }
        
        // Check noise
        if noise.needsDenoising {
            score -= 0.2
            issues.append(.highNoise)
        }
        
        // Check levels
        if levels.peak < -12 {
            score -= 0.1
            issues.append(.lowLevel)
        }
        
        if loudness.needsNormalization {
            score -= 0.1
            issues.append(.loudnessOff)
        }
        
        // Check dynamic range
        if levels.dynamicRange < 6 {
            score -= 0.1
            issues.append(.overCompressed)
        } else if levels.dynamicRange > 40 {
            score -= 0.05
            issues.append(.highDynamicRange)
        }
        
        let isUsable = score > 0.5 && !issues.contains(.severeClipping)
        
        return QualityAssessment(score: max(0, score), isUsable: isUsable, issues: issues)
    }
}

// MARK: - Internal Types

private struct LevelAnalysis {
    let peak: Float
    let rms: Float
    let dynamicRange: Float
}

private struct ClippingAnalysis {
    let hasClipping: Bool
    let ratio: Float
    let count: Int
}

private struct NoiseAnalysis {
    let floor: Float
    let snr: Float
    let needsDenoising: Bool
}

private struct LoudnessAnalysis {
    let integrated: Float
    let range: Float
    let needsNormalization: Bool
}

private struct QualityAssessment {
    let score: Float
    let isUsable: Bool
    let issues: [AudioQualityIssue]
}

// MARK: - Public Types

/// Audio quality issue types
public enum AudioQualityIssue: String, Codable, Sendable {
    case severeClipping = "severe_clipping"
    case minorClipping = "minor_clipping"
    case occasionalClipping = "occasional_clipping"
    case highNoise = "high_noise"
    case lowLevel = "low_level"
    case loudnessOff = "loudness_off"
    case overCompressed = "over_compressed"
    case highDynamicRange = "high_dynamic_range"
}

/// Complete audio metrics result
public struct AudioMetrics: Codable, Sendable, Equatable {
    // MARK: - Basic Info
    public let duration: Double
    public let sampleRate: Int
    public let channels: Int
    
    // MARK: - Levels (dBFS)
    public let peakLevel: Float
    public let rmsLevel: Float
    public let lufs: Float
    public let loudnessRange: Float
    public let dynamicRange: Float
    
    // MARK: - Noise
    public let noiseFloor: Float
    public let signalToNoise: Float
    
    // MARK: - Clipping
    public let hasClipping: Bool
    public let clippingRatio: Float
    public let clippingSamples: Int
    
    // MARK: - Quality
    public let needsDenoising: Bool
    public let needsNormalization: Bool
    public let isUsable: Bool
    public let qualityScore: Float
    public let issues: [AudioQualityIssue]
}

/// Quick audio metrics (subset for fast analysis)
public struct QuickAudioMetrics: Codable, Sendable, Equatable {
    public let peakLevel: Float
    public let rmsLevel: Float
    public let hasClipping: Bool
    public let dynamicRange: Float
}
