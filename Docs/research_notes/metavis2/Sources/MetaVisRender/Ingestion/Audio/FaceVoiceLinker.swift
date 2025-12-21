// Sources/MetaVisRender/Ingestion/Audio/FaceVoiceLinker.swift
// Sprint 03: Match speakers to visible faces

import Foundation
import simd

// MARK: - Face Voice Linker

/// Links speaker diarization segments to detected faces
/// Uses temporal correlation and optional lip sync analysis
public actor FaceVoiceLinker {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Minimum overlap ratio for temporal correlation
        public let minOverlapRatio: Float
        /// Weight for temporal correlation in scoring
        public let temporalWeight: Float
        /// Weight for face visibility in scoring
        public let visibilityWeight: Float
        /// Weight for face position (centered faces more likely speaking)
        public let positionWeight: Float
        /// Minimum confidence to create a link
        public let minLinkConfidence: Float
        
        public init(
            minOverlapRatio: Float = 0.3,
            temporalWeight: Float = 0.5,
            visibilityWeight: Float = 0.3,
            positionWeight: Float = 0.2,
            minLinkConfidence: Float = 0.4
        ) {
            self.minOverlapRatio = minOverlapRatio
            self.temporalWeight = temporalWeight
            self.visibilityWeight = visibilityWeight
            self.positionWeight = positionWeight
            self.minLinkConfidence = minLinkConfidence
        }
        
        public static let `default` = Config()
        
        public static let strict = Config(
            minOverlapRatio: 0.5,
            minLinkConfidence: 0.6
        )
        
        public static let lenient = Config(
            minOverlapRatio: 0.2,
            minLinkConfidence: 0.3
        )
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Public API
    
    /// Link speaker segments to face observations
    public func linkSpeakersToFaces(
        diarization: DiarizationResult,
        faceObservations: [TimedFaceObservation],
        videoDuration: Double
    ) async -> FaceVoiceLinkResult {
        guard !diarization.speakers.isEmpty else {
            return FaceVoiceLinkResult(
                links: [],
                unmatchedSpeakers: [],
                unmatchedFaces: [],
                confidence: 0
            )
        }
        
        // Build face presence timeline
        let faceTimelines = buildFaceTimelines(from: faceObservations)
        
        // Simple heuristic: if exactly 1 speaker and 1 face, link them directly (monologue case)
        if diarization.speakers.count == 1 && faceTimelines.count == 1,
           let speaker = diarization.speakers.first,
           let (faceId, _) = faceTimelines.first {
            let link = SpeakerFaceLink(
                speakerId: speaker.id,
                faceId: faceId,
                confidence: 0.95,  // High confidence for single speaker/face match
                correlationType: .temporal
            )
            return FaceVoiceLinkResult(
                links: [link],
                unmatchedSpeakers: [],
                unmatchedFaces: [],
                confidence: 0.95
            )
        }
        
        // Score each speaker-face pair
        var links: [SpeakerFaceLink] = []
        var usedFaces: Set<String> = []
        
        for speaker in diarization.speakers {
            let speakerSegments = diarization.segments(for: speaker.id)
            
            // Score all faces for this speaker
            var faceScores: [(faceId: String, score: Float, correlation: CorrelationType)] = []
            
            for (faceId, timeline) in faceTimelines {
                let score = calculateLinkScore(
                    speakerSegments: speakerSegments,
                    faceTimeline: timeline,
                    videoDuration: videoDuration
                )
                
                if score.total >= config.minLinkConfidence {
                    faceScores.append((faceId, score.total, score.correlationType))
                }
            }
            
            // Pick best matching face
            faceScores.sort { $0.score > $1.score }
            
            if let best = faceScores.first, !usedFaces.contains(best.faceId) {
                let link = SpeakerFaceLink(
                    speakerId: speaker.id,
                    faceId: best.faceId,
                    confidence: best.score,
                    correlationType: best.correlation
                )
                links.append(link)
                usedFaces.insert(best.faceId)
            } else {
                // No face matched
                links.append(SpeakerFaceLink(
                    speakerId: speaker.id,
                    faceId: nil,
                    confidence: 0,
                    correlationType: .none
                ))
            }
        }
        
        // Find unmatched faces
        let allFaceIds = Set(faceTimelines.keys)
        let unmatchedFaces = Array(allFaceIds.subtracting(usedFaces))
        
        // Find unmatched speakers
        let unmatchedSpeakers = links.filter { $0.faceId == nil }.map { $0.speakerId }
        
        // Calculate overall confidence
        let matchedLinks = links.filter { $0.faceId != nil }
        let avgConfidence = matchedLinks.isEmpty ? 0 : matchedLinks.reduce(0) { $0 + $1.confidence } / Float(matchedLinks.count)
        
        return FaceVoiceLinkResult(
            links: links,
            unmatchedSpeakers: unmatchedSpeakers,
            unmatchedFaces: unmatchedFaces,
            confidence: avgConfidence
        )
    }
    
    /// Link with additional lip sync analysis (requires mouth landmark data)
    public func linkWithLipSync(
        diarization: DiarizationResult,
        faceObservations: [TimedFaceObservation],
        mouthLandmarks: [TimedMouthLandmarks]?,
        videoDuration: Double
    ) async -> FaceVoiceLinkResult {
        // If no mouth landmarks, fall back to temporal correlation
        guard let landmarks = mouthLandmarks, !landmarks.isEmpty else {
            return await linkSpeakersToFaces(
                diarization: diarization,
                faceObservations: faceObservations,
                videoDuration: videoDuration
            )
        }
        
        // Build face presence timeline
        let faceTimelines = buildFaceTimelines(from: faceObservations)
        
        // Build mouth movement timeline
        let mouthMovement = analyzeMouthMovement(landmarks: landmarks)
        
        var links: [SpeakerFaceLink] = []
        var usedFaces: Set<String> = []
        
        for speaker in diarization.speakers {
            let speakerSegments = diarization.segments(for: speaker.id)
            
            var faceScores: [(faceId: String, score: Float, correlation: CorrelationType)] = []
            
            for (faceId, timeline) in faceTimelines {
                // Temporal score
                let temporalScore = calculateLinkScore(
                    speakerSegments: speakerSegments,
                    faceTimeline: timeline,
                    videoDuration: videoDuration
                )
                
                // Lip sync score
                let lipSyncScore = calculateLipSyncScore(
                    speakerSegments: speakerSegments,
                    faceId: faceId,
                    mouthMovement: mouthMovement
                )
                
                // Combined score (weight lip sync more heavily when available)
                let combinedScore = temporalScore.total * 0.4 + lipSyncScore * 0.6
                let correlationType: CorrelationType = lipSyncScore > 0.5 ? .lipSync : temporalScore.correlationType
                
                if combinedScore >= config.minLinkConfidence {
                    faceScores.append((faceId, combinedScore, correlationType))
                }
            }
            
            faceScores.sort { $0.score > $1.score }
            
            if let best = faceScores.first, !usedFaces.contains(best.faceId) {
                let link = SpeakerFaceLink(
                    speakerId: speaker.id,
                    faceId: best.faceId,
                    confidence: best.score,
                    correlationType: best.correlation
                )
                links.append(link)
                usedFaces.insert(best.faceId)
            } else {
                links.append(SpeakerFaceLink(
                    speakerId: speaker.id,
                    faceId: nil,
                    confidence: 0,
                    correlationType: .none
                ))
            }
        }
        
        let allFaceIds = Set(faceTimelines.keys)
        let unmatchedFaces = Array(allFaceIds.subtracting(usedFaces))
        let unmatchedSpeakers = links.filter { $0.faceId == nil }.map { $0.speakerId }
        let matchedLinks = links.filter { $0.faceId != nil }
        let avgConfidence = matchedLinks.isEmpty ? 0 : matchedLinks.reduce(0) { $0 + $1.confidence } / Float(matchedLinks.count)
        
        return FaceVoiceLinkResult(
            links: links,
            unmatchedSpeakers: unmatchedSpeakers,
            unmatchedFaces: unmatchedFaces,
            confidence: avgConfidence
        )
    }
    
    // MARK: - Private Methods
    
    private func buildFaceTimelines(
        from observations: [TimedFaceObservation]
    ) -> [String: [(start: Double, end: Double, bounds: CGRect, position: CGPoint)]] {
        var timelines: [String: [(start: Double, end: Double, bounds: CGRect, position: CGPoint)]] = [:]
        
        // Sort observations by time
        let sorted = observations.sorted { $0.timestamp < $1.timestamp }
        
        // Group consecutive observations by face ID
        for observation in sorted {
            for face in observation.faces {
                let faceId = face.id
                let center = CGPoint(
                    x: face.bounds.midX,
                    y: face.bounds.midY
                )
                
                if timelines[faceId] == nil {
                    timelines[faceId] = []
                }
                
                // Extend existing segment or create new one
                if var lastSegment = timelines[faceId]?.last,
                   observation.timestamp - lastSegment.end < 0.5 {  // 500ms gap tolerance
                    lastSegment.end = observation.timestamp
                    timelines[faceId]![timelines[faceId]!.count - 1] = lastSegment
                } else {
                    timelines[faceId]!.append((
                        start: observation.timestamp,
                        end: observation.timestamp,
                        bounds: face.bounds,
                        position: center
                    ))
                }
            }
        }
        
        return timelines
    }
    
    private func calculateLinkScore(
        speakerSegments: [SpeakerSegment],
        faceTimeline: [(start: Double, end: Double, bounds: CGRect, position: CGPoint)],
        videoDuration: Double
    ) -> (total: Float, correlationType: CorrelationType) {
        var overlapTime: Double = 0
        var speakerTime: Double = 0
        var visibilityScore: Float = 0
        var positionScore: Float = 0
        var overlapCount = 0
        
        for segment in speakerSegments {
            speakerTime += segment.duration
            
            for faceSegment in faceTimeline {
                // Calculate overlap
                let overlapStart = max(segment.start, faceSegment.start)
                let overlapEnd = min(segment.end, faceSegment.end)
                
                if overlapStart < overlapEnd {
                    overlapTime += overlapEnd - overlapStart
                    overlapCount += 1
                    
                    // Face size as proxy for visibility (larger = more prominent)
                    let faceSize = Float(faceSegment.bounds.width * faceSegment.bounds.height)
                    visibilityScore += min(1.0, faceSize * 4)  // Normalize
                    
                    // Position score (center of frame = higher score)
                    let distFromCenter = sqrt(
                        pow(Float(faceSegment.position.x) - 0.5, 2) +
                        pow(Float(faceSegment.position.y) - 0.5, 2)
                    )
                    positionScore += max(0, 1.0 - distFromCenter * 2)
                }
            }
        }
        
        guard speakerTime > 0 && overlapCount > 0 else {
            return (0, .none)
        }
        
        // Normalize scores
        let temporalScore = Float(overlapTime / speakerTime)
        visibilityScore /= Float(overlapCount)
        positionScore /= Float(overlapCount)
        
        // Check minimum overlap
        if temporalScore < config.minOverlapRatio {
            return (0, .none)
        }
        
        // Weighted combination
        let totalScore = temporalScore * config.temporalWeight +
                        visibilityScore * config.visibilityWeight +
                        positionScore * config.positionWeight
        
        let correlationType: CorrelationType = temporalScore > 0.6 ? .temporal : .spatial
        
        return (totalScore, correlationType)
    }
    
    private func analyzeMouthMovement(
        landmarks: [TimedMouthLandmarks]
    ) -> [String: [(time: Double, movement: Float)]] {
        var movement: [String: [(time: Double, movement: Float)]] = [:]
        
        // Sort by time
        let sorted = landmarks.sorted { $0.timestamp < $1.timestamp }
        
        // Track previous mouth state per face
        var previousState: [String: Float] = [:]
        
        for landmark in sorted {
            let faceId = landmark.faceId
            let mouthOpenness = landmark.mouthOpenness
            
            if movement[faceId] == nil {
                movement[faceId] = []
            }
            
            // Calculate movement as change from previous
            let movementValue: Float
            if let previous = previousState[faceId] {
                movementValue = abs(mouthOpenness - previous)
            } else {
                movementValue = 0
            }
            
            movement[faceId]!.append((time: landmark.timestamp, movement: movementValue))
            previousState[faceId] = mouthOpenness
        }
        
        return movement
    }
    
    private func calculateLipSyncScore(
        speakerSegments: [SpeakerSegment],
        faceId: String,
        mouthMovement: [String: [(time: Double, movement: Float)]]
    ) -> Float {
        guard let movements = mouthMovement[faceId] else {
            return 0
        }
        
        var speechMovement: Float = 0
        var silenceMovement: Float = 0
        var speechSamples = 0
        var silenceSamples = 0
        
        for m in movements {
            let isDuringSpeech = speakerSegments.contains { segment in
                m.time >= segment.start && m.time <= segment.end
            }
            
            if isDuringSpeech {
                speechMovement += m.movement
                speechSamples += 1
            } else {
                silenceMovement += m.movement
                silenceSamples += 1
            }
        }
        
        guard speechSamples > 0 else { return 0 }
        
        let avgSpeechMovement = speechMovement / Float(speechSamples)
        let avgSilenceMovement = silenceSamples > 0 ? silenceMovement / Float(silenceSamples) : 0
        
        // Good lip sync: more movement during speech than silence
        if avgSpeechMovement > avgSilenceMovement * 1.5 {
            return min(1.0, avgSpeechMovement / 0.1)  // Normalize
        }
        
        return 0
    }
}

