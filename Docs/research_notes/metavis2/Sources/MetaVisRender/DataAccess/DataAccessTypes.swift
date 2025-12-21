// DataAccessTypes.swift
// MetaVisRender
//
// Created for Sprint 09: Data Access Layer
// Core types for unified data access

import Foundation
import CoreMedia

// MARK: - Identifier Types

/// Unique identifier for speakers (audio diarization)
public struct SpeakerID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(_ value: String) {
        self.rawValue = value
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Unique identifier for persons (visual identity)
public struct DataPersonID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(_ value: String) {
        self.rawValue = value
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Unique identifier for global identities (cross-project)
public struct GlobalPersonID: Hashable, Codable, Sendable {
    public let rawValue: String
    
    public init(_ value: String) {
        self.rawValue = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Unified entity reference (speaker or person)
public enum EntityID: Codable, Sendable {
    case speaker(SpeakerID)
    case person(DataPersonID)
    
    public init(from string: String) {
        if string.hasPrefix("SPEAKER_") {
            self = .speaker(SpeakerID(string))
        } else {
            self = .person(DataPersonID(string))
        }
    }
}

// MARK: - Speaker (Audio Entity)

/// A detected speaker from audio diarization
public struct DataSpeaker: Identifiable, Codable, Sendable {
    /// Unique identifier (e.g., "SPEAKER_00")
    public let id: SpeakerID
    
    /// User-assigned name (nil if not identified)
    public var name: String?
    
    /// Alternative names/aliases
    public var aliases: [String]
    
    /// Linked visual person (if matched)
    public var linkedPersonID: DataPersonID?
    
    /// Total speaking duration in seconds
    public var totalDuration: TimeInterval
    
    /// Number of speaking segments
    public var segmentCount: Int
    
    /// Voice embedding for matching (optional)
    public var voicePrint: Data?
    
    public init(
        id: SpeakerID,
        name: String? = nil,
        aliases: [String] = [],
        linkedPersonID: DataPersonID? = nil,
        totalDuration: TimeInterval = 0,
        segmentCount: Int = 0,
        voicePrint: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.linkedPersonID = linkedPersonID
        self.totalDuration = totalDuration
        self.segmentCount = segmentCount
        self.voicePrint = voicePrint
    }
    
    /// Display name (user-assigned or ID)
    public var displayName: String {
        name ?? id.rawValue
    }
}

// MARK: - Person (Visual Entity)

/// A detected person from visual analysis
public struct DataPerson: Identifiable, Codable, Sendable {
    /// Unique identifier (e.g., "PERSON_001")
    public let id: DataPersonID
    
    /// User-assigned name (nil if not identified)
    public var name: String?
    
    /// Linked audio speaker (if matched)
    public var linkedSpeakerID: SpeakerID?
    
    /// Global identity match (if recognized)
    public var globalPersonID: GlobalPersonID?
    
    /// Face embedding path (512-dim vector)
    public var embeddingPath: URL?
    
    /// Best face crop for display
    public var thumbnailPath: URL?
    
    /// Number of frame appearances
    public var appearanceCount: Int
    
    /// Total time visible on screen
    public var totalScreenTime: TimeInterval
    
    /// When first detected
    public var createdAt: Date
    
    public init(
        id: DataPersonID,
        name: String? = nil,
        linkedSpeakerID: SpeakerID? = nil,
        globalPersonID: GlobalPersonID? = nil,
        embeddingPath: URL? = nil,
        thumbnailPath: URL? = nil,
        appearanceCount: Int = 0,
        totalScreenTime: TimeInterval = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.linkedSpeakerID = linkedSpeakerID
        self.globalPersonID = globalPersonID
        self.embeddingPath = embeddingPath
        self.thumbnailPath = thumbnailPath
        self.appearanceCount = appearanceCount
        self.totalScreenTime = totalScreenTime
        self.createdAt = createdAt
    }
    
    /// Display name (user-assigned or ID)
    public var displayName: String {
        name ?? id.rawValue
    }
}

// MARK: - Data Segment

/// A continuous segment of speech (used in DataAccess layer)
public struct DataSegment: Identifiable, Codable, Sendable {
    /// Database ID
    public let id: Int
    
    /// Start time in seconds
    public let startTime: TimeInterval
    
    /// End time in seconds
    public let endTime: TimeInterval
    
    /// Speaker who said this (may be nil)
    public var speakerID: SpeakerID?
    
    /// Transcribed text
    public var transcript: String
    
    /// Transcription confidence (0-1)
    public var confidence: Float
    
    /// Detected emotion scores for this segment
    public var emotions: [DataEmotionScore]
    
    /// Persons visible during this segment
    public var visiblePersons: [DataPersonID]
    
    public init(
        id: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: SpeakerID? = nil,
        transcript: String,
        confidence: Float = 1.0,
        emotions: [DataEmotionScore] = [],
        visiblePersons: [DataPersonID] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
        self.transcript = transcript
        self.confidence = confidence
        self.emotions = emotions
        self.visiblePersons = visiblePersons
    }
    
    /// Duration in seconds
    public var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Time range as CMTimeRange
    public var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
    }
}

/// Emotion with confidence score
public struct DataEmotionScore: Codable, Sendable {
    public let emotion: DataEmotion
    public let score: Float
    
