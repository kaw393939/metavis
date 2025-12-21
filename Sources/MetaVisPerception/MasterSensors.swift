import Foundation
import MetaVisCore

public struct MasterSensors: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let source: SourceInfo
    public let sampling: SamplingInfo

    public let videoSamples: [VideoSample]
    public let audioSegments: [AudioSegment]
    /// Optional hop-sized audio telemetry frames (prosody / beat features).
    public let audioFrames: [AudioFrame]?
    /// Optional beat candidates derived deterministically from audioFrames.
    public let audioBeats: [AudioBeat]?
    public let warnings: [WarningSegment]

    /// Optional LLM-friendly descriptor segments derived deterministically from raw sensors.
    public let descriptors: [DescriptorSegment]?

    /// Optional auto-start suggestion for trimming leader (e.g., throat-clear / settling).
    public let suggestedStart: SuggestedStart?

    public let summary: Summary

    public init(
        schemaVersion: Int = 4,
        source: SourceInfo,
        sampling: SamplingInfo,
        videoSamples: [VideoSample],
        audioSegments: [AudioSegment],
        audioFrames: [AudioFrame]? = nil,
        audioBeats: [AudioBeat]? = nil,
        warnings: [WarningSegment],
        descriptors: [DescriptorSegment]? = nil,
        suggestedStart: SuggestedStart? = nil,
        summary: Summary
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.sampling = sampling
        self.videoSamples = videoSamples
        self.audioSegments = audioSegments
        self.audioFrames = audioFrames
        self.audioBeats = audioBeats
        self.warnings = warnings
        self.descriptors = descriptors
        self.suggestedStart = suggestedStart
        self.summary = summary
    }
}

public extension MasterSensors {
    enum DescriptorLabel: String, Sendable, Codable, Equatable {
        case suggestedStart = "suggested_start"
        case punchInSuggestion = "punch_in_suggestion"
        case singleSubject = "single_subject"
        case multiPerson = "multi_person"
        case noFaceDetected = "no_face_detected"

        case continuousSpeech = "continuous_speech"
        case silenceGap = "silence_gap"

        case safeForBeauty = "safe_for_beauty"
        case gradeConfidenceLow = "grade_confidence_low"
        case avoidHeavyGrade = "avoid_heavy_grade"
    }

    struct DescriptorEvidenceItem: Sendable, Codable, Equatable {
        public let field: String
        public let value: Double

        public init(field: String, value: Double) {
            self.field = field
            self.value = value
        }
    }

    struct DescriptorSegment: Sendable, Codable, Equatable {
        public let start: Double
        public let end: Double
        public let label: DescriptorLabel
        public let confidence: Double
        public let veto: Bool?
        public let evidence: [DescriptorEvidenceItem]
        public let reasons: [String]

        public init(
            start: Double,
            end: Double,
            label: DescriptorLabel,
            confidence: Double,
            veto: Bool? = nil,
            evidence: [DescriptorEvidenceItem] = [],
            reasons: [String] = []
        ) {
            self.start = start
            self.end = end
            self.label = label
            self.confidence = confidence
            self.veto = veto
            self.evidence = evidence
            self.reasons = reasons
        }
    }

    struct SuggestedStart: Sendable, Codable, Equatable {
        public let time: Double
        public let reasons: [String]
        public let confidence: Double

        public init(time: Double, reasons: [String], confidence: Double) {
            self.time = time
            self.reasons = reasons
            self.confidence = confidence
        }
    }

    struct SourceInfo: Sendable, Codable, Equatable {
        public let path: String
        public let durationSeconds: Double
        public let width: Int?
        public let height: Int?
        public let nominalFPS: Double?

        public init(path: String, durationSeconds: Double, width: Int?, height: Int?, nominalFPS: Double?) {
            self.path = path
            self.durationSeconds = durationSeconds
            self.width = width
            self.height = height
            self.nominalFPS = nominalFPS
        }
    }

    struct SamplingInfo: Sendable, Codable, Equatable {
        public let videoStrideSeconds: Double
        public let maxVideoSeconds: Double
        public let audioAnalyzeSeconds: Double

