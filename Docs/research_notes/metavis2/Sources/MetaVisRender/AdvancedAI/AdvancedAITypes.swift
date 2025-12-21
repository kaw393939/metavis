// AdvancedAITypes.swift
// MetaVisRender
//
// Core types for Advanced AI features: Auto-Clip, Multi-Cam Sync, Source Separation, Live Ingestion
// Sprint 08

import Foundation
import AVFoundation

// MARK: - Constants

/// Default values for Advanced AI processing
public enum AdvancedAIDefaults {
    // Auto-clip
    public static let minClipDuration: Double = 3.0
    public static let maxClipDuration: Double = 30.0
    public static let targetHighlightDuration: Double = 60.0
    public static let defaultClipOverlap: Double = 0.5
    
    // Multi-cam
    public static let syncSearchRange: Double = 60.0
    public static let syncRefinementWindow: Double = 1.0
    public static let minSyncConfidence: Float = 0.8
    public static let chromagramBins: Int = 12
    public static let fingerprintHopSize: Int = 512
    
    // Source separation
    public static let stemChunkDuration: Double = 10.0
    public static let stemOverlapDuration: Double = 0.5
    public static let stemSampleRate: Double = 44100.0
    
    // Live ingestion
    public static let liveSegmentDuration: Double = 0.5
    public static let liveBufferSize: Int = 4096
}

// MARK: - Auto-Clip Types

/// Reason why a clip was selected
public enum ClipReason: String, Codable, Sendable, CaseIterable {
    case highEnergy = "high_energy"
    case emotionalPeak = "emotional_peak"
    case laughter = "laughter"
    case keyStatement = "key_statement"
    case visualInterest = "visual_interest"
    case reactionShot = "reaction_shot"
    case applause = "applause"
    case musicDrop = "music_drop"
}

/// Type of cut point for clip boundaries
public enum CutPointType: String, Codable, Sendable {
    case sentenceBoundary = "sentence_boundary"
    case silencePause = "silence_pause"
    case sceneChange = "scene_change"
    case beatDrop = "beat_drop"
    case speakerChange = "speaker_change"
}

/// A precise cut point with timing and type
public struct CutPoint: Codable, Sendable, Hashable {
    public let timestamp: Double
    public let type: CutPointType
    public let confidence: Float
    
    public init(timestamp: Double, type: CutPointType, confidence: Float = 1.0) {
        self.timestamp = timestamp
        self.type = type
        self.confidence = confidence
    }
}

/// In and out points for a clip
public struct CutPoints: Codable, Sendable, Hashable {
    public let inPoint: CutPoint
    public let outPoint: CutPoint
    
    public init(inPoint: CutPoint, outPoint: CutPoint) {
        self.inPoint = inPoint
        self.outPoint = outPoint
    }
    
    public var duration: Double {
        outPoint.timestamp - inPoint.timestamp
    }
}

/// An AI-suggested clip with scoring and rationale
public struct ProposedClip: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let timeRange: ClosedRange<Double>
    public let score: Float
    public let rationale: [ClipReason]
    public let cutPoints: CutPoints
    public let sourceClipId: UUID?
    
    public init(
        id: UUID = UUID(),
        timeRange: ClosedRange<Double>,
        score: Float,
        rationale: [ClipReason],
        cutPoints: CutPoints,
        sourceClipId: UUID? = nil
    ) {
        self.id = id
        self.timeRange = timeRange
        self.score = score
        self.rationale = rationale
        self.cutPoints = cutPoints
        self.sourceClipId = sourceClipId
    }
    
    public var duration: Double {
        timeRange.upperBound - timeRange.lowerBound
    }
}

/// Editing style for highlight reels
public enum EditStyle: String, Codable, Sendable {
    case chronological = "chronological"
    case energetic = "energetic"
    case narrative = "narrative"
    case dramatic = "dramatic"
}

