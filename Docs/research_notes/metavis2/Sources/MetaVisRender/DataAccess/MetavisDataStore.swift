// MetavisDataStore.swift
// MetaVisRender
//
// Created for Sprint 09: Data Access Layer
// Primary interface to all project data

import Foundation
import CoreMedia

// MARK: - MetavisDataStore Protocol

/// Primary interface to all project data
/// This protocol defines how to access ingested data from a metavis project
public protocol MetavisDataStore: Actor {
    
    // MARK: - Lifecycle
    
    /// Current ingestion state
    var state: IngestionState { get async }
    
    /// Block until ingestion complete (or throw on failure)
    func waitUntilReady() async throws
    
    /// Check if specific data type is available
    func isAvailable(_ dataType: DataType) async -> Bool
    
    // MARK: - Discovery
    
    /// Project metadata and statistics
    func projectInfo() async throws -> ProjectInfo
    
    /// All detected speakers (audio)
    func speakers() async throws -> [DataSpeaker]
    
    /// All detected persons (visual)
    func persons() async throws -> [DataPerson]
    
    /// Timeline overview with segment types
    func timeline() async throws -> [TimelineEntry]
    
    // MARK: - Entity Access
    
    /// Get speaker by ID
    func speaker(id: SpeakerID) async throws -> DataSpeaker?
    
    /// Get speaker by name
    func speaker(named: String) async throws -> DataSpeaker?
    
    /// Get person by ID
    func person(id: DataPersonID) async throws -> DataPerson?
    
    /// Get person by name
    func person(named: String) async throws -> DataPerson?
    
    // MARK: - Temporal Queries
    
    /// Get all segments, optionally within time range
    func segments(startTime: TimeInterval?, endTime: TimeInterval?) async throws -> [DataSegment]
    
    /// Get appearances of a person
    func appearances(of personID: DataPersonID) async throws -> [FaceAppearance]
    
    /// Get all data at a specific time
    func frameData(at time: TimeInterval) async throws -> FrameData
    
    // MARK: - Semantic Search
    
    /// Full-text search in transcript
    func search(text: String, options: SearchOptions) async throws -> [TranscriptMatch]
    
    /// Find moments matching filter
    func moments(filter: MomentFilter) async throws -> [DetectedMoment]
    
    /// Get complete clips (sentence-bounded segments)
    func clips(filter: ClipFilter) async throws -> [DataClip]
    
    /// Auto-detected highlights ranked by score
    func highlights(count: Int) async throws -> [DetectedMoment]
    
    // MARK: - Metadata Queries
    
    /// Find media by metadata criteria
    func findByMetadata(filter: MetadataFilter) async throws -> [MediaMetadataRecord]
    
    /// Get metadata for a specific media file
    func metadata(for sourcePath: String) async throws -> MediaMetadataRecord?
    
    /// Get all media metadata records
    func allMetadata() async throws -> [MediaMetadataRecord]
    
    // MARK: - Mutations
    
    /// Name a person or speaker
    func identify(_ entity: EntityID, name: String) async throws
    
    /// Link a speaker to a person
    func link(speaker: SpeakerID, to person: DataPersonID) async throws
    
    /// Add a tag to a time range
    func addTag(startTime: TimeInterval, endTime: TimeInterval, label: String, note: String?) async throws
    
    /// Get all tags
    func tags() async throws -> [DataTag]
    
    /// Delete a tag
    func deleteTag(id: Int) async throws
    
    // MARK: - Global Store
    
    /// Promote person to global identity database
    func promoteToGlobal(_ personID: DataPersonID) async throws -> GlobalPersonID
    
    /// Match project persons against global database
    func matchGlobalIdentities() async throws -> [GlobalMatch]
    
    // MARK: - Export
    
    /// Export data in specified format
    func export(options: ExportOptions) async throws -> String
}

// MARK: - Frame Data

/// All data available at a specific frame time
public struct FrameData: Codable, Sendable {
    /// The frame time in seconds
    public let time: TimeInterval
    
    /// Active segment at this time (if any)
    public var segment: DataSegment?
    
    /// Visible persons at this time
    public var appearances: [FaceAppearance]
    
    /// Active moments at this time
    public var moments: [DetectedMoment]
    
    /// Active tags at this time
    public var tags: [DataTag]
    
    public init(
        time: TimeInterval,
        segment: DataSegment? = nil,
        appearances: [FaceAppearance] = [],
        moments: [DetectedMoment] = [],
        tags: [DataTag] = []
    ) {
        self.time = time
        self.segment = segment
        self.appearances = appearances
        self.moments = moments
        self.tags = tags
    }
}

// MARK: - Default Implementations

extension MetavisDataStore {
    /// Get all segments (no time filter)
    public func allSegments() async throws -> [DataSegment] {
        try await segments(startTime: nil, endTime: nil)
    }
    
    /// Search with default options
    public func search(text: String) async throws -> [TranscriptMatch] {
        try await search(text: text, options: SearchOptions())
    }
    
    /// Get moments with default filter
    public func allMoments() async throws -> [DetectedMoment] {
        try await moments(filter: MomentFilter())
    }
    
    /// Get clips with default filter
    public func allClips() async throws -> [DataClip] {
        try await clips(filter: ClipFilter())
    }
    
    /// Get top 10 highlights
    public func topHighlights() async throws -> [DetectedMoment] {
        try await highlights(count: 10)
    }
}

// MARK: - Highlight

/// A highlight is just a high-scoring moment
public typealias Highlight = DetectedMoment

// MARK: - Data Store Factory

/// Factory for creating data stores
public enum DataStoreFactory {
    
    /// Create a data store for a project at the given path
    /// - Parameter projectPath: Path to the project directory or video file
    /// - Returns: A MetavisDataStore implementation
    public static func create(projectPath: URL) async throws -> any MetavisDataStore {
        try await ProjectStore(projectPath: projectPath)
    }
    
    /// Get the shared global identity store
    public static var globalStore: GlobalStore {
        GlobalStore.shared
    }
}

// MARK: - Store Paths

/// Standard paths for metavis data storage
public struct MetavisPaths {
    
    /// Base directory for all metavis data (~/.metavis)
    public static var baseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".metavis", isDirectory: true)
    }
    
    /// Directory for global data (~/.metavis/global)
    public static var globalDirectory: URL {
        baseDirectory.appendingPathComponent("global", isDirectory: true)
    }
    
    /// Path to global identities database
    public static var globalIdentitiesDB: URL {
        globalDirectory.appendingPathComponent("identities.db")
    }
    
    /// Directory for project data (~/.metavis/projects)
    public static var projectsDirectory: URL {
        baseDirectory.appendingPathComponent("projects", isDirectory: true)
    }
    
    /// Get project directory for a project ID
    public static func projectDirectory(projectID: String) -> URL {
        projectsDirectory.appendingPathComponent(projectID, isDirectory: true)
    }
    
    /// Get database path for a project
    public static func projectDatabase(projectID: String) -> URL {
        projectDirectory(projectID: projectID).appendingPathComponent("metavis.db")
    }
    
    /// Get the .metavis directory adjacent to a video file
    public static func adjacentDirectory(for videoURL: URL) -> URL {
        let videoName = videoURL.deletingPathExtension().lastPathComponent
        return videoURL.deletingLastPathComponent()
            .appendingPathComponent("\(videoName).metavis", isDirectory: true)
    }
    
    /// Ensure all base directories exist
    public static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        
        try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: globalDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
    }
}