        public init(videoStrideSeconds: Double, maxVideoSeconds: Double, audioAnalyzeSeconds: Double) {
            self.videoStrideSeconds = videoStrideSeconds
            self.maxVideoSeconds = maxVideoSeconds
            self.audioAnalyzeSeconds = audioAnalyzeSeconds
        }
    }

    struct VideoSample: Sendable, Codable, Equatable {
        public let time: Double
        public let meanLuma: Double
        public let skinLikelihood: Double
        public let dominantColors: [SIMD3<Double>]
        public let faces: [Face]
        public let personMaskPresence: Double?
        public let peopleCountEstimate: Int?

        public init(
            time: Double,
            meanLuma: Double,
            skinLikelihood: Double,
            dominantColors: [SIMD3<Double>],
            faces: [Face],
            personMaskPresence: Double? = nil,
            peopleCountEstimate: Int? = nil
        ) {
            self.time = time
            self.meanLuma = meanLuma
            self.skinLikelihood = skinLikelihood
            self.dominantColors = dominantColors
            self.faces = faces
            self.personMaskPresence = personMaskPresence
            self.peopleCountEstimate = peopleCountEstimate
        }
    }

    enum AudioSegmentKind: String, Sendable, Codable, Equatable {
        case speechLike
        case musicLike
        case silence
        case unknown
    }

    struct AudioSegment: Sendable, Codable, Equatable {
        public let start: Double
        public let end: Double
        public let kind: AudioSegmentKind
        public let confidence: Double

        /// Optional per-segment audio features (derived deterministically from analysis windows).
        public let rmsDB: Double?
        public let spectralCentroidHz: Double?
        public let dominantFrequencyHz: Double?
        /// Spectral flatness (0..1). Higher means more noise-like.
        public let spectralFlatness: Double?

        public init(
            start: Double,
            end: Double,
            kind: AudioSegmentKind,
            confidence: Double,
            rmsDB: Double? = nil,
            spectralCentroidHz: Double? = nil,
            dominantFrequencyHz: Double? = nil,
            spectralFlatness: Double? = nil
        ) {
            self.start = start
            self.end = end
            self.kind = kind
            self.confidence = confidence
            self.rmsDB = rmsDB
            self.spectralCentroidHz = spectralCentroidHz
            self.dominantFrequencyHz = dominantFrequencyHz
            self.spectralFlatness = spectralFlatness
        }
    }

    /// Hop-sized audio telemetry suitable for beat detection and emphasis modeling.
    struct AudioFrame: Sendable, Codable, Equatable {
        public let start: Double
        public let end: Double

        public let rmsDB: Double?
        public let rmsDeltaDB: Double?

        public let spectralCentroidHz: Double?
        public let centroidDeltaHz: Double?

        public let dominantFrequencyHz: Double?
        public let dominantDeltaHz: Double?

        public let spectralFlatness: Double?
        public let flatnessDelta: Double?

        public let zeroCrossingRate: Double?
        public let zcrDelta: Double?

        /// 0..1 proxy for “speech-likeness / voicing”. Higher values correlate with voiced speech.
        public let voicingScore: Double?
        public let voicingDelta: Double?

        /// Optional pitch estimate in Hz (very lightweight heuristic; nil when not confident).
        public let pitchHz: Double?

        public init(
            start: Double,
            end: Double,
            rmsDB: Double? = nil,
            rmsDeltaDB: Double? = nil,
            spectralCentroidHz: Double? = nil,
            centroidDeltaHz: Double? = nil,
            dominantFrequencyHz: Double? = nil,
            dominantDeltaHz: Double? = nil,
            spectralFlatness: Double? = nil,
            flatnessDelta: Double? = nil,
            zeroCrossingRate: Double? = nil,
            zcrDelta: Double? = nil,
            voicingScore: Double? = nil,
            voicingDelta: Double? = nil,
            pitchHz: Double? = nil
        ) {
            self.start = start
            self.end = end
            self.rmsDB = rmsDB
            self.rmsDeltaDB = rmsDeltaDB
            self.spectralCentroidHz = spectralCentroidHz
            self.centroidDeltaHz = centroidDeltaHz
            self.dominantFrequencyHz = dominantFrequencyHz
            self.dominantDeltaHz = dominantDeltaHz
            self.spectralFlatness = spectralFlatness
            self.flatnessDelta = flatnessDelta
            self.zeroCrossingRate = zeroCrossingRate
            self.zcrDelta = zcrDelta
            self.voicingScore = voicingScore
            self.voicingDelta = voicingDelta
            self.pitchHz = pitchHz
        }
    }

