// ProjectStore.swift
// MetaVisRender
//
// Created for Sprint 09: Data Access Layer
// SQLite-backed project data store

import Foundation
import CoreMedia
import SQLite3

// MARK: - ProjectStore

/// SQLite-backed project data store implementation
public actor ProjectStore: MetavisDataStore {
    
    // MARK: - Properties
    
    private let projectPath: URL
    private let dbPath: URL
    private var db: OpaquePointer?
    private var currentState: IngestionState = .notStarted
    private let fileStore: FileStore
    
    // MARK: - Initialization
    
    public init(projectPath: URL) async throws {
        self.projectPath = projectPath
        
        // Determine database path
        if projectPath.hasDirectoryPath || projectPath.pathExtension.isEmpty {
            // Project directory - use internal DB
            self.dbPath = projectPath.appendingPathComponent("metavis.db")
        } else {
            // Video file - use adjacent .metavis directory
            let adjacentDir = MetavisPaths.adjacentDirectory(for: projectPath)
            self.dbPath = adjacentDir.appendingPathComponent("metavis.db")
        }
        
        self.fileStore = FileStore(projectPath: projectPath)
        
        try await openDatabase()
        try await initializeSchema()
        try await loadState()
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Database Setup
    
    private func openDatabase() async throws {
        // Ensure directory exists
        let dbDir = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        
        var dbHandle: OpaquePointer?
        let result = sqlite3_open(dbPath.path, &dbHandle)
        
        guard result == SQLITE_OK, let handle = dbHandle else {
            let message = String(cString: sqlite3_errmsg(dbHandle))
            throw DataAccessError.databaseError("Failed to open database: \(message)")
        }
        
        self.db = handle
        
        // Enable foreign keys
        try execute("PRAGMA foreign_keys = ON;")
        
        // Enable WAL mode for better concurrency
        try execute("PRAGMA journal_mode = WAL;")
    }
    
    private func initializeSchema() async throws {
        try execute("""
            -- Version tracking
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            );
            
            -- Ingestion state
            CREATE TABLE IF NOT EXISTS ingestion_state (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                state TEXT NOT NULL,
                phase TEXT,
                progress REAL,
                error TEXT,
                updated_at TEXT NOT NULL
            );
            
            -- Project info
            CREATE TABLE IF NOT EXISTS project_info (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                name TEXT NOT NULL,
                source_path TEXT NOT NULL,
                duration REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                modified_at TEXT NOT NULL
            );
            
            -- Segments (transcript + timing)
            CREATE TABLE IF NOT EXISTS segments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                speaker_id TEXT,
                transcript TEXT,
                confidence REAL DEFAULT 1.0,
                UNIQUE(start_time, end_time)
            );
            CREATE INDEX IF NOT EXISTS idx_segments_time ON segments(start_time, end_time);
            CREATE INDEX IF NOT EXISTS idx_segments_speaker ON segments(speaker_id);
            
            -- Speakers (audio entities)
            CREATE TABLE IF NOT EXISTS speakers (
                id TEXT PRIMARY KEY,
                name TEXT,
                aliases TEXT DEFAULT '[]',
                linked_person_id TEXT,
                total_duration REAL DEFAULT 0,
                segment_count INTEGER DEFAULT 0,
                voice_print BLOB
            );
            
            -- Persons (visual entities)
            CREATE TABLE IF NOT EXISTS persons (
                id TEXT PRIMARY KEY,
                name TEXT,
                linked_speaker_id TEXT,
                global_person_id TEXT,
                embedding_path TEXT,
                thumbnail_path TEXT,
                appearance_count INTEGER DEFAULT 0,
                total_screen_time REAL DEFAULT 0,
                created_at TEXT NOT NULL
            );
            
            -- Face appearances
            CREATE TABLE IF NOT EXISTS appearances (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                person_id TEXT NOT NULL,
                frame_time REAL NOT NULL,
                bbox_x REAL NOT NULL,
                bbox_y REAL NOT NULL,
                bbox_w REAL NOT NULL,
                bbox_h REAL NOT NULL,
                confidence REAL DEFAULT 1.0,
                emotion TEXT,
                emotion_score REAL,
                FOREIGN KEY (person_id) REFERENCES persons(id)
            );
            CREATE INDEX IF NOT EXISTS idx_appearances_time ON appearances(frame_time);
            CREATE INDEX IF NOT EXISTS idx_appearances_person ON appearances(person_id);
            
            -- Segment emotions
            CREATE TABLE IF NOT EXISTS segment_emotions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                segment_id INTEGER NOT NULL,
                emotion TEXT NOT NULL,
                score REAL NOT NULL,
                FOREIGN KEY (segment_id) REFERENCES segments(id)
            );
            CREATE INDEX IF NOT EXISTS idx_segment_emotions ON segment_emotions(segment_id);
            
            -- Segment visible persons
            CREATE TABLE IF NOT EXISTS segment_persons (
                segment_id INTEGER NOT NULL,
                person_id TEXT NOT NULL,
                PRIMARY KEY (segment_id, person_id),
                FOREIGN KEY (segment_id) REFERENCES segments(id),
                FOREIGN KEY (person_id) REFERENCES persons(id)
            );
            
            -- User tags
            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                label TEXT NOT NULL,
                note TEXT,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_tags_time ON tags(start_time, end_time);
            
            -- Auto-detected moments
            CREATE TABLE IF NOT EXISTS moments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time REAL NOT NULL,
                end_time REAL NOT NULL,
                type TEXT NOT NULL,
                score REAL NOT NULL,
                description TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_moments_time ON moments(start_time, end_time);
            CREATE INDEX IF NOT EXISTS idx_moments_score ON moments(score DESC);
            
            -- Moment speakers
            CREATE TABLE IF NOT EXISTS moment_speakers (
                moment_id INTEGER NOT NULL,
                speaker_id TEXT NOT NULL,
                PRIMARY KEY (moment_id, speaker_id),
                FOREIGN KEY (moment_id) REFERENCES moments(id)
            );
            
            -- Moment persons
            CREATE TABLE IF NOT EXISTS moment_persons (
                moment_id INTEGER NOT NULL,
                person_id TEXT NOT NULL,
                PRIMARY KEY (moment_id, person_id),
                FOREIGN KEY (moment_id) REFERENCES moments(id)
            );
            
            -- Media metadata (EXIF/XMP)
            CREATE TABLE IF NOT EXISTS media_metadata (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_path TEXT NOT NULL UNIQUE,
                iso INTEGER,
                aperture REAL,
                shutter_speed REAL,
                focal_length REAL,
                white_balance TEXT,
                exposure_compensation REAL,
                camera_make TEXT,
                camera_model TEXT,
                lens_make TEXT,
                lens_model TEXT,
                camera_serial TEXT,
                lens_serial TEXT,
                captured_at TEXT,
                timezone TEXT,
                gps_latitude REAL,
                gps_longitude REAL,
                gps_altitude REAL,
                orientation INTEGER,
                rating INTEGER,
                keywords TEXT DEFAULT '[]',
                description TEXT,
                copyright TEXT,
                creator TEXT,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_metadata_camera ON media_metadata(camera_make, camera_model);
            CREATE INDEX IF NOT EXISTS idx_metadata_rating ON media_metadata(rating);
            CREATE INDEX IF NOT EXISTS idx_metadata_captured ON media_metadata(captured_at);
            
            -- Data availability tracking
            CREATE TABLE IF NOT EXISTS data_availability (
                data_type TEXT PRIMARY KEY,
                available INTEGER NOT NULL DEFAULT 0,
                updated_at TEXT NOT NULL
            );
        """)
        
        // Create FTS5 virtual table for full-text search
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS segments_fts USING fts5(
                transcript,
                content=segments,
                content_rowid=id
            );
        """)
        
        // Create triggers to keep FTS in sync
        try execute("""
            CREATE TRIGGER IF NOT EXISTS segments_ai AFTER INSERT ON segments BEGIN
                INSERT INTO segments_fts(rowid, transcript) VALUES (new.id, new.transcript);
            END;
            
            CREATE TRIGGER IF NOT EXISTS segments_ad AFTER DELETE ON segments BEGIN
                INSERT INTO segments_fts(segments_fts, rowid, transcript) 
                VALUES('delete', old.id, old.transcript);
            END;
            
            CREATE TRIGGER IF NOT EXISTS segments_au AFTER UPDATE ON segments BEGIN
                INSERT INTO segments_fts(segments_fts, rowid, transcript) 
                VALUES('delete', old.id, old.transcript);
                INSERT INTO segments_fts(rowid, transcript) VALUES (new.id, new.transcript);
            END;
        """)
    }
    
    private func loadState() async throws {
        let result = try query("SELECT state, phase, progress, error FROM ingestion_state WHERE id = 1")
        
        guard let row = result.first else {
            currentState = .notStarted
            return
        }
        
        let stateStr = row["state"] as? String ?? "notStarted"
        
        switch stateStr {
        case "ready":
            currentState = .ready
        case "failed":
            let error = row["error"] as? String ?? "Unknown error"
            currentState = .failed(error)
        case "inProgress":
            let phaseStr = row["phase"] as? String ?? IngestionPhase.extractingAudio.rawValue
            let phase = IngestionPhase(rawValue: phaseStr) ?? .extractingAudio
            let progress = row["progress"] as? Double ?? 0
            currentState = .inProgress(IngestionProgress(phase: phase, progress: progress))
        default:
            currentState = .notStarted
        }
    }
    
    // MARK: - MetavisDataStore Protocol
    
    public var state: IngestionState {
        get async {
            currentState
        }
    }
    
    public func waitUntilReady() async throws {
        // In a real implementation, this would poll or use notifications
        // For now, just check current state
        switch currentState {
        case .ready:
            return
        case .failed(let error):
            throw DataAccessError.ingestionFailed(error)
        case .notStarted:
            throw DataAccessError.ingestionFailed("Ingestion has not started")
        case .inProgress:
            throw DataAccessError.ingestionInProgress
        }
    }
    
    public func isAvailable(_ dataType: DataType) async -> Bool {
        let result = try? query(
            "SELECT available FROM data_availability WHERE data_type = ?",
            [dataType.rawValue]
        )
        return (result?.first?["available"] as? Int ?? 0) == 1
    }
    
    // MARK: - Discovery
    
    public func projectInfo() async throws -> ProjectInfo {
        let result = try query("SELECT * FROM project_info WHERE id = 1")
        
        guard let row = result.first else {
            // Return default info
            return ProjectInfo(
                name: projectPath.lastPathComponent,
                sourcePath: projectPath.path,
                duration: 0,
                state: currentState
            )
        }
        
        // Get counts
        let speakerCount = try scalarInt("SELECT COUNT(*) FROM speakers")
        let namedSpeakerCount = try scalarInt("SELECT COUNT(*) FROM speakers WHERE name IS NOT NULL")
        let personCount = try scalarInt("SELECT COUNT(*) FROM persons")
        let namedPersonCount = try scalarInt("SELECT COUNT(*) FROM persons WHERE name IS NOT NULL")
        let segmentCount = try scalarInt("SELECT COUNT(*) FROM segments")
        let momentCount = try scalarInt("SELECT COUNT(*) FROM moments")
        let tagCount = try scalarInt("SELECT COUNT(*) FROM tags")
        
        return ProjectInfo(
            name: row["name"] as? String ?? projectPath.lastPathComponent,
            sourcePath: row["source_path"] as? String ?? projectPath.path,
            duration: row["duration"] as? Double ?? 0,
            state: currentState,
            createdAt: parseDate(row["created_at"] as? String) ?? Date(),
            modifiedAt: parseDate(row["modified_at"] as? String) ?? Date(),
            speakerCount: speakerCount,
            namedSpeakerCount: namedSpeakerCount,
            personCount: personCount,
            namedPersonCount: namedPersonCount,
            segmentCount: segmentCount,
            momentCount: momentCount,
            tagCount: tagCount
        )
    }
    
    public func speakers() async throws -> [DataSpeaker] {
        let result = try query("SELECT * FROM speakers ORDER BY id")
        return result.map { row in
            DataSpeaker(
                id: SpeakerID(row["id"] as? String ?? ""),
                name: row["name"] as? String,
                aliases: parseJSONArray(row["aliases"] as? String),
                linkedPersonID: (row["linked_person_id"] as? String).map { DataPersonID($0) },
                totalDuration: row["total_duration"] as? Double ?? 0,
                segmentCount: row["segment_count"] as? Int ?? 0,
                voicePrint: row["voice_print"] as? Data
            )
        }
    }
    
    public func persons() async throws -> [DataPerson] {
        let result = try query("SELECT * FROM persons ORDER BY id")
        return result.map { row in
            DataPerson(
                id: DataPersonID(row["id"] as? String ?? ""),
                name: row["name"] as? String,
                linkedSpeakerID: (row["linked_speaker_id"] as? String).map { SpeakerID($0) },
                globalPersonID: (row["global_person_id"] as? String).map { GlobalPersonID($0) },
                embeddingPath: (row["embedding_path"] as? String).flatMap { URL(fileURLWithPath: $0) },
                thumbnailPath: (row["thumbnail_path"] as? String).flatMap { URL(fileURLWithPath: $0) },
                appearanceCount: row["appearance_count"] as? Int ?? 0,
                totalScreenTime: row["total_screen_time"] as? Double ?? 0,
                createdAt: parseDate(row["created_at"] as? String) ?? Date()
            )
        }
    }
    
    public func timeline() async throws -> [TimelineEntry] {
        // Build timeline from segments and detect gaps
        let segments = try await allSegments()
        var entries: [TimelineEntry] = []
        var lastEndTime: TimeInterval = 0
        
        for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
            // Add silence gap if there's a gap
            if segment.startTime > lastEndTime + 0.5 {
                entries.append(TimelineEntry(
                    startTime: lastEndTime,
                    endTime: segment.startTime,
                    type: .silence,
                    summary: ""
                ))
            }
            
            // Add speech entry
            let speakerName = segment.speakerID.flatMap { id in
                try? self.speakerName(for: id)
            }
            
            entries.append(TimelineEntry(
                startTime: segment.startTime,
                endTime: segment.endTime,
                type: .speech,
                speakerID: segment.speakerID,
                speakerName: speakerName,
                summary: String(segment.transcript.prefix(100))
            ))
            
            lastEndTime = segment.endTime
        }
        
        return entries
    }
    
    // MARK: - Entity Access
    
    public func speaker(id: SpeakerID) async throws -> DataSpeaker? {
        let result = try query("SELECT * FROM speakers WHERE id = ?", [id.rawValue])
        guard let row = result.first else { return nil }
        
        return DataSpeaker(
            id: id,
            name: row["name"] as? String,
            aliases: parseJSONArray(row["aliases"] as? String),
            linkedPersonID: (row["linked_person_id"] as? String).map { DataPersonID($0) },
            totalDuration: row["total_duration"] as? Double ?? 0,
            segmentCount: row["segment_count"] as? Int ?? 0,
            voicePrint: row["voice_print"] as? Data
        )
    }
    
    public func speaker(named: String) async throws -> DataSpeaker? {
        let result = try query(
            "SELECT * FROM speakers WHERE name = ? OR aliases LIKE ?",
            [named, "%\"\(named)\"%"]
        )
        guard let row = result.first else { return nil }
        
        return DataSpeaker(
            id: SpeakerID(row["id"] as? String ?? ""),
            name: row["name"] as? String,
            aliases: parseJSONArray(row["aliases"] as? String),
            linkedPersonID: (row["linked_person_id"] as? String).map { DataPersonID($0) },
            totalDuration: row["total_duration"] as? Double ?? 0,
            segmentCount: row["segment_count"] as? Int ?? 0,
            voicePrint: row["voice_print"] as? Data
        )
    }
    
    public func person(id: DataPersonID) async throws -> DataPerson? {
        let result = try query("SELECT * FROM persons WHERE id = ?", [id.rawValue])
        guard let row = result.first else { return nil }
        
        return DataPerson(
            id: id,
            name: row["name"] as? String,
            linkedSpeakerID: (row["linked_speaker_id"] as? String).map { SpeakerID($0) },
            globalPersonID: (row["global_person_id"] as? String).map { GlobalPersonID($0) },
            embeddingPath: (row["embedding_path"] as? String).flatMap { URL(fileURLWithPath: $0) },
            thumbnailPath: (row["thumbnail_path"] as? String).flatMap { URL(fileURLWithPath: $0) },
            appearanceCount: row["appearance_count"] as? Int ?? 0,
            totalScreenTime: row["total_screen_time"] as? Double ?? 0,
            createdAt: parseDate(row["created_at"] as? String) ?? Date()
        )
    }
    
    public func person(named: String) async throws -> DataPerson? {
        let result = try query("SELECT * FROM persons WHERE name = ?", [named])
        guard let row = result.first else { return nil }
        
        return DataPerson(
            id: DataPersonID(row["id"] as? String ?? ""),
            name: row["name"] as? String,
            linkedSpeakerID: (row["linked_speaker_id"] as? String).map { SpeakerID($0) },
            globalPersonID: (row["global_person_id"] as? String).map { GlobalPersonID($0) },
            embeddingPath: (row["embedding_path"] as? String).flatMap { URL(fileURLWithPath: $0) },
            thumbnailPath: (row["thumbnail_path"] as? String).flatMap { URL(fileURLWithPath: $0) },
            appearanceCount: row["appearance_count"] as? Int ?? 0,
            totalScreenTime: row["total_screen_time"] as? Double ?? 0,
            createdAt: parseDate(row["created_at"] as? String) ?? Date()
        )
    }
    
    // MARK: - Temporal Queries
    
    public func segments(startTime: TimeInterval?, endTime: TimeInterval?) async throws -> [DataSegment] {
        var sql = "SELECT * FROM segments"
        var params: [Any] = []
        var conditions: [String] = []
        
        if let start = startTime {
            conditions.append("end_time >= ?")
            params.append(start)
        }
        if let end = endTime {
            conditions.append("start_time <= ?")
            params.append(end)
        }
        
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY start_time"
        
        let result = try query(sql, params)
        
        return try result.map { row in
            let segmentId = row["id"] as? Int ?? 0
            let emotions = try loadSegmentEmotions(segmentId: segmentId)
            let visiblePersons = try loadSegmentPersons(segmentId: segmentId)
            
            return DataSegment(
                id: segmentId,
                startTime: row["start_time"] as? Double ?? 0,
                endTime: row["end_time"] as? Double ?? 0,
                speakerID: (row["speaker_id"] as? String).map { SpeakerID($0) },
                transcript: row["transcript"] as? String ?? "",
                confidence: Float(row["confidence"] as? Double ?? 1.0),
                emotions: emotions,
                visiblePersons: visiblePersons
            )
        }
    }
    
    public func appearances(of personID: DataPersonID) async throws -> [FaceAppearance] {
        let result = try query(
            "SELECT * FROM appearances WHERE person_id = ? ORDER BY frame_time",
            [personID.rawValue]
        )
        
        return result.map { row in
            var emotion: DataEmotionScore?
            if let emotionStr = row["emotion"] as? String,
               let dataEmotion = DataEmotion(rawValue: emotionStr),
               let score = row["emotion_score"] as? Double {
                emotion = DataEmotionScore(emotion: dataEmotion, score: Float(score))
            }
            
            return FaceAppearance(
                id: row["id"] as? Int ?? 0,
                personID: personID,
                frameTime: row["frame_time"] as? Double ?? 0,
                boundingBox: CGRect(
                    x: row["bbox_x"] as? Double ?? 0,
                    y: row["bbox_y"] as? Double ?? 0,
                    width: row["bbox_w"] as? Double ?? 0,
                    height: row["bbox_h"] as? Double ?? 0
                ),
                confidence: Float(row["confidence"] as? Double ?? 1.0),
                emotion: emotion
            )
        }
    }
    
    public func frameData(at time: TimeInterval) async throws -> FrameData {
        // Get active segment
        let segmentResult = try query(
            "SELECT * FROM segments WHERE start_time <= ? AND end_time >= ? LIMIT 1",
            [time, time]
        )
        
        var segment: DataSegment?
        if let row = segmentResult.first {
            let segmentId = row["id"] as? Int ?? 0
            let emotions = try loadSegmentEmotions(segmentId: segmentId)
            let visiblePersons = try loadSegmentPersons(segmentId: segmentId)
            
            segment = DataSegment(
                id: segmentId,
                startTime: row["start_time"] as? Double ?? 0,
                endTime: row["end_time"] as? Double ?? 0,
                speakerID: (row["speaker_id"] as? String).map { SpeakerID($0) },
                transcript: row["transcript"] as? String ?? "",
                confidence: Float(row["confidence"] as? Double ?? 1.0),
                emotions: emotions,
                visiblePersons: visiblePersons
            )
        }
        
        // Get appearances near this time (within 0.5s)
        let appearanceResult = try query(
            "SELECT * FROM appearances WHERE frame_time >= ? AND frame_time <= ?",
            [time - 0.5, time + 0.5]
        )
        
        let appearances = appearanceResult.map { row in
            FaceAppearance(
                id: row["id"] as? Int ?? 0,
                personID: DataPersonID(row["person_id"] as? String ?? ""),
                frameTime: row["frame_time"] as? Double ?? 0,
                boundingBox: CGRect(
                    x: row["bbox_x"] as? Double ?? 0,
                    y: row["bbox_y"] as? Double ?? 0,
                    width: row["bbox_w"] as? Double ?? 0,
                    height: row["bbox_h"] as? Double ?? 0
                ),
                confidence: Float(row["confidence"] as? Double ?? 1.0),
                emotion: nil
            )
        }
        
        // Get active moments
        let momentResult = try query(
            "SELECT * FROM moments WHERE start_time <= ? AND end_time >= ?",
            [time, time]
        )
        let moments = try momentResult.map { row in try parseMoment(row) }
        
        // Get active tags
        let tagResult = try query(
            "SELECT * FROM tags WHERE start_time <= ? AND end_time >= ?",
            [time, time]
        )
        let tags = tagResult.map { row in parseTag(row) }
        
        return FrameData(
            time: time,
            segment: segment,
            appearances: appearances,
            moments: moments,
            tags: tags
        )
    }
    
    // MARK: - Semantic Search
    
    public func search(text: String, options: SearchOptions) async throws -> [TranscriptMatch] {
        // Build FTS5 query
        let ftsQuery = options.useRegex ? text : text.split(separator: " ").map { "\"\($0)\"" }.joined(separator: " OR ")
        
        var sql = """
            SELECT s.id, s.start_time, s.end_time, s.speaker_id, s.transcript,
                   highlight(segments_fts, 0, '<mark>', '</mark>') as highlighted
            FROM segments_fts
            JOIN segments s ON segments_fts.rowid = s.id
            WHERE segments_fts MATCH ?
        """
        var params: [Any] = [ftsQuery]
        
        if let speaker = options.speaker {
            // Check if it's a speaker ID or name
            sql += " AND (s.speaker_id = ? OR s.speaker_id IN (SELECT id FROM speakers WHERE name = ?))"
            params.append(speaker)
            params.append(speaker)
        }
        
        if let startTime = options.startTime {
            sql += " AND s.end_time >= ?"
            params.append(startTime)
        }
        
        if let endTime = options.endTime {
            sql += " AND s.start_time <= ?"
            params.append(endTime)
        }
        
        sql += " ORDER BY s.start_time"
        
        if let limit = options.limit {
            sql += " LIMIT ?"
            params.append(limit)
        }
        
        let result = try query(sql, params)
        
        return result.map { row in
            let speakerId = row["speaker_id"] as? String
            let speakerName = speakerId.flatMap { id in try? self.speakerName(for: SpeakerID(id)) }
            
            return TranscriptMatch(
                segmentID: row["id"] as? Int ?? 0,
                startTime: row["start_time"] as? Double ?? 0,
                endTime: row["end_time"] as? Double ?? 0,
                speakerID: speakerId.map { SpeakerID($0) },
                speakerName: speakerName,
                transcript: row["transcript"] as? String ?? "",
                highlighted: row["highlighted"] as? String ?? ""
            )
        }
    }
    
    public func moments(filter: MomentFilter) async throws -> [DetectedMoment] {
        var sql = "SELECT * FROM moments WHERE score >= ?"
        var params: [Any] = [filter.minScore]
        
        if let type = filter.type {
            sql += " AND type = ?"
            params.append(type.rawValue)
        }
        
        if let startTime = filter.startTime {
            sql += " AND end_time >= ?"
            params.append(startTime)
        }
        
        if let endTime = filter.endTime {
            sql += " AND start_time <= ?"
            params.append(endTime)
        }
        
        sql += " ORDER BY score DESC LIMIT ?"
        params.append(filter.limit)
        
        let result = try query(sql, params)
        return try result.map { row in try parseMoment(row) }
    }
    
    public func clips(filter: ClipFilter) async throws -> [DataClip] {
        var sql = "SELECT * FROM segments WHERE 1=1"
        var params: [Any] = []
        
        if let speaker = filter.speaker {
            sql += " AND (speaker_id = ? OR speaker_id IN (SELECT id FROM speakers WHERE name = ?))"
            params.append(speaker)
            params.append(speaker)
        }
        
        if let minDuration = filter.minDuration {
            sql += " AND (end_time - start_time) >= ?"
            params.append(minDuration)
        }
        
        if let maxDuration = filter.maxDuration {
            sql += " AND (end_time - start_time) <= ?"
            params.append(maxDuration)
        }
        
        if let startTime = filter.startTime {
            sql += " AND end_time >= ?"
            params.append(startTime)
        }
        
        if let endTime = filter.endTime {
            sql += " AND start_time <= ?"
            params.append(endTime)
        }
        
        sql += " ORDER BY start_time LIMIT ?"
        params.append(filter.limit)
        
        let result = try query(sql, params)
        
        return result.map { row in
            let speakerId = row["speaker_id"] as? String
            let speakerName = speakerId.flatMap { id in try? self.speakerName(for: SpeakerID(id)) }
            let transcript = row["transcript"] as? String ?? ""
            
            return DataClip(
                startTime: row["start_time"] as? Double ?? 0,
                endTime: row["end_time"] as? Double ?? 0,
                speakerID: speakerId.map { SpeakerID($0) },
                speakerName: speakerName,
                transcript: transcript,
                isCompleteSentence: transcript.hasSuffix(".") || transcript.hasSuffix("?") || transcript.hasSuffix("!"),
                dominantEmotion: nil,
                highlightScore: 0
            )
        }
    }
    
    public func highlights(count: Int) async throws -> [DetectedMoment] {
        let result = try query(
            "SELECT * FROM moments ORDER BY score DESC LIMIT ?",
            [count]
        )
        return try result.map { row in try parseMoment(row) }
    }
    
    // MARK: - Metadata Queries
    
    public func findByMetadata(filter: MetadataFilter) async throws -> [MediaMetadataRecord] {
        var sql = "SELECT * FROM media_metadata WHERE 1=1"
        var params: [Any] = []
        
        if let camera = filter.camera {
            sql += " AND (camera_make LIKE ? OR camera_model LIKE ?)"
            params.append("%\(camera)%")
            params.append("%\(camera)%")
        }
        
        if let lens = filter.lens {
            sql += " AND (lens_make LIKE ? OR lens_model LIKE ?)"
            params.append("%\(lens)%")
            params.append("%\(lens)%")
        }
        
        if let isoMin = filter.isoMin {
            sql += " AND iso >= ?"
            params.append(isoMin)
        }
        
        if let isoMax = filter.isoMax {
            sql += " AND iso <= ?"
            params.append(isoMax)
        }
        
        if let apertureMin = filter.apertureMin {
            sql += " AND aperture >= ?"
            params.append(apertureMin)
        }
        
        if let apertureMax = filter.apertureMax {
            sql += " AND aperture <= ?"
            params.append(apertureMax)
        }
        
        if let dateFrom = filter.dateFrom {
            sql += " AND captured_at >= ?"
            params.append(ISO8601DateFormatter().string(from: dateFrom))
        }
        
        if let dateTo = filter.dateTo {
            sql += " AND captured_at <= ?"
            params.append(ISO8601DateFormatter().string(from: dateTo))
        }
        
        if let ratingMin = filter.ratingMin {
            sql += " AND rating >= ?"
            params.append(ratingMin)
        }
        
        if let keyword = filter.keyword {
            sql += " AND keywords LIKE ?"
            params.append("%\(keyword)%")
        }
        
        if let creator = filter.creator {
            sql += " AND creator LIKE ?"
            params.append("%\(creator)%")
        }
        
        sql += " LIMIT ?"
        params.append(filter.limit)
        
        let result = try query(sql, params)
        return result.map { row in parseMetadata(row) }
    }
    
    public func metadata(for sourcePath: String) async throws -> MediaMetadataRecord? {
        let result = try query(
            "SELECT * FROM media_metadata WHERE source_path = ?",
            [sourcePath]
        )
        guard let row = result.first else { return nil }
        return parseMetadata(row)
    }
    
    public func allMetadata() async throws -> [MediaMetadataRecord] {
        let result = try query("SELECT * FROM media_metadata")
        return result.map { row in parseMetadata(row) }
    }
    
    // MARK: - Mutations
    
    public func identify(_ entity: EntityID, name: String) async throws {
        switch entity {
        case .speaker(let id):
            try execute("UPDATE speakers SET name = ? WHERE id = ?", [name, id.rawValue])
        case .person(let id):
            try execute("UPDATE persons SET name = ? WHERE id = ?", [name, id.rawValue])
        }
    }
    
    public func link(speaker: SpeakerID, to person: DataPersonID) async throws {
        try execute("UPDATE speakers SET linked_person_id = ? WHERE id = ?", [person.rawValue, speaker.rawValue])
        try execute("UPDATE persons SET linked_speaker_id = ? WHERE id = ?", [speaker.rawValue, person.rawValue])
    }
    
    public func addTag(startTime: TimeInterval, endTime: TimeInterval, label: String, note: String?) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try execute(
            "INSERT INTO tags (start_time, end_time, label, note, created_at) VALUES (?, ?, ?, ?, ?)",
            [startTime, endTime, label, note as Any, now]
        )
    }
    
    public func tags() async throws -> [DataTag] {
        let result = try query("SELECT * FROM tags ORDER BY start_time")
        return result.map { row in parseTag(row) }
    }
    
    public func deleteTag(id: Int) async throws {
        try execute("DELETE FROM tags WHERE id = ?", [id])
    }
    
    // MARK: - Global Store
    
    public func promoteToGlobal(_ personID: DataPersonID) async throws -> GlobalPersonID {
        guard let person = try await person(id: personID) else {
            throw DataAccessError.personNotFound(personID.rawValue)
        }
        
        guard let name = person.name else {
            throw DataAccessError.personNotNamed(personID.rawValue)
        }
        
        // Load embedding
        guard let embeddingPath = person.embeddingPath else {
            throw DataAccessError.noEmbedding
        }
        
        let embeddingData = try Data(contentsOf: embeddingPath)
        let embedding = embeddingData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        
        let projectName = projectPath.lastPathComponent
        let globalID = try await GlobalStore.shared.addPerson(
            name: name,
            embedding: embedding,
            voicePrint: nil,
            sourceProject: projectName
        )
        
        // Update local person with global ID
        try execute(
            "UPDATE persons SET global_person_id = ? WHERE id = ?",
            [globalID.rawValue, personID.rawValue]
        )
        
        return globalID
    }
    
    public func matchGlobalIdentities() async throws -> [GlobalMatch] {
        let persons = try await persons()
        var matches: [GlobalMatch] = []
        
        for person in persons where person.globalPersonID == nil {
            guard let embeddingPath = person.embeddingPath else { continue }
            
            let embeddingData = try Data(contentsOf: embeddingPath)
            let embedding = embeddingData.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
            
            let personMatches = try await GlobalStore.shared.findMatches(embedding: embedding)
            
            if let bestMatch = personMatches.first {
                // Update local person with global ID
                try execute(
                    "UPDATE persons SET global_person_id = ?, name = COALESCE(name, ?) WHERE id = ?",
                    [bestMatch.globalPersonID.rawValue, bestMatch.name, person.id.rawValue]
                )
                matches.append(bestMatch)
            }
        }
        
        return matches
    }
    
    // MARK: - Export
    
    public func export(options: ExportOptions) async throws -> String {
        switch options.format {
        case .json:
            return try await exportJSON(options: options)
        case .edl:
            return try await exportEDL(options: options)
        case .srt:
            return try await exportSRT(options: options)
        case .vtt:
            return try await exportVTT(options: options)
        case .csv:
            return try await exportCSV(options: options)
        case .fcpxml:
            return try await exportFCPXML(options: options)
        case .markers:
            return try await exportMarkers(options: options)
        }
    }
    
    // MARK: - Ingestion API (for use by ingestion pipeline)
    
    /// Update the ingestion state
    public func updateState(_ state: IngestionState) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        
        switch state {
        case .notStarted:
            try execute(
                "INSERT OR REPLACE INTO ingestion_state (id, state, updated_at) VALUES (1, 'notStarted', ?)",
                [now]
            )
        case .inProgress(let progress):
            try execute(
                "INSERT OR REPLACE INTO ingestion_state (id, state, phase, progress, updated_at) VALUES (1, 'inProgress', ?, ?, ?)",
                [progress.phase.rawValue, progress.progress, now]
            )
        case .ready:
            try execute(
                "INSERT OR REPLACE INTO ingestion_state (id, state, updated_at) VALUES (1, 'ready', ?)",
                [now]
            )
        case .failed(let error):
            try execute(
                "INSERT OR REPLACE INTO ingestion_state (id, state, error, updated_at) VALUES (1, 'failed', ?, ?)",
                [error, now]
            )
        }
        
        currentState = state
    }
    
    /// Insert a segment
    public func insertSegment(
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerID: String?,
        transcript: String,
        confidence: Float
    ) throws -> Int {
        try execute(
            "INSERT INTO segments (start_time, end_time, speaker_id, transcript, confidence) VALUES (?, ?, ?, ?, ?)",
            [startTime, endTime, speakerID as Any, transcript, confidence]
        )
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    /// Insert a speaker
    public func insertSpeaker(id: String, name: String? = nil) throws {
        try execute(
            "INSERT OR IGNORE INTO speakers (id, name) VALUES (?, ?)",
            [id, name as Any]
        )
    }
    
    /// Insert a person
    public func insertPerson(
        id: String,
        name: String? = nil,
        embeddingPath: String? = nil,
        thumbnailPath: String? = nil
    ) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try execute(
            "INSERT OR IGNORE INTO persons (id, name, embedding_path, thumbnail_path, created_at) VALUES (?, ?, ?, ?, ?)",
            [id, name as Any, embeddingPath as Any, thumbnailPath as Any, now]
        )
    }
    
    /// Insert an appearance
    public func insertAppearance(
        personID: String,
        frameTime: TimeInterval,
        boundingBox: CGRect,
        confidence: Float
    ) throws -> Int {
        try execute(
            "INSERT INTO appearances (person_id, frame_time, bbox_x, bbox_y, bbox_w, bbox_h, confidence) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [personID, frameTime, boundingBox.origin.x, boundingBox.origin.y, boundingBox.width, boundingBox.height, confidence]
        )
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    /// Insert a moment
    public func insertMoment(
        startTime: TimeInterval,
        endTime: TimeInterval,
        type: MomentType,
        score: Float,
        description: String
    ) throws -> Int {
        try execute(
            "INSERT INTO moments (start_time, end_time, type, score, description) VALUES (?, ?, ?, ?, ?)",
            [startTime, endTime, type.rawValue, score, description]
        )
        return Int(sqlite3_last_insert_rowid(db))
    }
    
    /// Set data availability
    public func setDataAvailable(_ dataType: DataType, available: Bool) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try execute(
            "INSERT OR REPLACE INTO data_availability (data_type, available, updated_at) VALUES (?, ?, ?)",
            [dataType.rawValue, available ? 1 : 0, now]
        )
    }
    
    // MARK: - Private Helpers
    
    private func execute(_ sql: String, _ params: [Any] = []) throws {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DataAccessError.databaseError("Failed to prepare: \(message)")
        }
        
        defer { sqlite3_finalize(statement) }
        
        try bindParams(statement: statement, params: params)
        
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DataAccessError.databaseError("Failed to execute: \(message)")
        }
    }
    
    private func query(_ sql: String, _ params: [Any] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DataAccessError.databaseError("Failed to prepare: \(message)")
        }
        
        defer { sqlite3_finalize(statement) }
        
        try bindParams(statement: statement, params: params)
        
        var results: [[String: Any]] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(statement)
            
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, i))
                let type = sqlite3_column_type(statement, i)
                
                switch type {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[name] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(statement, i)
                    let length = sqlite3_column_bytes(statement, i)
                    if let bytes = bytes {
                        row[name] = Data(bytes: bytes, count: Int(length))
                    }
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    break
                }
            }
            
            results.append(row)
        }
        
        return results
    }
    
    private func scalarInt(_ sql: String, _ params: [Any] = []) throws -> Int {
        let result = try query(sql, params)
        guard let row = result.first, let value = row.values.first as? Int else {
            return 0
        }
        return value
    }
    
    private func bindParams(statement: OpaquePointer?, params: [Any]) throws {
        for (index, param) in params.enumerated() {
            let i = Int32(index + 1)
            
            switch param {
            case let value as Int:
                sqlite3_bind_int64(statement, i, Int64(value))
            case let value as Double:
                sqlite3_bind_double(statement, i, value)
            case let value as Float:
                sqlite3_bind_double(statement, i, Double(value))
            case let value as String:
                sqlite3_bind_text(statement, i, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let value as Data:
                _ = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, i, buffer.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case is NSNull:
                sqlite3_bind_null(statement, i)
            default:
                if case Optional<Any>.none = param {
                    sqlite3_bind_null(statement, i)
                } else {
                    throw DataAccessError.databaseError("Unsupported parameter type")
                }
            }
        }
    }
    
    private func speakerName(for id: SpeakerID) throws -> String? {
        let result = try query("SELECT name FROM speakers WHERE id = ?", [id.rawValue])
        return result.first?["name"] as? String
    }
    
    private func loadSegmentEmotions(segmentId: Int) throws -> [DataEmotionScore] {
        let result = try query(
            "SELECT emotion, score FROM segment_emotions WHERE segment_id = ?",
            [segmentId]
        )
        return result.compactMap { row in
            guard let emotionStr = row["emotion"] as? String,
                  let emotion = DataEmotion(rawValue: emotionStr),
                  let score = row["score"] as? Double else {
                return nil
            }
            return DataEmotionScore(emotion: emotion, score: Float(score))
        }
    }
    
    private func loadSegmentPersons(segmentId: Int) throws -> [DataPersonID] {
        let result = try query(
            "SELECT person_id FROM segment_persons WHERE segment_id = ?",
            [segmentId]
        )
        return result.compactMap { row in
            guard let id = row["person_id"] as? String else { return nil }
            return DataPersonID(id)
        }
    }
    
    private func parseMoment(_ row: [String: Any]) throws -> DetectedMoment {
        let momentId = row["id"] as? Int ?? 0
        
        // Load moment speakers
        let speakerResult = try query(
            "SELECT speaker_id FROM moment_speakers WHERE moment_id = ?",
            [momentId]
        )
        let speakers = speakerResult.compactMap { r in
            (r["speaker_id"] as? String).map { SpeakerID($0) }
        }
        
        // Load moment persons
        let personResult = try query(
            "SELECT person_id FROM moment_persons WHERE moment_id = ?",
            [momentId]
        )
        let persons = personResult.compactMap { r in
            (r["person_id"] as? String).map { DataPersonID($0) }
        }
        
        return DetectedMoment(
            id: momentId,
            startTime: row["start_time"] as? Double ?? 0,
            endTime: row["end_time"] as? Double ?? 0,
            type: MomentType(rawValue: row["type"] as? String ?? "") ?? .emotionalPeak,
            score: Float(row["score"] as? Double ?? 0),
            description: row["description"] as? String ?? "",
            speakers: speakers,
            persons: persons
        )
    }
    
    private func parseTag(_ row: [String: Any]) -> DataTag {
        DataTag(
            id: row["id"] as? Int ?? 0,
            startTime: row["start_time"] as? Double ?? 0,
            endTime: row["end_time"] as? Double ?? 0,
            label: row["label"] as? String ?? "",
            note: row["note"] as? String,
            createdAt: parseDate(row["created_at"] as? String) ?? Date()
        )
    }
    
    private func parseMetadata(_ row: [String: Any]) -> MediaMetadataRecord {
        MediaMetadataRecord(
            id: row["id"] as? Int ?? 0,
            sourcePath: row["source_path"] as? String ?? "",
            iso: row["iso"] as? Int,
            aperture: row["aperture"] as? Double,
            shutterSpeed: row["shutter_speed"] as? Double,
            focalLength: row["focal_length"] as? Double,
            whiteBalance: row["white_balance"] as? String,
            exposureCompensation: row["exposure_compensation"] as? Double,
            cameraMake: row["camera_make"] as? String,
            cameraModel: row["camera_model"] as? String,
            lensMake: row["lens_make"] as? String,
            lensModel: row["lens_model"] as? String,
            cameraSerial: row["camera_serial"] as? String,
            lensSerial: row["lens_serial"] as? String,
            capturedAt: parseDate(row["captured_at"] as? String),
            timezone: row["timezone"] as? String,
            gpsLatitude: row["gps_latitude"] as? Double,
            gpsLongitude: row["gps_longitude"] as? Double,
            gpsAltitude: row["gps_altitude"] as? Double,
            orientation: row["orientation"] as? Int,
            rating: row["rating"] as? Int,
            keywords: parseJSONArray(row["keywords"] as? String),
            metadataDescription: row["description"] as? String,
            copyright: row["copyright"] as? String,
            creator: row["creator"] as? String
        )
    }
    
    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
    
    private func parseJSONArray(_ string: String?) -> [String] {
        guard let string = string,
              let data = string.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }
    
    // MARK: - Export Implementations
    
    private func exportJSON(options: ExportOptions) async throws -> String {
        let info = try await projectInfo()
        let speakers = try await speakers()
        let persons = try await persons()
        let segments = try await allSegments()
        let moments = try await allMoments()
        let tagsList = try await tags()
        
        let export: [String: Any] = [
            "project": [
                "name": info.name,
                "duration": info.duration,
                "createdAt": ISO8601DateFormatter().string(from: info.createdAt)
            ],
            "speakers": speakers.map { [
                "id": $0.id.rawValue,
                "name": $0.name as Any,
                "duration": $0.totalDuration
            ]},
            "persons": persons.map { [
                "id": $0.id.rawValue,
                "name": $0.name as Any,
                "appearances": $0.appearanceCount
            ]},
            "segments": segments.map { [
                "start": $0.startTime,
                "end": $0.endTime,
                "speaker": $0.speakerID?.rawValue as Any,
                "transcript": $0.transcript
            ]},
            "moments": moments.map { [
                "start": $0.startTime,
                "end": $0.endTime,
                "type": $0.type.rawValue,
                "score": $0.score,
                "description": $0.description
            ]},
            "tags": tagsList.map { [
                "start": $0.startTime,
                "end": $0.endTime,
                "label": $0.label,
                "note": $0.note as Any
            ]}
        ]
        
        let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    private func exportEDL(options: ExportOptions) async throws -> String {
        let filter = ClipFilter(speaker: options.speaker, startTime: options.startTime, endTime: options.endTime)
        let clips = try await clips(filter: filter)
        
        var edl = "TITLE: MetaVis Export\nFCM: NON-DROP FRAME\n\n"
        
        for (index, clip) in clips.enumerated() {
            let eventNum = String(format: "%03d", index + 1)
            let srcIn = timecodeString(clip.startTime, frameRate: options.frameRate)
            let srcOut = timecodeString(clip.endTime, frameRate: options.frameRate)
            let recIn = srcIn
            let recOut = srcOut
            
            edl += "\(eventNum)  AX       V     C        \(srcIn) \(srcOut) \(recIn) \(recOut)\n"
            edl += "* FROM CLIP NAME: \(clip.speakerName ?? "Unknown")\n"
            edl += "* COMMENT: \(clip.transcript.prefix(100))\n\n"
        }
        
        return edl
    }
    
    private func exportSRT(options: ExportOptions) async throws -> String {
        let filter = ClipFilter(speaker: options.speaker, startTime: options.startTime, endTime: options.endTime)
        let clips = try await clips(filter: filter)
        
        var srt = ""
        
        for (index, clip) in clips.enumerated() {
            let startTC = srtTimestamp(clip.startTime)
            let endTC = srtTimestamp(clip.endTime)
            
            srt += "\(index + 1)\n"
            srt += "\(startTC) --> \(endTC)\n"
            if let name = clip.speakerName {
                srt += "[\(name)] "
            }
            srt += "\(clip.transcript)\n\n"
        }
        
        return srt
    }
    
    private func exportVTT(options: ExportOptions) async throws -> String {
        let filter = ClipFilter(speaker: options.speaker, startTime: options.startTime, endTime: options.endTime)
        let clips = try await clips(filter: filter)
        
        var vtt = "WEBVTT\n\n"
        
        for clip in clips {
            let startTC = vttTimestamp(clip.startTime)
            let endTC = vttTimestamp(clip.endTime)
            
            vtt += "\(startTC) --> \(endTC)\n"
            if let name = clip.speakerName {
                vtt += "<v \(name)>"
            }
            vtt += "\(clip.transcript)\n\n"
        }
        
        return vtt
    }
    
    private func exportCSV(options: ExportOptions) async throws -> String {
        let filter = ClipFilter(speaker: options.speaker, startTime: options.startTime, endTime: options.endTime)
        let clips = try await clips(filter: filter)
        
        var csv = "Start,End,Duration,Speaker,Transcript\n"
        
        for clip in clips {
            let transcript = clip.transcript.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(clip.startTime)\",\"\(clip.endTime)\",\"\(clip.duration)\",\"\(clip.speakerName ?? "")\",\"\(transcript)\"\n"
        }
        
        return csv
    }
    
    private func exportFCPXML(options: ExportOptions) async throws -> String {
        // Simplified FCPXML export
        let info = try await projectInfo()
        
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
            <resources>
                <format id="r1" name="FFVideoFormat1080p30" frameDuration="100/3000s" width="1920" height="1080"/>
            </resources>
            <library>
                <event name="\(info.name)">
                    <project name="\(info.name)">
                        <sequence format="r1">
                            <spine>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
    }
    
    private func exportMarkers(options: ExportOptions) async throws -> String {
        let moments = try await highlights(count: 50)
        
        var markers = "Name\tStart\tDuration\tType\tNotes\n"
        
        for moment in moments {
            markers += "\(moment.type.rawValue)\t\(moment.startTime)\t\(moment.duration)\t\(moment.type.rawValue)\t\(moment.description)\n"
        }
        
        return markers
    }
    
    private func timecodeString(_ seconds: TimeInterval, frameRate: Double) -> String {
        let totalFrames = Int(seconds * frameRate)
        let frames = totalFrames % Int(frameRate)
        let secs = (totalFrames / Int(frameRate)) % 60
        let mins = (totalFrames / Int(frameRate) / 60) % 60
        let hours = totalFrames / Int(frameRate) / 3600
        
        return String(format: "%02d:%02d:%02d:%02d", hours, mins, secs, frames)
    }
    
    private func srtTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, mins, secs, millis)
    }
    
    private func vttTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d.%03d", hours, mins, secs, millis)
    }
}
