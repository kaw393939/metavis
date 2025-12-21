// Sources/MetaVisRender/Ingestion/Audio/TranscriptTypes.swift
// Sprint 03: Data models for transcription results

import Foundation

// MARK: - Transcript

/// Complete transcription result
public struct Transcript: Codable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let language: String
    public let segments: [TranscriptSegment]
    public let words: [TranscriptWord]
    public let confidence: Float
    public let engine: TranscriptionEngine.EngineType
    public let duration: Double
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        text: String,
        language: String,
        segments: [TranscriptSegment],
        words: [TranscriptWord] = [],
        confidence: Float,
        engine: TranscriptionEngine.EngineType,
        duration: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.language = language
        self.segments = segments
        self.words = words
        self.confidence = confidence
        self.engine = engine
        self.duration = duration
        self.createdAt = createdAt
    }
    
    // MARK: Computed Properties
    
    public var wordCount: Int { words.isEmpty ? text.split(separator: " ").count : words.count }
    public var segmentCount: Int { segments.count }
    public var hasWordTiming: Bool { !words.isEmpty }
    public var hasSpeakerLabels: Bool { segments.contains { $0.speakerId != nil } }
    
    public var speakerIds: Set<String> {
        Set(segments.compactMap { $0.speakerId })
    }
    
    public var averageConfidence: Float {
        guard !segments.isEmpty else { return confidence }
        return segments.map { $0.confidence }.reduce(0, +) / Float(segments.count)
    }
    
    /// Get segments for a specific speaker
    public func segments(for speakerId: String) -> [TranscriptSegment] {
        segments.filter { $0.speakerId == speakerId }
    }
    
    /// Get text for a time range
    public func text(from start: Double, to end: Double) -> String {
        if hasWordTiming {
            return words
                .filter { $0.start >= start && $0.end <= end }
                .map { $0.word }
                .joined(separator: " ")
        } else {
            return segments
                .filter { $0.start >= start && $0.end <= end }
                .map { $0.text }
                .joined(separator: " ")
        }
    }
}

// MARK: - Transcript Segment

/// A sentence or phrase segment with timing
public struct TranscriptSegment: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let text: String
    public let confidence: Float
    public let speakerId: String?
    
    public init(
        id: Int,
        start: Double,
        end: Double,
        text: String,
        confidence: Float,
        speakerId: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.confidence = confidence
        self.speakerId = speakerId
    }
    
    public var duration: Double { end - start }
    
    public var wordCount: Int {
        text.split(separator: " ").count
    }
    
    public var wordsPerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(wordCount) / duration
    }
}

// MARK: - Transcript Word

/// Individual word with precise timing
public struct TranscriptWord: Codable, Sendable, Equatable {
    public let word: String
    public let start: Double
    public let end: Double
    public let confidence: Float
    public let speakerId: String?
    
    public init(
        word: String,
        start: Double,
        end: Double,
        confidence: Float,
        speakerId: String? = nil
    ) {
        self.word = word
        self.start = start
        self.end = end
        self.confidence = confidence
        self.speakerId = speakerId
    }
    
    public var duration: Double { end - start }
}

// MARK: - Speaker Segment

/// A contiguous speaking segment for one speaker
public struct SpeakerSegment: Codable, Sendable, Equatable {
    public let speakerId: String
    public let start: Double
    public let end: Double
    public let confidence: Float
    
    public init(
        speakerId: String,
        start: Double,
        end: Double,
        confidence: Float
    ) {
        self.speakerId = speakerId
        self.start = start
        self.end = end
        self.confidence = confidence
    }
    
    public var duration: Double { end - start }
}

// MARK: - Speaker

/// Identified speaker with metadata
public struct Speaker: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var label: String?
    public let embedding: [Float]?
    public let totalSpeakingTime: Double
    public let segmentCount: Int
    
    public init(
        id: String,
        label: String? = nil,
        embedding: [Float]? = nil,
        totalSpeakingTime: Double = 0,
        segmentCount: Int = 0
    ) {
        self.id = id
        self.label = label
        self.embedding = embedding
        self.totalSpeakingTime = totalSpeakingTime
        self.segmentCount = segmentCount
    }
    
    public var displayName: String {
        label ?? id
    }
}