/// Transition type between clips
public enum ClipTransitionType: String, Codable, Sendable {
    case cut = "cut"
    case crossDissolve = "cross_dissolve"
    case dip = "dip"
    case wipe = "wipe"
    case fade = "fade"
}

/// A transition between two clips
public struct ClipTransition: Codable, Sendable, Hashable {
    public let type: ClipTransitionType
    public let duration: Double
    public let fromClipId: UUID
    public let toClipId: UUID
    
    public init(type: ClipTransitionType, duration: Double, fromClipId: UUID, toClipId: UUID) {
        self.type = type
        self.duration = duration
        self.fromClipId = fromClipId
        self.toClipId = toClipId
    }
}

/// A complete highlight compilation
public struct HighlightReel: Codable, Sendable {
    public let id: UUID
    public let clips: [ProposedClip]
    public let totalDuration: Double
    public let style: EditStyle
    public let transitions: [ClipTransition]
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        clips: [ProposedClip],
        totalDuration: Double,
        style: EditStyle,
        transitions: [ClipTransition],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clips = clips
        self.totalDuration = totalDuration
        self.style = style
        self.transitions = transitions
        self.createdAt = createdAt
    }
}

/// Scoring weights for clip importance
public struct ClipScoringWeights: Codable, Sendable {
    public let speechEnergy: Float
    public let emotion: Float
    public let visual: Float
    public let laughter: Float
    public let sentenceCompleteness: Float
    
    public init(
        speechEnergy: Float = 0.20,
        emotion: Float = 0.25,
        visual: Float = 0.15,
        laughter: Float = 0.20,
        sentenceCompleteness: Float = 0.20
    ) {
        self.speechEnergy = speechEnergy
        self.emotion = emotion
        self.visual = visual
        self.laughter = laughter
        self.sentenceCompleteness = sentenceCompleteness
    }
    
    public static let `default` = ClipScoringWeights()
    
    public static let energetic = ClipScoringWeights(
        speechEnergy: 0.30,
        emotion: 0.20,
        visual: 0.25,
        laughter: 0.15,
        sentenceCompleteness: 0.10
    )
    
    public static let narrative = ClipScoringWeights(
        speechEnergy: 0.15,
        emotion: 0.25,
        visual: 0.10,
        laughter: 0.15,
        sentenceCompleteness: 0.35
    )
}

// MARK: - Multi-Camera Types

/// Method used for synchronization
public enum AlignmentMethod: String, Codable, Sendable {
    case audioFingerprint = "audio_fingerprint"
    case chromagram = "chromagram"
    case waveform = "waveform"
    case visualMotion = "visual_motion"
    case timecode = "timecode"
}

/// An aligned clip with offset information
public struct AlignedClip: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let clipId: UUID
    public let sourceURL: URL
    public let offset: Double          // Seconds relative to reference
    public let confidence: Float
    public let drift: Double?          // Drift over time (if detected)
    public let sampleRateDrift: Double? // Sample rate difference
    
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        sourceURL: URL,
        offset: Double,
        confidence: Float,
        drift: Double? = nil,
        sampleRateDrift: Double? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.sourceURL = sourceURL
        self.offset = offset
        self.confidence = confidence
        self.drift = drift
        self.sampleRateDrift = sampleRateDrift
    }
}

/// Cross-clip alignment result for multi-cam
public struct MultiCamAlignment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let referenceClipId: UUID
    public let alignedClips: [AlignedClip]
    public let confidence: Float
    public let method: AlignmentMethod
    public let analysisTime: Double
    
    public init(
        id: UUID = UUID(),
        referenceClipId: UUID,
        alignedClips: [AlignedClip],
        confidence: Float,
        method: AlignmentMethod,
        analysisTime: Double = 0
    ) {
        self.id = id
        self.referenceClipId = referenceClipId
        self.alignedClips = alignedClips
        self.confidence = confidence
        self.method = method
        self.analysisTime = analysisTime
    }
}

