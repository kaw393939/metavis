// PersonIntelligenceTypes.swift
// MetaVisRender
//
// Created for Sprint 06: Person Intelligence
// Core data types for person understanding

import Foundation
import CoreGraphics

// MARK: - Person Identity

/// A unique person identity detected across frames and clips
public struct PersonIdentity: Codable, Sendable, Hashable, Identifiable {
    /// Unique identifier for this person
    public let id: UUID
    
    /// Stable human-readable label (PERSON_00, PERSON_01, etc.)
    public let label: String
    
    /// Optional user-assigned name
    public var name: String?
    
    /// Representative face embedding (average of all observations)
    public let representativeEmbedding: [Float]?
    
    /// Confidence in this identity cluster (0-1)
    public let confidence: Float
    
    /// Source observations that make up this identity
    public let observationCount: Int
    
    /// Time range where this person appears
    public let firstAppearance: Double
    public let lastAppearance: Double
    
    /// Associated voice speaker ID (if linked)
    public var linkedSpeakerId: String?
    
    public init(
        id: UUID = UUID(),
        label: String,
        name: String? = nil,
        representativeEmbedding: [Float]? = nil,
        confidence: Float = 1.0,
        observationCount: Int = 1,
        firstAppearance: Double = 0,
        lastAppearance: Double = 0,
        linkedSpeakerId: String? = nil
    ) {
        self.id = id
        self.label = label
        self.name = name
        self.representativeEmbedding = representativeEmbedding
        self.confidence = confidence
        self.observationCount = observationCount
        self.firstAppearance = firstAppearance
        self.lastAppearance = lastAppearance
        self.linkedSpeakerId = linkedSpeakerId
    }
    
    /// Display name (user-assigned or label)
    public var displayName: String {
        name ?? label
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: PersonIdentity, rhs: PersonIdentity) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Face Embedding

/// A face observation with its identity embedding
public struct FaceEmbeddingObservation: Codable, Sendable {
    /// Original face observation data
    public let bounds: CGRect
    public let confidence: Float
    public let roll: Float?
    public let yaw: Float?
    public let pitch: Float?
    
    /// Timestamp in the video
    public let timestamp: Double
    
    /// 512-dimensional identity embedding
    public let embedding: [Float]
    
    /// Assigned person identity (after clustering)
    public var personId: UUID?
    
    public init(
        bounds: CGRect,
        confidence: Float,
        roll: Float? = nil,
        yaw: Float? = nil,
        pitch: Float? = nil,
        timestamp: Double,
        embedding: [Float],
        personId: UUID? = nil
    ) {
        self.bounds = bounds
        self.confidence = confidence
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
        self.timestamp = timestamp
        self.embedding = embedding
        self.personId = personId
    }
}

// MARK: - Emotion Types

/// Primary emotion categories
public enum EmotionCategory: String, Codable, CaseIterable, Sendable {
    case neutral
    case happy
    case sad
    case angry
    case fearful
    case disgusted
    case surprised
    case contempt
    
    /// Valence value (-1 to +1, negative to positive)
    public var typicalValence: Float {
        switch self {
        case .neutral: return 0.0
        case .happy: return 0.8
        case .sad: return -0.7
        case .angry: return -0.6
        case .fearful: return -0.8
        case .disgusted: return -0.5
        case .surprised: return 0.3  // Can be positive or negative
        case .contempt: return -0.4
        }
    }
    
    /// Arousal value (0 to 1, calm to excited)
    public var typicalArousal: Float {
        switch self {
        case .neutral: return 0.2
        case .happy: return 0.6
        case .sad: return 0.3
        case .angry: return 0.9
        case .fearful: return 0.8
        case .disgusted: return 0.5
        case .surprised: return 0.9
        case .contempt: return 0.3
        }
    }
}

/// Face-based emotion detection result
public struct FaceEmotion: Codable, Sendable {
    /// Primary detected emotion
    public let category: EmotionCategory
    
    /// Confidence in detection (0-1)
    public let confidence: Float
    
    /// All emotion probabilities
    public let probabilities: [EmotionCategory: Float]
    
