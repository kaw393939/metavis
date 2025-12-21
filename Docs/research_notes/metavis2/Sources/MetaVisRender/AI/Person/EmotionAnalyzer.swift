// EmotionAnalyzer.swift
// MetaVisRender
//
// Created for Sprint 06: Person Intelligence
// Multi-modal emotion analysis from face and voice

import Foundation
import CoreGraphics
import Accelerate
import AVFoundation

// MARK: - Emotion Analyzer

/// Analyzes emotions from face and voice signals,
/// fusing them into a unified emotional state.
public actor EmotionAnalyzer {
    
    // MARK: - Types
    
    public enum Error: Swift.Error, Equatable {
        case invalidFaceImage
        case audioExtractionFailed
        case analysisTimeout
    }
    
    public struct Config: Sendable {
        /// Weight for face emotion (0-1, remainder goes to voice)
        public let faceWeight: Float
        
        /// Minimum confidence to report emotion
        public let minConfidence: Float
        
        /// Smoothing factor for temporal consistency (0-1)
        public let temporalSmoothing: Float
        
        /// Sample rate for emotion timeline (samples per second)
        public let sampleRate: Double
        
        public init(
            faceWeight: Float = 0.6,
            minConfidence: Float = 0.3,
            temporalSmoothing: Float = 0.3,
            sampleRate: Double = 1.0
        ) {
            self.faceWeight = faceWeight
            self.minConfidence = minConfidence
            self.temporalSmoothing = temporalSmoothing
            self.sampleRate = sampleRate
        }
        
        public static let `default` = Config()
        
        /// Face-focused analysis
        public static let faceHeavy = Config(faceWeight: 0.8)
        
        /// Voice-focused analysis
        public static let voiceHeavy = Config(faceWeight: 0.3)
    }
    
    // MARK: - Properties
    
    private let config: Config
    private var previousEmotion: FusedEmotion?
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Face Emotion Analysis
    
    /// Analyze emotion from a face image
    public func analyzeFace(_ face: CGImage) async throws -> FaceEmotion {
        // Extract face features for emotion classification
        let features = try extractFaceFeatures(from: face)
        
        // Classify emotion based on features
        let (category, probabilities) = classifyEmotion(from: features)
        
        // Compute valence and arousal
        let valence = computeValence(probabilities: probabilities)
        let arousal = computeArousal(probabilities: probabilities)
        
        // Extract expression metrics
        let mouthOpenness = features.mouthOpenRatio
        let eyeOpenness = features.eyeOpenRatio
        let browRaise = features.browPosition
        let smileIntensity = features.smileIntensity
        
        return FaceEmotion(
            category: category,
            confidence: probabilities[category] ?? 0.5,
            probabilities: probabilities,
            valence: valence,
            arousal: arousal,
            mouthOpenness: mouthOpenness,
            eyeOpenness: eyeOpenness,
            browRaise: browRaise,
            smileIntensity: smileIntensity
        )
    }
    
    // MARK: - Voice Emotion Analysis
    
    /// Analyze emotion from a voice segment
    public func analyzeVoice(
        _ audioURL: URL,
        segment: ClosedRange<Double>
    ) async throws -> VoiceEmotion {
        // Extract prosodic features
        let features = try await extractVoiceFeatures(
            from: audioURL,
            segment: segment
        )
        
        // Classify emotion based on prosody
        let (category, confidence) = classifyVoiceEmotion(from: features)
        
        // Compute valence/arousal from prosody
        let valence = computeVoiceValence(features: features)
        let arousal = computeVoiceArousal(features: features)
        
        return VoiceEmotion(
            category: category,
            confidence: confidence,
            valence: valence,
            arousal: arousal,
            pitchMean: features.pitchMean,
            pitchVariation: features.pitchVariation,
            energy: features.energy,
            speechRate: features.speechRate
        )
    }
    
    // MARK: - Fusion
    
    /// Fuse face and voice emotions into a unified result
    public func fuse(
        face: FaceEmotion?,
        voice: VoiceEmotion?
    ) -> FusedEmotion {
        // Handle cases where one modality is missing
        if let face = face, voice == nil {
            return FusedEmotion(
                category: face.category,
                confidence: face.confidence,
                valence: face.valence,
                arousal: face.arousal,
                faceEmotion: face,
                voiceEmotion: nil,
                faceWeight: 1.0
            )
        }
        
        if let voice = voice, face == nil {
            return FusedEmotion(
                category: voice.category,
                confidence: voice.confidence,
                valence: voice.valence,
                arousal: voice.arousal,
                faceEmotion: nil,
                voiceEmotion: voice,
                faceWeight: 0.0
            )
        }
        
        guard let face = face, let voice = voice else {
            return FusedEmotion(
                category: .neutral,
                confidence: 0.5,
                valence: 0,
                arousal: 0.2,
                faceEmotion: nil,
                voiceEmotion: nil,
                faceWeight: 0.5
            )
        }
        
        // Weighted fusion
        let faceW = config.faceWeight
        let voiceW = 1 - faceW
        
        // Fuse valence and arousal
        let fusedValence = face.valence * faceW + voice.valence * voiceW
        let fusedArousal = face.arousal * faceW + voice.arousal * voiceW
        
        // Determine primary emotion by weighted vote
        let category = determineFusedCategory(face: face, voice: voice, faceWeight: faceW)
        
        // Compute fused confidence
        let confidence = face.confidence * faceW + voice.confidence * voiceW
        
        var result = FusedEmotion(
            category: category,
            confidence: confidence,
            valence: fusedValence,
            arousal: fusedArousal,
            faceEmotion: face,
            voiceEmotion: voice,
            faceWeight: faceW
        )
        
        // Apply temporal smoothing if we have a previous emotion
        if let previous = previousEmotion {
            result = smoothEmotion(current: result, previous: previous)
        }
        
        previousEmotion = result
        return result
    }
    
    // MARK: - Timeline Generation
    
    /// Generate emotion timeline for a clip
    public func generateTimeline(
        faceEmotions: [(timestamp: Double, emotion: FaceEmotion)],
        voiceEmotions: [(timestamp: Double, emotion: VoiceEmotion)],
        duration: Double
    ) -> EmotionTimeline {
        var samples: [EmotionSample] = []
        let step = 1.0 / config.sampleRate
        
        var time: Double = 0
        while time <= duration {
            // Find nearest face emotion
            let nearestFace = faceEmotions.min { 
                abs($0.timestamp - time) < abs($1.timestamp - time) 
            }
            let faceEmotion = nearestFace.flatMap { 
                abs($0.timestamp - time) < step * 2 ? $0.emotion : nil 
            }
            
            // Find nearest voice emotion
            let nearestVoice = voiceEmotions.min { 
                abs($0.timestamp - time) < abs($1.timestamp - time) 
            }
            let voiceEmotion = nearestVoice.flatMap { 
                abs($0.timestamp - time) < step * 2 ? $0.emotion : nil 
            }
            
            // Fuse
            let fused = fuse(face: faceEmotion, voice: voiceEmotion)
            
            samples.append(EmotionSample(
                timestamp: time,
                personId: nil,
                emotion: fused
            ))
            
            time += step
        }
        
        // Detect peaks
        let peaks = detectEmotionPeaks(samples: samples)
        
        // Compute averages
        let avgValence = samples.reduce(0) { $0 + $1.emotion.valence } / Float(samples.count)
        let avgArousal = samples.reduce(0) { $0 + $1.emotion.arousal } / Float(samples.count)
        
        // Find dominant emotion
        var emotionCounts: [EmotionCategory: Int] = [:]
        for sample in samples {
            emotionCounts[sample.emotion.category, default: 0] += 1
        }
        let dominantEmotion = emotionCounts.max { $0.value < $1.value }?.key ?? .neutral
        
        return EmotionTimeline(
            samples: samples,
            peaks: peaks,
            averageValence: avgValence,
            averageArousal: avgArousal,
            dominantEmotion: dominantEmotion
        )
    }
    
    // MARK: - Private Methods - Face Features
    
    private struct FaceFeatures {
        let mouthOpenRatio: Float
        let eyeOpenRatio: Float
        let browPosition: Float
        let smileIntensity: Float
        let jawDrop: Float
        let lipCornerPull: Float
        let innerBrowRaise: Float
    }
    
    private func extractFaceFeatures(from image: CGImage) throws -> FaceFeatures {
        // Simplified feature extraction based on image analysis
        // In production, would use Vision face landmarks
        
        guard image.width > 10 && image.height > 10 else {
            throw Error.invalidFaceImage
        }
        
        // Analyze different regions of the face
        // Mouth region (bottom third)
        // Eye region (middle third, upper half)
        // Brow region (top quarter)
        
        let mouthOpenRatio = analyzeRegion(
            image: image,
            region: CGRect(x: 0.25, y: 0.6, width: 0.5, height: 0.3)
        )
        
        let eyeOpenRatio = analyzeRegion(
            image: image,
            region: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.2)
        )
        
        let browPosition = analyzeRegion(
            image: image,
            region: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2)
        )
        
        // Smile detection based on lower face horizontal gradient
        let smileIntensity = analyzeSmile(image: image)
        
        return FaceFeatures(
            mouthOpenRatio: mouthOpenRatio,
            eyeOpenRatio: eyeOpenRatio,
            browPosition: browPosition,
            smileIntensity: smileIntensity,
            jawDrop: mouthOpenRatio,
            lipCornerPull: smileIntensity,
            innerBrowRaise: browPosition
        )
    }
    
    private func analyzeRegion(image: CGImage, region: CGRect) -> Float {
        // Convert normalized region to pixels
        let pixelRect = CGRect(
            x: region.minX * CGFloat(image.width),
            y: region.minY * CGFloat(image.height),
            width: region.width * CGFloat(image.width),
            height: region.height * CGFloat(image.height)
        )
        
        guard let cropped = image.cropping(to: pixelRect),
              let data = cropped.dataProvider?.data,
              let pixels = CFDataGetBytePtr(data) else {
            return 0.5
        }
        
        // Compute variance as a measure of "activity"
        var sum: Float = 0
        var sumSq: Float = 0
        var count: Float = 0
        
        let bytesPerRow = cropped.bytesPerRow
        for y in 0..<cropped.height {
            for x in 0..<cropped.width {
                let offset = y * bytesPerRow + x * 4
                let intensity = (Float(pixels[offset]) + Float(pixels[offset + 1]) + Float(pixels[offset + 2])) / (3 * 255)
                sum += intensity
                sumSq += intensity * intensity
                count += 1
            }
        }
        
        let mean = sum / count
        let variance = (sumSq / count) - (mean * mean)
        
        // Map variance to 0-1 range
        return min(1, variance * 10)
    }
    
    private func analyzeSmile(image: CGImage) -> Float {
        // Analyze horizontal brightness gradient in lower face
        // Smiles tend to create upward curves (lighter corners)
        
        let lowerThird = CGRect(
            x: 0,
            y: CGFloat(image.height) * 0.6,
            width: CGFloat(image.width),
            height: CGFloat(image.height) * 0.3
        )
        
        guard let cropped = image.cropping(to: lowerThird),
              let data = cropped.dataProvider?.data,
              let pixels = CFDataGetBytePtr(data) else {
            return 0.3
        }
        
        // Compare corner brightness to center
        let width = cropped.width
        let height = cropped.height
        let bytesPerRow = cropped.bytesPerRow
        
        var leftSum: Float = 0
        var centerSum: Float = 0
        var rightSum: Float = 0
        var count: Float = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let intensity = (Float(pixels[offset]) + Float(pixels[offset + 1]) + Float(pixels[offset + 2])) / (3 * 255)
                
                if x < width / 4 {
                    leftSum += intensity
                } else if x > 3 * width / 4 {
                    rightSum += intensity
                } else {
                    centerSum += intensity
                }
                count += 1
            }
        }
        
        let cornerBrightness = (leftSum + rightSum) / 2
        let centerBrightness = centerSum
        
        // Smiles: corners brighter than center
        let smileScore = (cornerBrightness - centerBrightness * 0.5) / cornerBrightness
        return max(0, min(1, smileScore + 0.5))
    }
    
    private func classifyEmotion(from features: FaceFeatures) -> (EmotionCategory, [EmotionCategory: Float]) {
        // Simple rule-based classification
        var probabilities: [EmotionCategory: Float] = [:]
        
        // Happy: high smile intensity, open eyes
        probabilities[.happy] = features.smileIntensity * 0.7 + features.eyeOpenRatio * 0.3
        
        // Sad: low everything, droopy
        probabilities[.sad] = (1 - features.smileIntensity) * 0.5 * (1 - features.browPosition) * 0.5
        
        // Angry: lowered brows, tense mouth
        probabilities[.angry] = (1 - features.browPosition) * 0.6 + (1 - features.smileIntensity) * 0.4
        
        // Surprised: high brow, open mouth, wide eyes
        probabilities[.surprised] = features.browPosition * 0.3 + features.mouthOpenRatio * 0.4 + features.eyeOpenRatio * 0.3
        
        // Fearful: high brow, wide eyes, no smile
        probabilities[.fearful] = features.browPosition * 0.3 + features.eyeOpenRatio * 0.4 + (1 - features.smileIntensity) * 0.3
        
        // Disgusted: lowered brow, narrowed eyes
        probabilities[.disgusted] = (1 - features.browPosition) * 0.4 + (1 - features.eyeOpenRatio) * 0.4 + (1 - features.smileIntensity) * 0.2
        
        // Contempt: asymmetric (simplified as neutral-ish)
        probabilities[.contempt] = 0.2
        
        // Neutral: baseline when nothing stands out
        let maxProb = probabilities.values.max() ?? 0
        probabilities[.neutral] = max(0, 0.5 - maxProb * 0.5)
        
        // Normalize
        let total = probabilities.values.reduce(0, +)
        if total > 0 {
            for key in probabilities.keys {
                probabilities[key]! /= total
            }
        }
        
        // Find winner
        let category = probabilities.max { $0.value < $1.value }?.key ?? .neutral
        
        return (category, probabilities)
    }
    
    // MARK: - Private Methods - Voice Features
    
    private struct VoiceFeatures {
        let pitchMean: Float
        let pitchVariation: Float
        let energy: Float
        let speechRate: Float
        let spectralCentroid: Float
    }
    
    private func extractVoiceFeatures(
        from url: URL,
        segment: ClosedRange<Double>
    ) async throws -> VoiceFeatures {
        // Load audio file
        guard let audioFile = try? AVAudioFile(forReading: url) else {
            throw Error.audioExtractionFailed
        }
        
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        
        // Calculate frame range
        let startFrame = AVAudioFramePosition(segment.lowerBound * sampleRate)
        let frameCount = AVAudioFrameCount((segment.upperBound - segment.lowerBound) * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw Error.audioExtractionFailed
        }
        
        audioFile.framePosition = startFrame
        try audioFile.read(into: buffer, frameCount: frameCount)
        
        guard let channelData = buffer.floatChannelData?[0] else {
            throw Error.audioExtractionFailed
        }
        
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        
        // Extract features
        let energy = computeEnergy(samples)
        let spectralCentroid = computeSpectralCentroid(samples, sampleRate: Float(sampleRate))
        
        // Estimate pitch (simplified zero-crossing rate as proxy)
        let zcr = computeZeroCrossingRate(samples)
        let pitchMean = zcr * Float(sampleRate) / 2  // Rough pitch estimate
        
        // Pitch variation (use energy variance as proxy)
        let pitchVariation = computeEnergyVariation(samples)
        
        // Speech rate (use energy above threshold)
        let speechRate = computeSpeechRate(samples, sampleRate: Float(sampleRate))
        
        return VoiceFeatures(
            pitchMean: pitchMean,
            pitchVariation: pitchVariation,
            energy: energy,
            speechRate: speechRate,
            spectralCentroid: spectralCentroid
        )
    }
    
    private func computeEnergy(_ samples: [Float]) -> Float {
        var sumSq: Float = 0
        vDSP_svesq(samples, 1, &sumSq, vDSP_Length(samples.count))
        return sqrt(sumSq / Float(samples.count))
    }
    
    private func computeZeroCrossingRate(_ samples: [Float]) -> Float {
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0) != (samples[i-1] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count)
    }
    
    private func computeSpectralCentroid(_ samples: [Float], sampleRate: Float) -> Float {
        // Simplified: use mean absolute value as proxy
        var mean: Float = 0
        vDSP_meamgv(samples, 1, &mean, vDSP_Length(samples.count))
        return mean * sampleRate / 2
    }
    
    private func computeEnergyVariation(_ samples: [Float]) -> Float {
        // Compute energy in windows and measure variation
        let windowSize = min(1024, samples.count / 4)
        guard windowSize > 0 else { return 0 }
        
        var energies: [Float] = []
        var offset = 0
        while offset + windowSize <= samples.count {
            let window = Array(samples[offset..<(offset + windowSize)])
            energies.append(computeEnergy(window))
            offset += windowSize / 2
        }
        
        guard energies.count > 1 else { return 0 }
        
        // Compute standard deviation
        let mean = energies.reduce(0, +) / Float(energies.count)
        let variance = energies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(energies.count)
        return sqrt(variance)
    }
    
    private func computeSpeechRate(_ samples: [Float], sampleRate: Float) -> Float {
        // Count "speech events" (energy above threshold)
        let threshold = computeEnergy(samples) * 0.5
        let windowSize = Int(sampleRate * 0.02)  // 20ms windows
        
        var speechWindows = 0
        var offset = 0
        var totalWindows = 0
        
        while offset + windowSize <= samples.count {
            let window = Array(samples[offset..<(offset + windowSize)])
            if computeEnergy(window) > threshold {
                speechWindows += 1
            }
            totalWindows += 1
            offset += windowSize
        }
        
        return totalWindows > 0 ? Float(speechWindows) / Float(totalWindows) : 0
    }
    
    private func classifyVoiceEmotion(from features: VoiceFeatures) -> (EmotionCategory, Float) {
        // Simple rule-based classification based on prosody
        
        // High energy + high pitch variation → excited emotions (angry, happy, surprised)
        // Low energy + low variation → calm emotions (sad, neutral)
        
        let excitement = (features.energy * 0.5 + features.pitchVariation * 0.3 + features.speechRate * 0.2)
        
        if excitement > 0.7 {
            // High arousal - could be happy, angry, or surprised
            if features.pitchMean > 200 {
                return (.surprised, 0.6)
            } else if features.speechRate > 0.6 {
                return (.angry, 0.5)
            } else {
                return (.happy, 0.5)
            }
        } else if excitement < 0.3 {
            // Low arousal
            if features.energy < 0.1 {
                return (.sad, 0.5)
            } else {
                return (.neutral, 0.6)
            }
        } else {
            return (.neutral, 0.5)
        }
    }
    
    // MARK: - Private Methods - Fusion Helpers
    
    private func computeValence(probabilities: [EmotionCategory: Float]) -> Float {
        var valence: Float = 0
        for (emotion, prob) in probabilities {
            valence += emotion.typicalValence * prob
        }
        return valence
    }
    
    private func computeArousal(probabilities: [EmotionCategory: Float]) -> Float {
        var arousal: Float = 0
        for (emotion, prob) in probabilities {
            arousal += emotion.typicalArousal * prob
        }
        return arousal
    }
    
    private func computeVoiceValence(features: VoiceFeatures) -> Float {
        // Higher pitch and energy generally correlate with positive valence
        return (features.pitchMean / 300 + features.energy) * 0.5 - 0.3
    }
    
    private func computeVoiceArousal(features: VoiceFeatures) -> Float {
        // High energy and speech rate indicate high arousal
        return min(1, features.energy + features.speechRate * 0.5)
    }
    
    private func determineFusedCategory(
        face: FaceEmotion,
        voice: VoiceEmotion,
        faceWeight: Float
    ) -> EmotionCategory {
        // If both agree, use that
        if face.category == voice.category {
            return face.category
        }
        
        // Weight by confidence
        let faceScore = face.confidence * faceWeight
        let voiceScore = voice.confidence * (1 - faceWeight)
        
        return faceScore > voiceScore ? face.category : voice.category
    }
    
    private func smoothEmotion(current: FusedEmotion, previous: FusedEmotion) -> FusedEmotion {
        let alpha = config.temporalSmoothing
        
        let smoothedValence = previous.valence * alpha + current.valence * (1 - alpha)
        let smoothedArousal = previous.arousal * alpha + current.arousal * (1 - alpha)
        
        return FusedEmotion(
            category: current.category,  // Keep current category
            confidence: current.confidence,
            valence: smoothedValence,
            arousal: smoothedArousal,
            faceEmotion: current.faceEmotion,
            voiceEmotion: current.voiceEmotion,
            faceWeight: current.faceWeight
        )
    }
    
    private func detectEmotionPeaks(samples: [EmotionSample]) -> [EmotionPeak] {
        var peaks: [EmotionPeak] = []
        
        // Look for high-arousal or extreme-valence moments
        let arousalThreshold: Float = 0.7
        let valenceThreshold: Float = 0.6
        
        var inPeak = false
        var peakStart = 0.0
        var peakEmotion: EmotionCategory = .neutral
        var peakIntensity: Float = 0
        
        for sample in samples {
            let intensity = max(abs(sample.emotion.valence), sample.emotion.arousal)
            let isPeaking = sample.emotion.arousal > arousalThreshold || 
                           abs(sample.emotion.valence) > valenceThreshold
            
            if isPeaking && !inPeak {
                // Start of peak
                inPeak = true
                peakStart = sample.timestamp
                peakEmotion = sample.emotion.category
                peakIntensity = intensity
            } else if isPeaking && inPeak {
                // Continue peak, track max intensity
                if intensity > peakIntensity {
                    peakIntensity = intensity
                    peakEmotion = sample.emotion.category
                }
            } else if !isPeaking && inPeak {
                // End of peak
                inPeak = false
                peaks.append(EmotionPeak(
                    timestamp: peakStart,
                    duration: sample.timestamp - peakStart,
                    personId: sample.personId,
                    emotion: peakEmotion,
                    intensity: peakIntensity
                ))
            }
        }
        
        // Handle peak at end
        if inPeak, let last = samples.last {
            peaks.append(EmotionPeak(
                timestamp: peakStart,
                duration: last.timestamp - peakStart,
                personId: nil,
                emotion: peakEmotion,
                intensity: peakIntensity
            ))
        }
        
        return peaks
    }
    
    // MARK: - Reset
    
    /// Reset temporal smoothing state
    public func reset() {
        previousEmotion = nil
    }
}