/// Reason for suggesting a camera cut
public enum CutSuggestionReason: String, Codable, Sendable {
    case speakerChange = "speaker_change"
    case reactionShot = "reaction_shot"
    case wideToClose = "wide_to_close"
    case closeToWide = "close_to_wide"
    case eyeContact = "eye_contact"
    case gesture = "gesture"
    case emphasis = "emphasis"
}

/// Suggested cut between cameras
public struct CutSuggestion: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Double
    public let fromClipId: UUID
    public let toClipId: UUID
    public let reason: CutSuggestionReason
    public let confidence: Float
    
    public init(
        id: UUID = UUID(),
        timestamp: Double,
        fromClipId: UUID,
        toClipId: UUID,
        reason: CutSuggestionReason,
        confidence: Float
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fromClipId = fromClipId
        self.toClipId = toClipId
        self.reason = reason
        self.confidence = confidence
    }
}

/// Audio fingerprint for synchronization
public struct AudioFingerprint: Sendable {
    public let chromagram: [[Float]]      // [time][chroma bins]
    public let rmsEnergy: [Float]         // RMS energy per frame
    public let zeroCrossings: [Float]     // Zero crossing rate per frame
    public let spectralCentroid: [Float]  // Spectral centroid per frame
    public let hopSize: Int
    public let sampleRate: Double
    
    public init(
        chromagram: [[Float]],
        rmsEnergy: [Float],
        zeroCrossings: [Float],
        spectralCentroid: [Float],
        hopSize: Int,
        sampleRate: Double
    ) {
        self.chromagram = chromagram
        self.rmsEnergy = rmsEnergy
        self.zeroCrossings = zeroCrossings
        self.spectralCentroid = spectralCentroid
        self.hopSize = hopSize
        self.sampleRate = sampleRate
    }
    
    public var frameCount: Int {
        chromagram.count
    }
    
    public var duration: Double {
        Double(frameCount * hopSize) / sampleRate
    }
}

// MARK: - Source Separation Types

/// Stem type for source separation
public enum StemType: String, Codable, Sendable, CaseIterable {
    case dialog = "dialog"       // Mapped from vocals
    case music = "music"         // Mapped from drums + bass + some other
    case ambience = "ambience"   // Environmental sounds
    case other = "other"         // Everything else
    
    // Demucs native stems
    case vocals = "vocals"
    case drums = "drums"
    case bass = "bass"
}

/// Metadata about stem separation processing
public struct StemMetadata: Codable, Sendable {
    public let modelVersion: String
    public let processingTime: Double
    public let qualityScore: Float
    public let sampleRate: Double
    public let bitDepth: Int
    
    public init(
        modelVersion: String,
        processingTime: Double,
        qualityScore: Float,
        sampleRate: Double = 44100,
        bitDepth: Int = 16
    ) {
        self.modelVersion = modelVersion
        self.processingTime = processingTime
        self.qualityScore = qualityScore
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }
}

/// Separated audio stems result
public struct SeparatedStems: Sendable {
    public let dialog: URL
    public let music: URL
    public let ambience: URL
    public let other: URL
    public let metadata: StemMetadata
    
    public init(
        dialog: URL,
        music: URL,
        ambience: URL,
        other: URL,
        metadata: StemMetadata
    ) {
        self.dialog = dialog
        self.music = music
        self.ambience = ambience
        self.other = other
        self.metadata = metadata
    }
    
    public var allURLs: [StemType: URL] {
        [
            .dialog: dialog,
            .music: music,
            .ambience: ambience,
            .other: other
        ]
    }
}

/// Raw Demucs output stems
public struct DemucsStems: Sendable {
    public let vocals: URL
    public let drums: URL
    public let bass: URL
    public let other: URL
    public let metadata: StemMetadata
    
    public init(
        vocals: URL,
        drums: URL,
        bass: URL,
        other: URL,
        metadata: StemMetadata
    ) {
        self.vocals = vocals
        self.drums = drums
        self.bass = bass
        self.other = other
        self.metadata = metadata
    }
}