    public init(emotion: DataEmotion, score: Float) {
        self.emotion = emotion
        self.score = score
    }
}

/// Supported emotion types (mirrors EmotionCategory but allows extension)
public enum DataEmotion: String, Codable, CaseIterable, Sendable {
    case neutral
    case happy
    case sad
    case angry
    case surprised
    case fearful
    case disgusted
    case excited
    case confused
    case contempt
    
    /// Valence (-1 to +1)
    public var typicalValence: Float {
        switch self {
        case .neutral: return 0.0
        case .happy, .excited: return 0.8
        case .sad: return -0.7
        case .angry: return -0.6
        case .fearful: return -0.8
        case .disgusted: return -0.5
        case .surprised: return 0.3
        case .confused: return -0.2
        case .contempt: return -0.4
        }
    }
}

// MARK: - Appearance (Face Observation)

/// A single face appearance in a frame
public struct FaceAppearance: Identifiable, Codable, Sendable {
    /// Database ID
    public let id: Int
    
    /// Which person this appearance belongs to
    public let personID: DataPersonID
    
    /// Frame time in seconds
    public let frameTime: TimeInterval
    
    /// Bounding box (normalized 0-1)
    public let boundingBox: CGRect
    
    /// Detection confidence
    public let confidence: Float
    
    /// Emotion at this appearance (optional)
    public var emotion: DataEmotionScore?
    
    public init(
        id: Int,
        personID: DataPersonID,
        frameTime: TimeInterval,
        boundingBox: CGRect,
        confidence: Float,
        emotion: DataEmotionScore? = nil
    ) {
        self.id = id
        self.personID = personID
        self.frameTime = frameTime
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.emotion = emotion
    }
}

// MARK: - Moment (Auto-Detected Event)

/// An automatically detected interesting moment
public struct DetectedMoment: Identifiable, Codable, Sendable {
    /// Database ID
    public let id: Int
    
    /// Start time in seconds
    public let startTime: TimeInterval
    
    /// End time in seconds
    public let endTime: TimeInterval
    
    /// Type of moment detected
    public let type: MomentType
    
    /// Importance score (0-1)
    public let score: Float
    
    /// Human-readable description
    public let description: String
    
    /// Related speaker IDs
    public var speakers: [SpeakerID]
    
    /// Related person IDs
    public var persons: [DataPersonID]
    
    public init(
        id: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        type: MomentType,
        score: Float,
        description: String,
        speakers: [SpeakerID] = [],
        persons: [DataPersonID] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.type = type
        self.score = score
        self.description = description
        self.speakers = speakers
        self.persons = persons
    }
    