    enum AudioBeatKind: String, Sendable, Codable, Equatable {
        case emphasis
        case boundary
    }

    struct AudioBeat: Sendable, Codable, Equatable {
        /// Beat onset time in seconds.
        public let time: Double
        /// Optional “impact” time in seconds (typically onset + ~200ms), snapped to a deterministic grid.
        public let timeImpact: Double?
        public let kind: AudioBeatKind
        public let confidence: Double
        public let reasons: [String]

        public init(time: Double, timeImpact: Double? = nil, kind: AudioBeatKind, confidence: Double, reasons: [String] = []) {
            self.time = time
            self.timeImpact = timeImpact
            self.kind = kind
            self.confidence = confidence
            self.reasons = reasons
        }
    }

    struct Face: Sendable, Codable, Equatable {
        public let trackId: UUID
        public let rect: CGRect // normalized 0..1, top-left origin
        /// Optional stable identity label for the person owning this track.
        /// v1 MVP: derived deterministically from stable track index (no faceprints yet).
        public let personId: String?

        public init(trackId: UUID, rect: CGRect, personId: String? = nil) {
            self.trackId = trackId
            self.rect = rect
            self.personId = personId
        }
    }

    struct Summary: Sendable, Codable, Equatable {
        public let analyzedSeconds: Double
        public let scene: SceneContext
        public let audio: AudioSummary

        public init(analyzedSeconds: Double, scene: SceneContext, audio: AudioSummary) {
            self.analyzedSeconds = analyzedSeconds
            self.scene = scene
            self.audio = audio
        }
    }

    struct AudioSummary: Sendable, Codable, Equatable {
        /// Approximate RMS level in dBFS (NOT LUFS; no K-weighting / gating).
        public let approxRMSdBFS: Float
        public let approxPeakDB: Float

        /// FFT-derived features (optional; present when audio analysis is enabled and enough samples exist).
        public let dominantFrequencyHz: Double?
        public let spectralCentroidHz: Double?

        public init(
            approxRMSdBFS: Float,
            approxPeakDB: Float,
            dominantFrequencyHz: Double? = nil,
            spectralCentroidHz: Double? = nil
        ) {
            self.approxRMSdBFS = approxRMSdBFS
            self.approxPeakDB = approxPeakDB
            self.dominantFrequencyHz = dominantFrequencyHz
            self.spectralCentroidHz = spectralCentroidHz
        }

        private enum CodingKeys: String, CodingKey {
            case approxRMSdBFS
            case approxLUFS // legacy alias
            case approxPeakDB
            case dominantFrequencyHz
            case spectralCentroidHz
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let v = try c.decodeIfPresent(Float.self, forKey: .approxRMSdBFS) {
                self.approxRMSdBFS = v
            } else {
                self.approxRMSdBFS = try c.decode(Float.self, forKey: .approxLUFS)
            }
            self.approxPeakDB = try c.decode(Float.self, forKey: .approxPeakDB)
            self.dominantFrequencyHz = try c.decodeIfPresent(Double.self, forKey: .dominantFrequencyHz)
            self.spectralCentroidHz = try c.decodeIfPresent(Double.self, forKey: .spectralCentroidHz)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(approxRMSdBFS, forKey: .approxRMSdBFS)
            try c.encode(approxPeakDB, forKey: .approxPeakDB)
            try c.encodeIfPresent(dominantFrequencyHz, forKey: .dominantFrequencyHz)
            try c.encodeIfPresent(spectralCentroidHz, forKey: .spectralCentroidHz)
        }
    }