/// Configuration for source separation
public struct SeparationConfig: Codable, Sendable {
    public let chunkDuration: Double
    public let overlapDuration: Double
    public let outputSampleRate: Double
    public let outputBitDepth: Int
    public let stemTypes: [StemType]
    
    public init(
        chunkDuration: Double = AdvancedAIDefaults.stemChunkDuration,
        overlapDuration: Double = AdvancedAIDefaults.stemOverlapDuration,
        outputSampleRate: Double = AdvancedAIDefaults.stemSampleRate,
        outputBitDepth: Int = 16,
        stemTypes: [StemType] = [.dialog, .music, .ambience, .other]
    ) {
        self.chunkDuration = chunkDuration
        self.overlapDuration = overlapDuration
        self.outputSampleRate = outputSampleRate
        self.outputBitDepth = outputBitDepth
        self.stemTypes = stemTypes
    }
    
    public static let `default` = SeparationConfig()
    
    public static let highQuality = SeparationConfig(
        chunkDuration: 30.0,
        overlapDuration: 1.0,
        outputSampleRate: 48000,
        outputBitDepth: 24
    )
}

// MARK: - Live Ingestion Types

/// Real-time transcript segment
public struct LiveTranscript: Sendable, Codable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Float
    public let language: String?
    
    public init(
        text: String,
        isFinal: Bool,
        confidence: Float,
        language: String? = nil
    ) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
        self.language = language
    }
}

/// A face observation during live capture
public struct LiveFaceObservation: Sendable, Codable {
    public let trackingId: Int
    public let boundingBox: CGRect
    public let confidence: Float
    public let landmarks: [String: CGPoint]?
    
    public init(
        trackingId: Int,
        boundingBox: CGRect,
        confidence: Float,
        landmarks: [String: CGPoint]? = nil
    ) {
        self.trackingId = trackingId
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.landmarks = landmarks
    }
}

/// Emotion state during live capture
public struct LiveEmotion: Sendable, Codable {
    public let dominant: String
    public let confidence: Float
    public let valence: Float    // -1 to 1 (negative to positive)
    public let arousal: Float    // 0 to 1 (calm to excited)
    
    public init(
        dominant: String,
        confidence: Float,
        valence: Float,
        arousal: Float
    ) {
        self.dominant = dominant
        self.confidence = confidence
        self.valence = valence
        self.arousal = arousal
    }
}

/// A real-time analysis segment
public struct LiveSegment: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Double
    public let duration: Double
    public let transcript: LiveTranscript?
    public let faces: [LiveFaceObservation]
    public let activeSpeakerId: Int?
    public let emotion: LiveEmotion?
    public let audioLevel: Float
    public let isHighlight: Bool
    
    public init(
        id: UUID = UUID(),
        timestamp: Double,
        duration: Double,
        transcript: LiveTranscript? = nil,
        faces: [LiveFaceObservation] = [],
        activeSpeakerId: Int? = nil,
        emotion: LiveEmotion? = nil,
        audioLevel: Float = 0,
        isHighlight: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.duration = duration
        self.transcript = transcript
        self.faces = faces
        self.activeSpeakerId = activeSpeakerId
        self.emotion = emotion
        self.audioLevel = audioLevel
        self.isHighlight = isHighlight
    }
}

/// Status of a live ingestion session
public enum LiveSessionStatus: String, Codable, Sendable {
    case idle = "idle"
    case starting = "starting"
    case running = "running"
    case paused = "paused"
    case stopping = "stopping"
    case stopped = "stopped"
    case error = "error"
}

/// Statistics for a live session
public struct LiveSessionStats: Sendable {
    public let duration: Double
    public let segmentCount: Int
    public let faceDetections: Int
    public let transcriptWords: Int
    public let highlightCount: Int
    public let droppedFrames: Int
    