// MARK: - Diarization Result

/// Speaker diarization output
public struct DiarizationResult: Codable, Sendable {
    public let speakers: [Speaker]
    public let segments: [SpeakerSegment]
    public let speakerCount: Int
    
    public init(
        speakers: [Speaker],
        segments: [SpeakerSegment]
    ) {
        self.speakers = speakers
        self.segments = segments
        self.speakerCount = speakers.count
    }
    
    /// Get segments for a specific speaker
    public func segments(for speakerId: String) -> [SpeakerSegment] {
        segments.filter { $0.speakerId == speakerId }
    }
    
    /// Get speaker at a specific time
    public func speaker(at time: Double) -> Speaker? {
        guard let segment = segments.first(where: { time >= $0.start && time <= $0.end }) else {
            return nil
        }
        return speakers.first { $0.id == segment.speakerId }
    }
}

// MARK: - Speech Activity

/// Voice Activity Detection segment
public struct SpeechActivity: Codable, Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let type: ActivityType
    public let confidence: Float
    
    public enum ActivityType: String, Codable, Sendable {
        case speech
        case silence
        case music
        case noise
        case unknown
    }
    
    public init(
        start: Double,
        end: Double,
        type: ActivityType,
        confidence: Float = 1.0
    ) {
        self.start = start
        self.end = end
        self.type = type
        self.confidence = confidence
    }
    
    public var duration: Double { end - start }
    public var isSpeech: Bool { type == .speech }
}

// MARK: - Speech Detection Result

/// Result of Voice Activity Detection
public struct SpeechDetectionResult: Codable, Sendable {
    public let segments: [SpeechActivity]
    public let totalSpeechDuration: Double
    public let totalSilenceDuration: Double
    public let totalMusicDuration: Double
    public let speechRatio: Float
    
    public init(segments: [SpeechActivity]) {
        self.segments = segments
        
        var speech: Double = 0
        var silence: Double = 0
        var music: Double = 0
        
        for segment in segments {
            switch segment.type {
            case .speech: speech += segment.duration
            case .silence: silence += segment.duration
            case .music: music += segment.duration
            case .noise, .unknown: break
            }
        }
        
        self.totalSpeechDuration = speech
        self.totalSilenceDuration = silence
        self.totalMusicDuration = music
        
        let total = speech + silence + music
        self.speechRatio = total > 0 ? Float(speech / total) : 0
    }
    
    public var speechSegments: [SpeechActivity] {
        segments.filter { $0.type == .speech }
    }
    
    public var hasSpeech: Bool {
        totalSpeechDuration > 0
    }
}

// MARK: - Transcription Options

/// Options for transcription
public struct TranscriptionOptions: Sendable {
    public let language: String?
    public let translateToEnglish: Bool
    public let enableWordTiming: Bool
    public let enableDiarization: Bool
    public let expectedSpeakerCount: Int?
    public let vadSensitivity: Float
    public let maxSegmentLength: Double
    
    public init(
        language: String? = nil,
        translateToEnglish: Bool = false,
        enableWordTiming: Bool = true,
        enableDiarization: Bool = false,
        expectedSpeakerCount: Int? = nil,
        vadSensitivity: Float = 0.5,
        maxSegmentLength: Double = 30.0
    ) {
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.enableWordTiming = enableWordTiming
        self.enableDiarization = enableDiarization
        self.expectedSpeakerCount = expectedSpeakerCount
        self.vadSensitivity = vadSensitivity
        self.maxSegmentLength = maxSegmentLength
    }
    
    public static let `default` = TranscriptionOptions()
    
    public static let fast = TranscriptionOptions(
        enableWordTiming: false,
        enableDiarization: false
    )
    
    public static let full = TranscriptionOptions(
        enableWordTiming: true,
        enableDiarization: true
    )
}