    /// Duration in seconds
    public var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Time range as CMTimeRange
    public var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
    }
}

/// Types of auto-detected moments
public enum MomentType: String, Codable, CaseIterable, Sendable {
    case emotionalPeak      // High emotion detected
    case topicChange        // Subject transition
    case speakerChange      // Different person starts speaking
    case silence            // Pause in conversation
    case overlappingSpeech  // Multiple people talking
    case laughter           // Detected laughter
    case applause           // Detected applause
    case keyStatement       // Important quote detected
    case sceneChange        // Visual scene change
}

// MARK: - Clip (Complete Thought)

/// A complete clip (sentence-bounded segment)
public struct DataClip: Identifiable, Codable, Sendable {
    /// Derived ID from time range
    public var id: String {
        "\(startTime)-\(endTime)"
    }
    
    /// Start time in seconds
    public let startTime: TimeInterval
    
    /// End time in seconds
    public let endTime: TimeInterval
    
    /// Primary speaker
    public var speakerID: SpeakerID?
    
    /// Speaker name (resolved)
    public var speakerName: String?
    
    /// Full transcript
    public let transcript: String
    
    /// Whether this is a complete sentence
    public let isCompleteSentence: Bool
    
    /// Average emotion during clip
    public var dominantEmotion: DataEmotion?
    
    /// Highlight score (0-1)
    public var highlightScore: Float
    
    public init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: SpeakerID? = nil,
        speakerName: String? = nil,
        transcript: String,
        isCompleteSentence: Bool = true,
        dominantEmotion: DataEmotion? = nil,
        highlightScore: Float = 0
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.transcript = transcript
        self.isCompleteSentence = isCompleteSentence
        self.dominantEmotion = dominantEmotion
        self.highlightScore = highlightScore
    }
    
    /// Duration in seconds
    public var duration: TimeInterval {
        endTime - startTime
    }
    
    /// Time range as CMTimeRange
    public var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
    }
}

// MARK: - Tag (User Annotation)

/// User-created annotation
public struct DataTag: Identifiable, Codable, Sendable {
    /// Database ID
    public let id: Int
    
    /// Start time in seconds
    public let startTime: TimeInterval
    
    /// End time in seconds
    public let endTime: TimeInterval
    
    /// Tag label (e.g., "key_moment", "blooper")
    public let label: String
    
    /// Optional note
    public var note: String?
    
    /// When created
    public let createdAt: Date
    
    public init(
        id: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        label: String,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
        self.note = note
        self.createdAt = createdAt
    }
    
    /// Time range as CMTimeRange
    public var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
    }
}

// MARK: - Media Metadata Record

/// EXIF/XMP metadata extracted from source media files
public struct MediaMetadataRecord: Identifiable, Codable, Sendable {
    /// Database ID
    public let id: Int
    
    /// Source file path (unique key)
    public let sourcePath: String
    
    // MARK: - Camera Settings
    
    /// ISO sensitivity
    public var iso: Int?
    
    /// Aperture (f-stop)
    public var aperture: Double?
    
    /// Shutter speed in seconds
    public var shutterSpeed: Double?
    
    /// Focal length in mm
    public var focalLength: Double?
    
    /// White balance mode
    public var whiteBalance: String?
    
    /// Exposure compensation in stops
    public var exposureCompensation: Double?
    
    // MARK: - Device Info
    
    /// Camera manufacturer
    public var cameraMake: String?
    
    /// Camera model name
    public var cameraModel: String?
    
    /// Lens manufacturer
    public var lensMake: String?
    
    /// Lens model name
    public var lensModel: String?
    
    /// Camera serial number
    public var cameraSerial: String?
    
    /// Lens serial number
    public var lensSerial: String?
    
    // MARK: - Shooting Conditions
    
    /// When the media was captured
    public var capturedAt: Date?
    
    /// Timezone of capture
    public var timezone: String?
    
    /// GPS latitude
    public var gpsLatitude: Double?
    
    /// GPS longitude
    public var gpsLongitude: Double?
    
    /// GPS altitude in meters
    public var gpsAltitude: Double?
    
    /// EXIF orientation value (1-8)
    public var orientation: Int?
    
    // MARK: - Curation Metadata
    
    /// User rating (1-5)
    public var rating: Int?
    
    /// Keywords/tags from XMP
    public var keywords: [String]
    
    /// Description/caption
    public var metadataDescription: String?
    