    /// Valence (-1 to +1)
    public let valence: Float
    
    /// Arousal (0 to 1)
    public let arousal: Float
    
    /// Face landmarks data (for expression analysis)
    public let mouthOpenness: Float?
    public let eyeOpenness: Float?
    public let browRaise: Float?
    public let smileIntensity: Float?
    
    public init(
        category: EmotionCategory,
        confidence: Float,
        probabilities: [EmotionCategory: Float] = [:],
        valence: Float = 0,
        arousal: Float = 0.2,
        mouthOpenness: Float? = nil,
        eyeOpenness: Float? = nil,
        browRaise: Float? = nil,
        smileIntensity: Float? = nil
    ) {
        self.category = category
        self.confidence = confidence
        self.probabilities = probabilities
        self.valence = valence
        self.arousal = arousal
        self.mouthOpenness = mouthOpenness
        self.eyeOpenness = eyeOpenness
        self.browRaise = browRaise
        self.smileIntensity = smileIntensity
    }
}

/// Voice-based emotion detection result
public struct VoiceEmotion: Codable, Sendable {
    /// Primary detected emotion
    public let category: EmotionCategory
    
    /// Confidence in detection (0-1)
    public let confidence: Float
    
    /// Valence (-1 to +1)
    public let valence: Float
    
    /// Arousal (0 to 1)
    public let arousal: Float
    
    /// Prosodic features
    public let pitchMean: Float
    public let pitchVariation: Float
    public let energy: Float
    public let speechRate: Float
    
    public init(
        category: EmotionCategory,
        confidence: Float,
        valence: Float = 0,
        arousal: Float = 0.2,
        pitchMean: Float = 0,
        pitchVariation: Float = 0,
        energy: Float = 0,
        speechRate: Float = 0
    ) {
        self.category = category
        self.confidence = confidence
        self.valence = valence
        self.arousal = arousal
        self.pitchMean = pitchMean
        self.pitchVariation = pitchVariation
        self.energy = energy
        self.speechRate = speechRate
    }
}

/// Fused emotion from face + voice
public struct FusedEmotion: Codable, Sendable {
    /// Primary emotion (weighted fusion)
    public let category: EmotionCategory
    
    /// Overall confidence
    public let confidence: Float
    
    /// Valence (-1 to +1)
    public let valence: Float
    
    /// Arousal (0 to 1)
    public let arousal: Float
    
    /// Face component (if available)
    public let faceEmotion: FaceEmotion?
    
    /// Voice component (if available)
    public let voiceEmotion: VoiceEmotion?
    
    /// Weight given to face vs voice (0 = all voice, 1 = all face)
    public let faceWeight: Float
    
    public init(
        category: EmotionCategory,
        confidence: Float,
        valence: Float,
        arousal: Float,
        faceEmotion: FaceEmotion? = nil,
        voiceEmotion: VoiceEmotion? = nil,
        faceWeight: Float = 0.5
    ) {
        self.category = category
        self.confidence = confidence
        self.valence = valence
        self.arousal = arousal
        self.faceEmotion = faceEmotion
        self.voiceEmotion = voiceEmotion
        self.faceWeight = faceWeight
    }
}

// MARK: - Emotion Timeline

/// A single emotion sample at a point in time
public struct EmotionSample: Codable, Sendable {
    /// Timestamp in seconds
    public let timestamp: Double
    
    /// Person this emotion belongs to
    public let personId: UUID?
    
    /// Fused emotion at this time
    public let emotion: FusedEmotion
    
    public init(timestamp: Double, personId: UUID? = nil, emotion: FusedEmotion) {
        self.timestamp = timestamp
        self.personId = personId
        self.emotion = emotion
    }
}

/// A significant emotional moment
public struct EmotionPeak: Codable, Sendable {
    /// Time of the peak
    public let timestamp: Double
    
    /// Duration of the emotional moment
    public let duration: Double
    
    /// Person experiencing this emotion
    public let personId: UUID?
    
    /// The peak emotion
    public let emotion: EmotionCategory
    
    /// Intensity (based on arousal/valence magnitude)
    public let intensity: Float
    