    enum TrafficLight: String, Sendable, Codable, Equatable {
        case green
        case yellow
        case red
    }

    struct WarningSegment: Sendable, Codable, Equatable {
        public let start: Double
        public let end: Double
        public let severity: TrafficLight

        /// Governed reason codes (preferred).
        public let reasonCodes: [ReasonCodeV1]

        /// Legacy string reasons. When encoding, we emit these as the rawValue of `reasonCodes`
        /// to preserve compatibility while preventing free-text.
        public let reasons: [String]

        public init(start: Double, end: Double, severity: TrafficLight, reasonCodes: [ReasonCodeV1]) {
            self.start = start
            self.end = end
            self.severity = severity

            let normalized = Array(Set(reasonCodes)).sorted()
            self.reasonCodes = normalized
            self.reasons = normalized.map { $0.rawValue }
        }

        public init(start: Double, end: Double, severity: TrafficLight, reasons: [String]) {
            self.start = start
            self.end = end
            self.severity = severity

            let normalizedStrings = Array(Set(reasons)).sorted()
            self.reasons = normalizedStrings
            self.reasonCodes = normalizedStrings.compactMap { ReasonCodeV1(rawValue: $0) }.sorted()
        }

        /// Returns governed reason codes when present, otherwise best-effort mapping from legacy reasons.
        public var governedReasonCodes: [ReasonCodeV1] {
            if !reasonCodes.isEmpty { return reasonCodes }
            return reasons.compactMap { ReasonCodeV1(rawValue: $0) }.sorted()
        }

        private enum CodingKeys: String, CodingKey {
            case start
            case end
            case severity
            case reasonCodes
            case reasons
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.start = try c.decode(Double.self, forKey: .start)
            self.end = try c.decode(Double.self, forKey: .end)
            self.severity = try c.decode(TrafficLight.self, forKey: .severity)

            // Prefer governed reasonCodes; fall back to legacy reasons.
            let decodedCodes = try c.decodeIfPresent([ReasonCodeV1].self, forKey: .reasonCodes) ?? []
            if !decodedCodes.isEmpty {
                let normalized = Array(Set(decodedCodes)).sorted()
                self.reasonCodes = normalized
                self.reasons = normalized.map { $0.rawValue }
            } else {
                let decodedReasons = try c.decodeIfPresent([String].self, forKey: .reasons) ?? []
                let normalizedStrings = Array(Set(decodedReasons)).sorted()
                self.reasons = normalizedStrings
                self.reasonCodes = normalizedStrings.compactMap { ReasonCodeV1(rawValue: $0) }.sorted()
            }
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(end, forKey: .end)
            try c.encode(severity, forKey: .severity)
            try c.encode(reasonCodes, forKey: .reasonCodes)

            // Prevent free-text: always encode string reasons derived from governed codes.
            try c.encode(reasonCodes.map { $0.rawValue }, forKey: .reasons)
        }
    }

    enum SceneLabel: String, Sendable, Codable, Equatable {
        case indoor
        case outdoor
        case unknown
    }

    enum LightSourceLabel: String, Sendable, Codable, Equatable {
        case natural
        case artificial
        case mixed
        case unknown
    }

    struct ScoredLabel<T: Sendable & Codable & Equatable>: Sendable, Codable, Equatable {
        public let label: T
        public let confidence: Double

        public init(label: T, confidence: Double) {
            self.label = label
            self.confidence = confidence
        }
    }

    struct SceneContext: Sendable, Codable, Equatable {
        public let indoorOutdoor: ScoredLabel<SceneLabel>
        public let lightSource: ScoredLabel<LightSourceLabel>

        public init(indoorOutdoor: ScoredLabel<SceneLabel>, lightSource: ScoredLabel<LightSourceLabel>) {
            self.indoorOutdoor = indoorOutdoor
            self.lightSource = lightSource
        }
    }
}