    /// Copyright notice
    public var copyright: String?
    
    /// Creator name
    public var creator: String?
    
    public init(
        id: Int,
        sourcePath: String,
        iso: Int? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        focalLength: Double? = nil,
        whiteBalance: String? = nil,
        exposureCompensation: Double? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensMake: String? = nil,
        lensModel: String? = nil,
        cameraSerial: String? = nil,
        lensSerial: String? = nil,
        capturedAt: Date? = nil,
        timezone: String? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsAltitude: Double? = nil,
        orientation: Int? = nil,
        rating: Int? = nil,
        keywords: [String] = [],
        metadataDescription: String? = nil,
        copyright: String? = nil,
        creator: String? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.iso = iso
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.focalLength = focalLength
        self.whiteBalance = whiteBalance
        self.exposureCompensation = exposureCompensation
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensMake = lensMake
        self.lensModel = lensModel
        self.cameraSerial = cameraSerial
        self.lensSerial = lensSerial
        self.capturedAt = capturedAt
        self.timezone = timezone
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsAltitude = gpsAltitude
        self.orientation = orientation
        self.rating = rating
        self.keywords = keywords
        self.metadataDescription = metadataDescription
        self.copyright = copyright
        self.creator = creator
    }
    
    /// Full camera name (make + model)
    public var cameraFullName: String? {
        [cameraMake, cameraModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    }
    
    /// Full lens name (make + model)
    public var lensFullName: String? {
        [lensMake, lensModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    }
    
    /// GPS coordinates as tuple if available
    public var gpsCoordinates: (lat: Double, lon: Double)? {
        guard let lat = gpsLatitude, let lon = gpsLongitude else { return nil }
        return (lat, lon)
    }
    
    /// Whether this is a high-ISO shot (ISO > 6400)
    public var isHighISO: Bool {
        guard let iso = iso else { return false }
        return iso > 6400
    }
    
    /// Whether this is shot wide open (aperture < 2.8)
    public var isWideOpen: Bool {
        guard let aperture = aperture else { return false }
        return aperture < 2.8
    }
}

// MARK: - Search Options

/// Options for transcript search
public struct SearchOptions: Sendable {
    /// Filter by speaker (name or ID)
    public var speaker: String?
    
    /// Filter by person visible
    public var person: String?
    
    /// Use regex pattern
    public var useRegex: Bool
    
    /// Case sensitive
    public var caseSensitive: Bool
    
    /// Maximum results
    public var limit: Int?
    
    /// Time range filter (seconds)
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    
    public init(
        speaker: String? = nil,
        person: String? = nil,
        useRegex: Bool = false,
        caseSensitive: Bool = false,
        limit: Int? = 100,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil
    ) {
        self.speaker = speaker
        self.person = person
        self.useRegex = useRegex
        self.caseSensitive = caseSensitive
        self.limit = limit
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - Search Results

/// Result from transcript search
public struct TranscriptMatch: Codable, Sendable {
    /// Segment ID
    public let segmentID: Int
    
    /// Start time in seconds
    public let startTime: TimeInterval
    
    /// End time in seconds
    public let endTime: TimeInterval
    
    /// Speaker ID (if known)
    public var speakerID: SpeakerID?
    
    /// Speaker name (resolved)
    public var speakerName: String?
    
    /// Full transcript
    public let transcript: String
    
    /// Highlighted transcript (with <mark> tags)
    public let highlighted: String
    
    public init(
        segmentID: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: SpeakerID? = nil,
        speakerName: String? = nil,
        transcript: String,
        highlighted: String
    ) {
        self.segmentID = segmentID
        self.startTime = startTime
        self.endTime = endTime
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.transcript = transcript
        self.highlighted = highlighted
    }
    
    /// Time range as CMTimeRange
    public var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
    }
}

// MARK: - Filters

/// Filter for moment queries
public struct MomentFilter: Sendable {
    /// Filter by moment type
    public var type: MomentType?
    
    /// Filter by emotion
    public var emotion: DataEmotion?
    
    /// Minimum score threshold
    public var minScore: Float
    
    /// Filter by speaker
    public var speaker: String?
    
    /// Time range filter (seconds)
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    
    /// Maximum results
    public var limit: Int
    
    public init(
        type: MomentType? = nil,
        emotion: DataEmotion? = nil,
        minScore: Float = 0.5,
        speaker: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        limit: Int = 20
    ) {
        self.type = type
        self.emotion = emotion
        self.minScore = minScore
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.limit = limit
    }
}

/// Filter for clip queries
public struct ClipFilter: Sendable {
    /// Filter by speaker
    public var speaker: String?
    
    /// Minimum duration (seconds)
    public var minDuration: Double?
    
    /// Maximum duration (seconds)
    public var maxDuration: Double?
    
    /// Only complete sentences
    public var completeSentencesOnly: Bool
    
    /// Filter by emotion
    public var emotion: DataEmotion?
    
    /// Time range filter (seconds)
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    
    /// Maximum results
    public var limit: Int
    
    public init(
        speaker: String? = nil,
        minDuration: Double? = nil,
        maxDuration: Double? = nil,
        completeSentencesOnly: Bool = false,
        emotion: DataEmotion? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        limit: Int = 50
    ) {
        self.speaker = speaker
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.completeSentencesOnly = completeSentencesOnly
        self.emotion = emotion
        self.startTime = startTime
        self.endTime = endTime
        self.limit = limit
    }
}

/// Filter for metadata queries
public struct MetadataFilter: Sendable {
    /// Filter by camera make/model (partial match)
    public var camera: String?
    
    /// Filter by lens make/model (partial match)
    public var lens: String?
    
    /// Minimum ISO value
    public var isoMin: Int?
    
    /// Maximum ISO value
    public var isoMax: Int?
    
    /// Minimum aperture (widest)
    public var apertureMin: Double?
    
    /// Maximum aperture (smallest opening)
    public var apertureMax: Double?
    
    /// Start date for capture time
    public var dateFrom: Date?
    
    /// End date for capture time
    public var dateTo: Date?
    
    /// Minimum rating (1-5)
    public var ratingMin: Int?
    
    /// Must contain this keyword
    public var keyword: String?
    
    /// Filter by creator name
    public var creator: String?
    
    /// Maximum results
    public var limit: Int
    
    public init(
        camera: String? = nil,
        lens: String? = nil,
        isoMin: Int? = nil,
        isoMax: Int? = nil,
        apertureMin: Double? = nil,
        apertureMax: Double? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        ratingMin: Int? = nil,
        keyword: String? = nil,
        creator: String? = nil,
        limit: Int = 100
    ) {
        self.camera = camera
        self.lens = lens
        self.isoMin = isoMin
        self.isoMax = isoMax
        self.apertureMin = apertureMin
        self.apertureMax = apertureMax
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.ratingMin = ratingMin
        self.keyword = keyword
        self.creator = creator
        self.limit = limit
    }
}

// MARK: - Ingestion State

/// Current state of project ingestion
public enum IngestionState: Codable, Sendable {
    case notStarted
    case inProgress(IngestionProgress)
    case ready
    case failed(String)
    
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    public var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
}

/// Progress details during ingestion
public struct IngestionProgress: Codable, Sendable {
    /// Current phase
    public let phase: IngestionPhase
    
    /// Overall progress (0-1)
    public let progress: Double
    
    /// Estimated time remaining in seconds
    public var eta: TimeInterval?
    
    /// Current item being processed
    public var currentItem: String?
    
    public init(
        phase: IngestionPhase,
        progress: Double,
        eta: TimeInterval? = nil,
        currentItem: String? = nil
    ) {
        self.phase = phase
        self.progress = progress
        self.eta = eta
        self.currentItem = currentItem
    }
}

/// Ingestion phases in order
public enum IngestionPhase: String, Codable, CaseIterable, Sendable {
    case extractingAudio = "Extracting audio"
    case transcribing = "Transcribing"
    case diarizing = "Detecting speakers"
    case detectingFaces = "Detecting faces"
    case computingEmbeddings = "Computing embeddings"
    case clusteringIdentities = "Clustering identities"
    case linkingSpeakers = "Linking speakers to faces"
    case detectingEmotions = "Analyzing emotions"
    case extractingMetadata = "Extracting metadata"
    case indexing = "Building search index"
    case complete = "Complete"
}

/// Types of data that can be queried
public enum DataType: String, Codable, CaseIterable, Sendable {
    case transcript       // Basic transcript available
    case speakers         // Speaker diarization complete
    case persons          // Face detection complete
    case identities       // Identity clustering complete
    case emotions         // Emotion analysis complete
    case moments          // Moment detection complete
    case spatialAudio     // Spatial positions computed
    case metadata         // EXIF/XMP metadata extracted
    case searchIndex      // FTS index built
}

// MARK: - Global Store Types

/// A known identity in the global database
public struct GlobalPerson: Identifiable, Codable, Sendable {
    /// Global unique ID
    public let id: GlobalPersonID
    
    /// Canonical name
    public let name: String
    
    /// Face embedding (512-dim)
    public let embedding: [Float]
    
    /// Voice print (optional)
    public var voicePrint: Data?
    
    /// Which project this was first identified in
    public let sourceProject: String
    
    /// Projects where this person appears
    public var projects: [String]
    
    /// When added to global store
    public let createdAt: Date
    
    /// When last matched
    public var lastSeenAt: Date
    
    public init(
        id: GlobalPersonID,
        name: String,
        embedding: [Float],
        voicePrint: Data? = nil,
        sourceProject: String,
        projects: [String] = [],
        createdAt: Date = Date(),
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.embedding = embedding
        self.voicePrint = voicePrint
        self.sourceProject = sourceProject
        self.projects = projects
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }
}

/// Result of matching against global database
public struct GlobalMatch: Codable, Sendable {
    /// Matched global identity
    public let globalPersonID: GlobalPersonID
    
    /// Global person's name
    public let name: String
    
    /// Similarity score (0-1)
    public let similarity: Float
    
    /// How the match was made
    public let method: MatchMethod
    
    public init(
        globalPersonID: GlobalPersonID,
        name: String,
        similarity: Float,
        method: MatchMethod = .faceEmbedding
    ) {
        self.globalPersonID = globalPersonID
        self.name = name
        self.similarity = similarity
        self.method = method
    }
}

/// Method used for identity matching
public enum MatchMethod: String, Codable, Sendable {
    case faceEmbedding
    case voicePrint
    case combined
}

// MARK: - Project Info

/// Project overview information
public struct ProjectInfo: Codable, Sendable {
    /// Project name (derived from path)
    public let name: String
    
    /// Source video path
    public let sourcePath: String
    
    /// Video duration in seconds
    public let duration: TimeInterval
    
    /// Current ingestion state
    public let state: IngestionState
    
    /// When project was created
    public let createdAt: Date
    
    /// When last modified
    public let modifiedAt: Date
    
    // MARK: - Counts
    
    /// Total speakers detected
    public let speakerCount: Int
    
    /// Speakers with names assigned
    public let namedSpeakerCount: Int
    
    /// Total persons detected
    public let personCount: Int
    
    /// Persons with names assigned
    public let namedPersonCount: Int
    
    /// Total transcript segments
    public let segmentCount: Int
    
    /// Auto-detected moments
    public let momentCount: Int
    
    /// User-created tags
    public let tagCount: Int
    
    public init(
        name: String,
        sourcePath: String,
        duration: TimeInterval,
        state: IngestionState,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        speakerCount: Int = 0,
        namedSpeakerCount: Int = 0,
        personCount: Int = 0,
        namedPersonCount: Int = 0,
        segmentCount: Int = 0,
        momentCount: Int = 0,
        tagCount: Int = 0
    ) {
        self.name = name
        self.sourcePath = sourcePath
        self.duration = duration
        self.state = state
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.speakerCount = speakerCount
        self.namedSpeakerCount = namedSpeakerCount
        self.personCount = personCount
        self.namedPersonCount = namedPersonCount
        self.segmentCount = segmentCount
        self.momentCount = momentCount
        self.tagCount = tagCount
    }
}

/// Timeline overview entry
public struct TimelineEntry: Codable, Sendable {
    /// Start time in seconds
    public let startTime: TimeInterval
    
    /// End time in seconds
    public let endTime: TimeInterval
    
    /// Type of segment
    public let type: TimelineEntryType
    
    /// Speaker (if speech)
    public var speakerID: SpeakerID?
    
    /// Speaker name (resolved)
    public var speakerName: String?
    
    /// Brief description/transcript snippet
    public var summary: String
    
    public init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        type: TimelineEntryType,
        speakerID: SpeakerID? = nil,
        speakerName: String? = nil,
        summary: String = ""
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.type = type
        self.speakerID = speakerID
        self.speakerName = speakerName
        self.summary = summary
    }
    
    /// Time range as CMTimeRange
    public var timeRange: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )
    }
}

