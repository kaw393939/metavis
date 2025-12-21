// AutoClipGenerator.swift
// MetaVisRender
//
// ML-based edit point detection and clip generation
// Uses scene detection, transient detection, action recognition, and clip ranking
// Sprint 08

import Foundation
import AVFoundation
import Accelerate
import CoreML

// MARK: - AutoClipGenerator

/// Generates highlight clips from analyzed footage using ML-based scoring
public actor AutoClipGenerator {
    
    // MARK: - Properties
    
    private let scoringWeights: ClipScoringWeights
    private let clipSceneDetector: ClipSceneDetector
    private let transientDetector: TransientDetector
    private let clipRanker: ClipRanker
    private let clipBuilder: ClipBuilder
    
    private var isProcessing = false
    private var currentProgress: Float = 0
    
    // MARK: - Initialization
    
    public init(weights: ClipScoringWeights = .default) {
        self.scoringWeights = weights
        self.clipSceneDetector = ClipSceneDetector()
        self.transientDetector = TransientDetector()
        self.clipRanker = ClipRanker(weights: weights)
        self.clipBuilder = ClipBuilder()
    }
    
    // MARK: - Public API
    
    /// Generate proposed clips from footage analysis
    public func generateClips(
        from analysis: FootageAnalysis,
        targetDuration: Double = AdvancedAIDefaults.targetHighlightDuration,
        style: EditStyle = .chronological,
        progress: AdvancedAIProgress? = nil
    ) async throws -> [ProposedClip] {
        guard !isProcessing else {
            throw AdvancedAIError.clipGenerationFailed("Already processing")
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Stage 1: Detect scene boundaries
        progress?(0.1, ClipGenerationStage.detectingScenes.rawValue)
        let sceneBoundaries = await clipSceneDetector.detectBoundaries(in: analysis)
        
        // Stage 2: Detect audio transients (beats, hits)
        progress?(0.25, ClipGenerationStage.analyzing.rawValue)
        let transients = await transientDetector.detectTransients(in: analysis)
        
        // Stage 3: Score all potential moments
        progress?(0.5, ClipGenerationStage.scoringMoments.rawValue)
        let scoredMoments = await clipRanker.scoreMoments(
            analysis: analysis,
            sceneBoundaries: sceneBoundaries,
            transients: transients
        )
        
        // Stage 4: Select best clips within duration budget
        progress?(0.75, ClipGenerationStage.selectingClips.rawValue)
        let selectedClips = clipBuilder.selectClips(
            from: scoredMoments,
            targetDuration: targetDuration,
            style: style
        )
        
        // Stage 5: Optimize flow and transitions
        progress?(0.9, ClipGenerationStage.optimizingFlow.rawValue)
        let optimizedClips = clipBuilder.optimizeFlow(
            clips: selectedClips,
            style: style
        )
        
        progress?(1.0, ClipGenerationStage.complete.rawValue)
        
        return optimizedClips
    }
    
    /// Generate a complete highlight reel
    public func generateHighlightReel(
        from analysis: FootageAnalysis,
        targetDuration: Double = AdvancedAIDefaults.targetHighlightDuration,
        style: EditStyle = .chronological,
        progress: AdvancedAIProgress? = nil
    ) async throws -> HighlightReel {
        let clips = try await generateClips(
            from: analysis,
            targetDuration: targetDuration,
            style: style,
            progress: progress
        )
        
        guard !clips.isEmpty else {
            throw AdvancedAIError.insufficientContent("No suitable clips found")
        }
        
        let transitions = clipBuilder.generateTransitions(for: clips, style: style)
        let totalDuration = clips.reduce(0) { $0 + $1.duration }
        
        return HighlightReel(
            clips: clips,
            totalDuration: totalDuration,
            style: style,
            transitions: transitions
        )
    }
    
    /// Find cut points within a time range
    public func findCutPoints(
        in analysis: FootageAnalysis,
        range: ClosedRange<Double>
    ) async -> [CutPoint] {
        var cutPoints: [CutPoint] = []
        
        // Find sentence boundaries from transcript
        if let transcript = analysis.transcript {
            for segment in transcript.segments {
                let segmentEnd = segment.startTime + segment.duration
                if range.contains(segment.startTime) {
                    cutPoints.append(CutPoint(
                        timestamp: segment.startTime,
                        type: .sentenceBoundary,
                        confidence: segment.confidence
                    ))
                }
                if range.contains(segmentEnd) {
                    cutPoints.append(CutPoint(
                        timestamp: segmentEnd,
                        type: .sentenceBoundary,
                        confidence: segment.confidence
                    ))
                }
            }
        }
        
        // Find silence pauses
        let silences = findSilences(in: analysis, range: range)
        cutPoints.append(contentsOf: silences)
        
        // Find scene changes
        let sceneChanges = await clipSceneDetector.detectBoundaries(in: analysis)
        for boundary in sceneChanges where range.contains(boundary.timestamp) {
            cutPoints.append(CutPoint(
                timestamp: boundary.timestamp,
                type: .sceneChange,
                confidence: boundary.confidence
            ))
        }
        
        // Sort by timestamp
        return cutPoints.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Private Helpers
    
    private func findSilences(in analysis: FootageAnalysis, range: ClosedRange<Double>) -> [CutPoint] {
        var silences: [CutPoint] = []
        
        // Use speaker segments to find gaps
        if let speakerInfo = analysis.speakerInfo {
            let segments = speakerInfo.segments.filter { segment in
                let segmentEnd = segment.startTime + segment.duration
                return range.overlaps(segment.startTime...segmentEnd)
            }
            
            for i in 0..<(segments.count - 1) {
                let currentEnd = segments[i].startTime + segments[i].duration
                let nextStart = segments[i + 1].startTime
                let gap = nextStart - currentEnd
                
                if gap >= 0.3 && range.contains(currentEnd) {
                    silences.append(CutPoint(
                        timestamp: currentEnd + gap / 2,
                        type: .silencePause,
                        confidence: min(1.0, Float(gap) / 2.0)
                    ))
                }
            }
        }
        
        return silences
    }
}

// MARK: - FootageAnalysis Extension

/// Analysis data structure for clip generation
public struct FootageAnalysis: Sendable {
    public let duration: Double
    public let transcript: ClipTranscriptResult?
    public let speakerInfo: ClipSpeakerInfo?
    public let emotions: [TimedEmotion]?
    public let visualFeatures: [VisualFeature]?
    public let audioFeatures: AudioFeatures?
    
    public init(
        duration: Double,
        transcript: ClipTranscriptResult? = nil,
        speakerInfo: ClipSpeakerInfo? = nil,
        emotions: [TimedEmotion]? = nil,
        visualFeatures: [VisualFeature]? = nil,
        audioFeatures: AudioFeatures? = nil
    ) {
        self.duration = duration
        self.transcript = transcript
        self.speakerInfo = speakerInfo
        self.emotions = emotions
        self.visualFeatures = visualFeatures
        self.audioFeatures = audioFeatures
    }
}

/// Timed emotion observation
public struct TimedEmotion: Sendable {
    public let timestamp: Double
    public let duration: Double
    public let emotion: String
    public let intensity: Float
    
    public init(timestamp: Double, duration: Double, emotion: String, intensity: Float) {
        self.timestamp = timestamp
        self.duration = duration
        self.emotion = emotion
        self.intensity = intensity
    }
}

/// Visual feature at a point in time
public struct VisualFeature: Sendable {
    public let timestamp: Double
    public let faceCount: Int
    public let motion: Float
    public let brightness: Float
    public let complexity: Float
    
    public init(timestamp: Double, faceCount: Int, motion: Float, brightness: Float, complexity: Float) {
        self.timestamp = timestamp
        self.faceCount = faceCount
        self.motion = motion
        self.brightness = brightness
        self.complexity = complexity
    }
}

/// Audio features for clip analysis
public struct AudioFeatures: Sendable {
    public let rmsLevels: [Float]        // RMS per frame
    public let spectralCentroid: [Float]
    public let zeroCrossings: [Float]
    public let frameDuration: Double
    
    public init(rmsLevels: [Float], spectralCentroid: [Float], zeroCrossings: [Float], frameDuration: Double) {
        self.rmsLevels = rmsLevels
        self.spectralCentroid = spectralCentroid
        self.zeroCrossings = zeroCrossings
        self.frameDuration = frameDuration
    }
}

/// Transcript result for clip analysis
public struct ClipTranscriptResult: Sendable {
    public let segments: [ClipTranscriptSegment]
    
    public init(segments: [ClipTranscriptSegment]) {
        self.segments = segments
    }
}

/// Transcript segment for clip analysis
public struct ClipTranscriptSegment: Sendable {
    public let startTime: Double
    public let duration: Double
    public let text: String
    public let confidence: Float
    
    public init(startTime: Double, duration: Double, text: String, confidence: Float) {
        self.startTime = startTime
        self.duration = duration
        self.text = text
        self.confidence = confidence
    }
}

/// Speaker info for clip analysis
public struct ClipSpeakerInfo: Sendable {
    public let segments: [ClipSpeakerSegment]
    
    public init(segments: [ClipSpeakerSegment]) {
        self.segments = segments
    }
}

/// Speaker segment for clip analysis
public struct ClipSpeakerSegment: Sendable {
    public let speakerId: String
    public let startTime: Double
    public let duration: Double
    public let confidence: Float
    
    public init(speakerId: String, startTime: Double, duration: Double, confidence: Float) {
        self.speakerId = speakerId
        self.startTime = startTime
        self.duration = duration
        self.confidence = confidence
    }
}

// MARK: - ClipSceneDetector

/// Detects visual scene boundaries
public actor ClipSceneDetector {
    
    public struct SceneBoundary: Sendable {
        public let timestamp: Double
        public let confidence: Float
        public let type: SceneChangeType
    }
    
    public enum SceneChangeType: Sendable {
        case cut
        case dissolve
        case fade
        case wipe
    }
    
    public func detectBoundaries(in analysis: FootageAnalysis) async -> [SceneBoundary] {
        guard let visualFeatures = analysis.visualFeatures, visualFeatures.count > 1 else {
            return []
        }
        
        var boundaries: [SceneBoundary] = []
        let motionThreshold: Float = 0.7
        let brightnessThreshold: Float = 0.3
        
        for i in 1..<visualFeatures.count {
            let prev = visualFeatures[i - 1]
            let curr = visualFeatures[i]
            
            let motionDelta = abs(curr.motion - prev.motion)
            let brightnessDelta = abs(curr.brightness - prev.brightness)
            
            // Detect cuts (abrupt changes)
            if motionDelta > motionThreshold || brightnessDelta > brightnessThreshold {
                let confidence = max(motionDelta / motionThreshold, brightnessDelta / brightnessThreshold)
                boundaries.append(SceneBoundary(
                    timestamp: curr.timestamp,
                    confidence: min(1.0, confidence),
                    type: .cut
                ))
            }
        }
        
        return boundaries
    }
}

// MARK: - TransientDetector

/// Detects audio transients (beats, hits, impacts)
public actor TransientDetector {
    
    public struct Transient: Sendable {
        public let timestamp: Double
        public let strength: Float
        public let type: TransientType
    }
    
    public enum TransientType: Sendable {
        case beat
        case hit
        case speech
        case laughter
    }
    
    public func detectTransients(in analysis: FootageAnalysis) async -> [Transient] {
        guard let audioFeatures = analysis.audioFeatures else {
            return []
        }
        
        var transients: [Transient] = []
        let rmsThreshold: Float = 0.5
        let rmsLevels = audioFeatures.rmsLevels
        
        guard rmsLevels.count > 2 else { return [] }
        
        // Detect onset transients using RMS derivative
        for i in 2..<rmsLevels.count {
            let derivative = rmsLevels[i] - rmsLevels[i - 1]
            let secondDerivative = (rmsLevels[i] - 2 * rmsLevels[i - 1] + rmsLevels[i - 2])
            
            // Onset: positive first derivative, peak in second derivative
            if derivative > rmsThreshold && secondDerivative < 0 {
                let timestamp = Double(i) * audioFeatures.frameDuration
                transients.append(Transient(
                    timestamp: timestamp,
                    strength: min(1.0, derivative),
                    type: .beat
                ))
            }
        }
        
        return transients
    }
}

// MARK: - ClipRanker

/// Scores moments based on multiple factors
public actor ClipRanker {
    
    public struct ScoredMoment: Sendable {
        public let timestamp: Double
        public let score: Float
        public let reasons: [ClipReason]
        public let componentScores: ComponentScores
    }
    
    public struct ComponentScores: Sendable {
        public let speechEnergy: Float
        public let emotion: Float
        public let visual: Float
        public let laughter: Float
        public let sentenceCompleteness: Float
    }
    
    private let weights: ClipScoringWeights
    
    public init(weights: ClipScoringWeights) {
        self.weights = weights
    }
    
    public func scoreMoments(
        analysis: FootageAnalysis,
        sceneBoundaries: [ClipSceneDetector.SceneBoundary],
        transients: [TransientDetector.Transient]
    ) async -> [ScoredMoment] {
        var moments: [ScoredMoment] = []
        
        // Sample at regular intervals
        let sampleInterval: Double = 0.5
        var timestamp: Double = 0
        
        while timestamp < analysis.duration {
            let scores = computeScores(at: timestamp, analysis: analysis, transients: transients)
            let totalScore = computeWeightedScore(scores)
            let reasons = determineReasons(scores: scores)
            
            if totalScore > 0.3 {
                moments.append(ScoredMoment(
                    timestamp: timestamp,
                    score: totalScore,
                    reasons: reasons,
                    componentScores: scores
                ))
            }
            
            timestamp += sampleInterval
        }
        
        return moments.sorted { $0.score > $1.score }
    }
    
    private func computeScores(
        at timestamp: Double,
        analysis: FootageAnalysis,
        transients: [TransientDetector.Transient]
    ) -> ComponentScores {
        // Speech energy from transcript
        var speechEnergy: Float = 0
        if let transcript = analysis.transcript {
            for segment in transcript.segments {
                let segmentEnd = segment.startTime + segment.duration
                if timestamp >= segment.startTime && timestamp <= segmentEnd {
                    speechEnergy = segment.confidence
                    break
                }
            }
        }
        
        // Emotion score
        var emotionScore: Float = 0
        if let emotions = analysis.emotions {
            for emotion in emotions {
                let emotionEnd = emotion.timestamp + emotion.duration
                if timestamp >= emotion.timestamp && timestamp <= emotionEnd {
                    emotionScore = emotion.intensity
                    break
                }
            }
        }
        
        // Visual interest
        var visualScore: Float = 0
        if let visualFeatures = analysis.visualFeatures {
            if let feature = visualFeatures.first(where: { abs($0.timestamp - timestamp) < 0.5 }) {
                visualScore = (feature.motion + feature.complexity) / 2.0
            }
        }
        
        // Laughter detection (from transients and high-frequency content)
        var laughterScore: Float = 0
        let nearbyTransients = transients.filter { abs($0.timestamp - timestamp) < 1.0 }
        if nearbyTransients.contains(where: { $0.type == .laughter }) {
            laughterScore = 0.9
        }
        
        // Sentence completeness (prefer complete sentences)
        var completeness: Float = 0
        if let transcript = analysis.transcript {
            for segment in transcript.segments {
                let segmentEnd = segment.startTime + segment.duration
                if timestamp >= segment.startTime && timestamp <= segmentEnd {
                    // Higher score if we're near the end of a sentence
                    let positionInSegment = (timestamp - segment.startTime) / segment.duration
                    completeness = Float(positionInSegment)
                    break
                }
            }
        }
        
        return ComponentScores(
            speechEnergy: speechEnergy,
            emotion: emotionScore,
            visual: visualScore,
            laughter: laughterScore,
            sentenceCompleteness: completeness
        )
    }
    
    private func computeWeightedScore(_ scores: ComponentScores) -> Float {
        return scores.speechEnergy * weights.speechEnergy +
               scores.emotion * weights.emotion +
               scores.visual * weights.visual +
               scores.laughter * weights.laughter +
               scores.sentenceCompleteness * weights.sentenceCompleteness
    }
    
    private func determineReasons(scores: ComponentScores) -> [ClipReason] {
        var reasons: [ClipReason] = []
        
        if scores.speechEnergy > 0.7 { reasons.append(.highEnergy) }
        if scores.emotion > 0.7 { reasons.append(.emotionalPeak) }
        if scores.laughter > 0.5 { reasons.append(.laughter) }
        if scores.visual > 0.7 { reasons.append(.visualInterest) }
        if scores.sentenceCompleteness > 0.8 { reasons.append(.keyStatement) }
        
        return reasons
    }
}

// MARK: - ClipBuilder

/// Builds and optimizes clips from scored moments
public struct ClipBuilder: Sendable {
    
    public init() {}
    
    public func selectClips(
        from moments: [ClipRanker.ScoredMoment],
        targetDuration: Double,
        style: EditStyle
    ) -> [ProposedClip] {
        var clips: [ProposedClip] = []
        var remainingDuration = targetDuration
        var usedRanges: [ClosedRange<Double>] = []
        
        // Sort by score (descending)
        let sortedMoments = moments.sorted { $0.score > $1.score }
        
        for moment in sortedMoments {
            guard remainingDuration > AdvancedAIDefaults.minClipDuration else { break }
            
            // Calculate clip duration based on score
            let clipDuration = calculateClipDuration(score: moment.score)
            let halfDuration = clipDuration / 2
            
            let startTime = max(0, moment.timestamp - halfDuration)
            let endTime = moment.timestamp + halfDuration
            let range = startTime...endTime
            
            // Check for overlap with existing clips
            if !usedRanges.contains(where: { $0.overlaps(range) }) {
                let inPoint = CutPoint(timestamp: startTime, type: .silencePause, confidence: 0.8)
                let outPoint = CutPoint(timestamp: endTime, type: .silencePause, confidence: 0.8)
                
                let clip = ProposedClip(
                    timeRange: range,
                    score: moment.score,
                    rationale: moment.reasons,
                    cutPoints: CutPoints(inPoint: inPoint, outPoint: outPoint)
                )
                
                clips.append(clip)
                usedRanges.append(range)
                remainingDuration -= clipDuration
            }
        }
        
        // Sort by time for chronological order
        if style == .chronological {
            clips.sort { $0.timeRange.lowerBound < $1.timeRange.lowerBound }
        }
        
        return clips
    }
    
    public func optimizeFlow(clips: [ProposedClip], style: EditStyle) -> [ProposedClip] {
        guard clips.count > 1 else { return clips }
        
        var optimized = clips
        
        switch style {
        case .chronological:
            // Already sorted by time
            break
            
        case .energetic:
            // Alternate high and lower energy clips
            optimized.sort { $0.score > $1.score }
            var reordered: [ProposedClip] = []
            var high: [ProposedClip] = []
            var low: [ProposedClip] = []
            
            for clip in optimized {
                if clip.score > 0.6 {
                    high.append(clip)
                } else {
                    low.append(clip)
                }
            }
            
            while !high.isEmpty || !low.isEmpty {
                if let h = high.first {
                    reordered.append(h)
                    high.removeFirst()
                }
                if let l = low.first {
                    reordered.append(l)
                    low.removeFirst()
                }
            }
            optimized = reordered
            
        case .narrative:
            // Group by topic/speaker if possible
            // For now, use chronological with preference for complete statements
            optimized.sort { $0.timeRange.lowerBound < $1.timeRange.lowerBound }
            
        case .dramatic:
            // Build to climax - sort by score ascending
            optimized.sort { $0.score < $1.score }
        }
        
        return optimized
    }
    
    public func generateTransitions(for clips: [ProposedClip], style: EditStyle) -> [ClipTransition] {
        guard clips.count > 1 else { return [] }
        
        var transitions: [ClipTransition] = []
        
        for i in 0..<(clips.count - 1) {
            let fromClip = clips[i]
            let toClip = clips[i + 1]
            
            let transitionType: ClipTransitionType
            let duration: Double
            
            switch style {
            case .energetic:
                transitionType = .cut
                duration = 0
                
            case .chronological, .narrative:
                // Use dissolves for time jumps
                let timeGap = toClip.timeRange.lowerBound - fromClip.timeRange.upperBound
                if timeGap > 5.0 {
                    transitionType = .crossDissolve
                    duration = 0.5
                } else {
                    transitionType = .cut
                    duration = 0
                }
                
            case .dramatic:
                transitionType = .dip
                duration = 0.75
            }
            
            transitions.append(ClipTransition(
                type: transitionType,
                duration: duration,
                fromClipId: fromClip.id,
                toClipId: toClip.id
            ))
        }
        
        return transitions
    }
    
    private func calculateClipDuration(score: Float) -> Double {
        // Higher scores get longer clips
        let minDuration = AdvancedAIDefaults.minClipDuration
        let maxDuration = AdvancedAIDefaults.maxClipDuration
        let range = maxDuration - minDuration
        
        return minDuration + Double(score) * range * 0.5
    }
}