    /// Description for UI/agents
    public var description: String {
        let personDesc = personId.map { "Person \($0.uuidString.prefix(4))" } ?? "Unknown"
        return "\(personDesc) shows \(emotion.rawValue) at \(String(format: "%.1f", timestamp))s"
    }
    
    public init(
        timestamp: Double,
        duration: Double = 1.0,
        personId: UUID? = nil,
        emotion: EmotionCategory,
        intensity: Float
    ) {
        self.timestamp = timestamp
        self.duration = duration
        self.personId = personId
        self.emotion = emotion
        self.intensity = intensity
    }
}

/// Complete emotion timeline for a clip
public struct EmotionTimeline: Codable, Sendable {
    /// Per-second emotion samples
    public let samples: [EmotionSample]
    
    /// Detected emotional peaks
    public let peaks: [EmotionPeak]
    
    /// Overall average valence (-1 to +1)
    public let averageValence: Float
    
    /// Overall average arousal (0 to 1)
    public let averageArousal: Float
    
    /// Dominant emotion across the clip
    public let dominantEmotion: EmotionCategory
    
    public init(
        samples: [EmotionSample],
        peaks: [EmotionPeak],
        averageValence: Float = 0,
        averageArousal: Float = 0.2,
        dominantEmotion: EmotionCategory = .neutral
    ) {
        self.samples = samples
        self.peaks = peaks
        self.averageValence = averageValence
        self.averageArousal = averageArousal
        self.dominantEmotion = dominantEmotion
    }
    
    /// Get emotion at a specific time
    public func emotion(at time: Double) -> FusedEmotion? {
        // Find nearest sample
        guard !samples.isEmpty else { return nil }
        
        let nearest = samples.min { abs($0.timestamp - time) < abs($1.timestamp - time) }
        return nearest?.emotion
    }
    
    /// Get peaks within a time range
    public func peaks(in range: ClosedRange<Double>) -> [EmotionPeak] {
        peaks.filter { range.contains($0.timestamp) }
    }
}

// MARK: - Cross-Clip Matching

/// Result of matching identities across multiple clips
public struct PersonTrackingResult: Codable, Sendable {
    /// Global identities unified across all clips
    public let globalIdentities: [PersonIdentity]
    
    /// Mapping from clip-local to global identity
    /// Key: clip UUID, Value: [local label : global UUID]
    public let clipMappings: [UUID: [String: UUID]]
    
    /// Confidence in the overall matching
    public let matchingConfidence: Float
    
    public init(
        globalIdentities: [PersonIdentity],
        clipMappings: [UUID: [String: UUID]],
        matchingConfidence: Float = 1.0
    ) {
        self.globalIdentities = globalIdentities
        self.clipMappings = clipMappings
        self.matchingConfidence = matchingConfidence
    }
    
    /// Get global identity for a local label in a clip
    public func globalIdentity(forLocal label: String, in clipId: UUID) -> PersonIdentity? {
        guard let mapping = clipMappings[clipId],
              let globalId = mapping[label] else {
            return nil
        }
        return globalIdentities.first { $0.id == globalId }
    }
}

// MARK: - Person Intelligence Result

/// Complete person intelligence analysis result
public struct PersonIntelligenceResult: Codable, Sendable {
    /// Detected person identities
    public let identities: [PersonIdentity]
    
    /// Face embedding observations
    public let embeddings: [FaceEmbeddingObservation]
    
    /// Emotion timeline
    public let emotionTimeline: EmotionTimeline?
    
    /// Processing metadata
    public let processingTime: Double
    public let frameCount: Int
    public let faceCount: Int
    
    public init(
        identities: [PersonIdentity],
        embeddings: [FaceEmbeddingObservation],
        emotionTimeline: EmotionTimeline? = nil,
        processingTime: Double = 0,
        frameCount: Int = 0,
        faceCount: Int = 0
    ) {
        self.identities = identities
        self.embeddings = embeddings
        self.emotionTimeline = emotionTimeline
        self.processingTime = processingTime
        self.frameCount = frameCount
        self.faceCount = faceCount
    }
}