/// Type of timeline segment
public enum TimelineEntryType: String, Codable, Sendable {
    case speech
    case silence
    case music
    case noise
    case overlapping
}

// MARK: - Export Types

/// Supported export formats
public enum ExportFormat: String, CaseIterable, Sendable {
    case json           // Full JSON export
    case edl            // Edit Decision List
    case fcpxml         // Final Cut Pro XML
    case srt            // SubRip subtitles
    case vtt            // WebVTT subtitles
    case csv            // Spreadsheet format
    case markers        // Marker list (Premiere/Resolve)
}

/// Export options
public struct ExportOptions: Sendable {
    /// Output format
    public let format: ExportFormat
    
    /// Filter by speaker
    public var speaker: String?
    
    /// Time range filter (seconds)
    public var startTime: TimeInterval?
    public var endTime: TimeInterval?
    
    /// Include emotions
    public var includeEmotions: Bool
    
    /// Include persons
    public var includePersons: Bool
    
    /// Frame rate for EDL/FCPXML
    public var frameRate: Double
    
    public init(
        format: ExportFormat,
        speaker: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil,
        includeEmotions: Bool = true,
        includePersons: Bool = true,
        frameRate: Double = 30.0
    ) {
        self.format = format
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.includeEmotions = includeEmotions
        self.includePersons = includePersons
        self.frameRate = frameRate
    }
}