// MARK: - Result Types

/// Result of face-voice linking
public struct FaceVoiceLinkResult: Codable, Sendable {
    /// Links between speakers and faces
    public let links: [SpeakerFaceLink]
    /// Speaker IDs without matched faces
    public let unmatchedSpeakers: [String]
    /// Face IDs without matched speakers
    public let unmatchedFaces: [String]
    /// Overall confidence of linking
    public let confidence: Float
    
    /// Get link for a specific speaker
    public func link(for speakerId: String) -> SpeakerFaceLink? {
        links.first { $0.speakerId == speakerId }
    }
    
    /// Get link for a specific face
    public func link(forFace faceId: String) -> SpeakerFaceLink? {
        links.first { $0.faceId == faceId }
    }
}

/// Link between a speaker and a face
public struct SpeakerFaceLink: Codable, Sendable {
    /// Speaker ID from diarization
    public let speakerId: String
    /// Face ID from detection (nil if no face matched)
    public let faceId: String?
    /// Confidence of the link
    public let confidence: Float
    /// How the correlation was determined
    public let correlationType: CorrelationType
    
    public var isMatched: Bool { faceId != nil }
}

/// Type of correlation used to link speaker and face
public enum CorrelationType: String, Codable, Sendable {
    case lipSync        // Mouth movement matches speech
    case temporal       // Face appears when speaking
    case spatial        // Face position in frame
    case manual         // User-assigned
    case none           // No correlation found
}

// MARK: - Input Types

/// Face observation at a specific time
public struct TimedFaceObservation: Codable, Sendable {
    public let timestamp: Double
    public let faces: [FaceInfo]
    
    public init(timestamp: Double, faces: [FaceInfo]) {
        self.timestamp = timestamp
        self.faces = faces
    }
}

/// Basic face information
public struct FaceInfo: Codable, Sendable {
    public let id: String
    public let bounds: CGRect
    public let confidence: Float
    
    public init(id: String, bounds: CGRect, confidence: Float) {
        self.id = id
        self.bounds = bounds
        self.confidence = confidence
    }
}

/// Mouth landmark data for lip sync
public struct TimedMouthLandmarks: Codable, Sendable {
    public let timestamp: Double
    public let faceId: String
    public let mouthOpenness: Float  // 0 = closed, 1 = fully open
    
    public init(timestamp: Double, faceId: String, mouthOpenness: Float) {
        self.timestamp = timestamp
        self.faceId = faceId
        self.mouthOpenness = mouthOpenness
    }
}
