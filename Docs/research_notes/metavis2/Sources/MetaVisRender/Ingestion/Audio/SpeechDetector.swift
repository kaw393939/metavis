// Sources/MetaVisRender/Ingestion/Audio/SpeechDetector.swift
// Sprint 03: Voice Activity Detection (VAD)

import AVFoundation
import Foundation
import Accelerate

// MARK: - Speech Detector

/// Detects speech vs silence/music/noise in audio
public actor SpeechDetector {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Minimum segment duration in seconds
        public let minSegmentDuration: Double
        /// Energy threshold for speech detection (0-1)
        public let energyThreshold: Float
        /// Zero crossing rate threshold
        public let zcrThreshold: Float
        /// Smoothing window size in frames
        public let smoothingWindow: Int
        /// Merge segments closer than this (seconds)
        public let mergeThreshold: Double
        
        public init(
            minSegmentDuration: Double = 0.3,
            energyThreshold: Float = 0.02,
            zcrThreshold: Float = 0.1,
            smoothingWindow: Int = 5,
            mergeThreshold: Double = 0.5
        ) {
            self.minSegmentDuration = minSegmentDuration
            self.energyThreshold = energyThreshold
            self.zcrThreshold = zcrThreshold
            self.smoothingWindow = smoothingWindow
            self.mergeThreshold = mergeThreshold
        }
        
        public static let `default` = Config()
        
        public static let sensitive = Config(
            minSegmentDuration: 0.2,
            energyThreshold: 0.01,
            smoothingWindow: 3
        )
        
        public static let conservative = Config(
            minSegmentDuration: 0.5,
            energyThreshold: 0.05,
            smoothingWindow: 7
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Detect speech segments in an audio file
    public func detect(in audioURL: URL) async throws -> SpeechDetectionResult {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw IngestionError.fileNotFound(audioURL)
        }
        
        // Load audio file
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw IngestionError.insufficientMemory
        }
        
        try audioFile.read(into: buffer)
        
        return try await detect(in: buffer, sampleRate: format.sampleRate)
    }
    
    /// Detect speech segments in an audio buffer
    public func detect(in buffer: AVAudioPCMBuffer, sampleRate: Double) async throws -> SpeechDetectionResult {
        guard let channelData = buffer.floatChannelData?[0] else {
            throw IngestionError.corruptedFile("No audio data")
        }
        
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        
        // Frame-based analysis
        let frameSize = Int(sampleRate * 0.025)  // 25ms frames
        let hopSize = Int(sampleRate * 0.010)    // 10ms hop
        let frameCount_ = (samples.count - frameSize) / hopSize + 1
        
        var energies: [Float] = []
        var zcrs: [Float] = []
        
        // Calculate features for each frame
        for i in 0..<frameCount_ {
            let start = i * hopSize
            let end = min(start + frameSize, samples.count)
            let frame = Array(samples[start..<end])
            
            // Root Mean Square energy
            let energy = calculateRMS(frame)
            energies.append(energy)
            
            // Zero Crossing Rate
            let zcr = calculateZCR(frame)
            zcrs.append(zcr)
        }
        
        // Normalize energies
        let maxEnergy = energies.max() ?? 1.0
        if maxEnergy > 0 {
            energies = energies.map { $0 / maxEnergy }
        }
        
        // Apply smoothing
        let smoothedEnergies = smooth(energies, windowSize: config.smoothingWindow)
        
        // Classify frames
        var frameLabels: [SpeechActivity.ActivityType] = []
        
        for i in 0..<frameCount_ {
            let energy = smoothedEnergies[i]
            let zcr = zcrs[i]
            
            if energy > config.energyThreshold {
                // High energy - could be speech or music
                if zcr > config.zcrThreshold {
                    frameLabels.append(.speech)
                } else {
                    // Low ZCR with high energy could be music
                    frameLabels.append(.speech)  // Default to speech, music detection is more complex
                }
            } else {
                frameLabels.append(.silence)
            }
        }
        
        // Convert frame labels to segments
        let frameDuration = Double(hopSize) / sampleRate
        var segments: [SpeechActivity] = []
        
        var currentType = frameLabels.first ?? .silence
        var segmentStart = 0.0
        
        for (i, label) in frameLabels.enumerated() {
            if label != currentType {
                let segmentEnd = Double(i) * frameDuration
                let duration = segmentEnd - segmentStart
                
                if duration >= config.minSegmentDuration {
                    segments.append(SpeechActivity(
                        start: segmentStart,
                        end: segmentEnd,
                        type: currentType,
                        confidence: 0.8
                    ))
                }
                
                currentType = label
                segmentStart = segmentEnd
            }
        }
        
        // Add final segment
        let totalDuration = Double(samples.count) / sampleRate
        if totalDuration - segmentStart >= config.minSegmentDuration {
            segments.append(SpeechActivity(
                start: segmentStart,
                end: totalDuration,
                type: currentType,
                confidence: 0.8
            ))
        }
        
        // Merge nearby segments of same type
        segments = mergeSegments(segments)
        
        return SpeechDetectionResult(segments: segments)
    }
    
    // MARK: - Feature Extraction
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    private func calculateZCR(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0) != (samples[i-1] >= 0) {
                crossings += 1
            }
        }
        
        return Float(crossings) / Float(samples.count - 1)
    }
    
    private func smooth(_ values: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 1 && values.count > windowSize else { return values }
        
        var result = [Float](repeating: 0, count: values.count)
        let halfWindow = windowSize / 2
        
        for i in 0..<values.count {
            let start = max(0, i - halfWindow)
            let end = min(values.count, i + halfWindow + 1)
            let sum = values[start..<end].reduce(0, +)
            result[i] = sum / Float(end - start)
        }
        
        return result
    }
    
    private func mergeSegments(_ segments: [SpeechActivity]) -> [SpeechActivity] {
        guard segments.count > 1 else { return segments }
        
        var merged: [SpeechActivity] = []
        var current = segments[0]
        
        for i in 1..<segments.count {
            let next = segments[i]
            
            // Merge if same type and close enough
            if current.type == next.type && (next.start - current.end) < config.mergeThreshold {
                current = SpeechActivity(
                    start: current.start,
                    end: next.end,
                    type: current.type,
                    confidence: (current.confidence + next.confidence) / 2
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        
        merged.append(current)
        return merged
    }
}

// MARK: - Convenience Extension

extension SpeechDetector {
    
    /// Quick check if audio has any speech
    public func hasSpeech(in audioURL: URL) async throws -> Bool {
        let result = try await detect(in: audioURL)
        return result.hasSpeech
    }
    
    /// Get only speech segments
    public func speechSegments(in audioURL: URL) async throws -> [SpeechActivity] {
        let result = try await detect(in: audioURL)
        return result.speechSegments
    }
    
    /// Calculate speech percentage
    public func speechPercentage(in audioURL: URL) async throws -> Float {
        let result = try await detect(in: audioURL)
        return result.speechRatio * 100
    }
}