// MARK: - Data Access Errors

/// Errors that can occur during data access
public enum DataAccessError: Error, LocalizedError, Sendable {
    case projectNotFound(String)
    case personNotFound(String)
    case speakerNotFound(String)
    case personNotNamed(String)
    case invalidTimeRange
    case ingestionInProgress
    case ingestionFailed(String)
    case databaseError(String)
    case noEmbedding
    case globalStoreError(String)
    case exportFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let path):
            return "Project not found at: \(path)"
        case .personNotFound(let id):
            return "Person not found: \(id)"
        case .speakerNotFound(let id):
            return "Speaker not found: \(id)"
        case .personNotNamed(let id):
            return "Person \(id) must be named before adding to global database"
        case .invalidTimeRange:
            return "Invalid time range specified"
        case .ingestionInProgress:
            return "Ingestion in progress. Use --partial for partial results."
        case .ingestionFailed(let reason):
            return "Ingestion failed: \(reason)"
        case .databaseError(let reason):
            return "Database error: \(reason)"
        case .noEmbedding:
            return "No embedding available for this person"
        case .globalStoreError(let reason):
            return "Global store error: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

// MARK: - Time Formatting Extensions

extension CMTime {
    /// Format as HH:MM:SS.mmm
    public func dataAccessFormatted() -> String {
        let totalSeconds = seconds
        guard totalSeconds.isFinite else { return "00:00.000" }
        
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let secs = Int(totalSeconds) % 60
        let millis = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, secs, millis)
        }
    }
}

extension CMTimeRange {
    /// Format as "START - END"
    public func dataAccessFormatted() -> String {
        "\(start.dataAccessFormatted()) - \(end.dataAccessFormatted())"
    }
}

extension TimeInterval {
    /// Format as human-readable duration
    public func durationFormatted() -> String {
        guard self.isFinite else { return "0:00" }
        
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Helper Extensions

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