    public init(
        duration: Double,
        segmentCount: Int,
        faceDetections: Int,
        transcriptWords: Int,
        highlightCount: Int,
        droppedFrames: Int
    ) {
        self.duration = duration
        self.segmentCount = segmentCount
        self.faceDetections = faceDetections
        self.transcriptWords = transcriptWords
        self.highlightCount = highlightCount
        self.droppedFrames = droppedFrames
    }
    
    public static let empty = LiveSessionStats(
        duration: 0,
        segmentCount: 0,
        faceDetections: 0,
        transcriptWords: 0,
        highlightCount: 0,
        droppedFrames: 0
    )
}

// MARK: - AI Orchestration Types

/// GPU memory budget for model loading
public struct GPUMemoryBudget: Sendable {
    public let totalBytes: Int
    public let usedBytes: Int
    public let maxModels: Int
    
    public init(totalBytes: Int = 4 * 1024 * 1024 * 1024, usedBytes: Int = 0, maxModels: Int = 3) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.maxModels = maxModels
    }
    
    public var availableBytes: Int {
        totalBytes - usedBytes
    }
    
    public var utilizationPercent: Float {
        Float(usedBytes) / Float(totalBytes) * 100
    }
}

/// Model priority for LRU eviction
public enum ModelPriority: Int, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
    
    public static func < (lhs: ModelPriority, rhs: ModelPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A loaded ML model in the cache
public struct LoadedModel: Sendable {
    public let name: String
    public let memoryBytes: Int
    public let priority: ModelPriority
    public let loadedAt: Date
    public let lastUsed: Date
    
    public init(
        name: String,
        memoryBytes: Int,
        priority: ModelPriority,
        loadedAt: Date = Date(),
        lastUsed: Date = Date()
    ) {
        self.name = name
        self.memoryBytes = memoryBytes
        self.priority = priority
        self.loadedAt = loadedAt
        self.lastUsed = lastUsed
    }
}

// MARK: - Error Types

/// Errors from Advanced AI operations
public enum AdvancedAIError: Error, LocalizedError {
    case clipGenerationFailed(String)
    case insufficientContent(String)
    case syncFailed(String)
    case lowSyncConfidence(Float)
    case separationFailed(String)
    case modelNotLoaded(String)
    case gpuMemoryExceeded(Int, Int)
    case liveSessionError(String)
    case invalidInput(String)
    case processingTimeout
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .clipGenerationFailed(let reason):
            return "Clip generation failed: \(reason)"
        case .insufficientContent(let reason):
            return "Insufficient content: \(reason)"
        case .syncFailed(let reason):
            return "Synchronization failed: \(reason)"
        case .lowSyncConfidence(let confidence):
            return "Sync confidence too low: \(String(format: "%.2f", confidence))"
        case .separationFailed(let reason):
            return "Source separation failed: \(reason)"
        case .modelNotLoaded(let name):
            return "Model not loaded: \(name)"
        case .gpuMemoryExceeded(let required, let available):
            return "GPU memory exceeded: required \(required) bytes, available \(available) bytes"
        case .liveSessionError(let reason):
            return "Live session error: \(reason)"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .processingTimeout:
            return "Processing timed out"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

// MARK: - Progress Reporting

/// Progress callback for long-running operations
public typealias AdvancedAIProgress = @Sendable (Float, String) -> Void

/// Progress stages for clip generation
public enum ClipGenerationStage: String, Sendable {
    case analyzing = "Analyzing content"
    case detectingScenes = "Detecting scenes"
    case scoringMoments = "Scoring moments"
    case selectingClips = "Selecting clips"
    case optimizingFlow = "Optimizing flow"
    case complete = "Complete"
}

/// Progress stages for source separation
public enum SeparationStage: String, Sendable {
    case loading = "Loading model"
    case preprocessing = "Preprocessing audio"
    case separating = "Separating stems"
    case postprocessing = "Post-processing"
    case exporting = "Exporting stems"
    case complete = "Complete"
}
