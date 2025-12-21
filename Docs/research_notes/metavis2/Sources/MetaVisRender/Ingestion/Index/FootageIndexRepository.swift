// Sources/MetaVisRender/Ingestion/Index/FootageIndexRepository.swift
// Sprint 03: JSON persistence for indexed footage

import Foundation

// Note: Uses FootageIndexRecord from Data/FootageIndexRecord.swift

// MARK: - Footage Index Repository

/// Persists and retrieves FootageIndexRecords
public actor FootageIndexRepository {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Directory for storing index files
        public let storageDirectory: URL
        /// Maximum age for cached records (seconds)
        public let maxCacheAge: TimeInterval
        
        public init(
            storageDirectory: URL? = nil,
            maxCacheAge: TimeInterval = 86400 * 7  // 1 week
        ) {
            self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory
            self.maxCacheAge = maxCacheAge
        }
        
        public static let `default` = Config()
        
        private static var defaultStorageDirectory: URL {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return appSupport.appendingPathComponent("MetaVisRender/FootageIndex", isDirectory: true)
        }
    }
    
    private let config: Config
    private var cache: [UUID: IndexedFootageRecord] = [:]
    
    public init(config: Config = .default) throws {
        self.config = config
        
        // Create storage directory if needed
        try FileManager.default.createDirectory(
            at: config.storageDirectory,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Public API
    
    /// Save a record to the index
    public func save(_ record: IndexedFootageRecord) async throws {
        cache[record.id] = record
        
        let url = recordURL(for: record.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(record)
        try data.write(to: url)
    }
    
    /// Load a record by ID
    public func load(id: UUID) async throws -> IndexedFootageRecord? {
        // Check cache first
        if let cached = cache[id] {
            return cached
        }
        
        // Load from disk
        let url = recordURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let record = try decoder.decode(IndexedFootageRecord.self, from: data)
        cache[id] = record
        
        return record
    }
    
    /// Find record by source file path
    public func find(byPath path: String) async throws -> IndexedFootageRecord? {
        // Check cache
        if let cached = cache.values.first(where: { $0.sourcePath == path }) {
            return cached
        }
        
        // Load index to find by path
        let records = try await listAll()
        return records.first { $0.sourcePath == path }
    }
    
    /// Delete a record
    public func delete(id: UUID) async throws {
        cache.removeValue(forKey: id)
        
        let url = recordURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    /// List all records
    public func listAll() async throws -> [IndexedFootageRecord] {
        let files = try FileManager.default.contentsOfDirectory(
            at: config.storageDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        
        var records: [IndexedFootageRecord] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let record = try decoder.decode(IndexedFootageRecord.self, from: data)
                records.append(record)
                cache[record.id] = record
            } catch {
                // Skip invalid files
                continue
            }
        }
        
        return records.sorted { $0.analyzedAt > $1.analyzedAt }
    }
    
    /// Find stale records (source file changed)
    public func findStaleRecords() async throws -> [IndexedFootageRecord] {
        let records = try await listAll()
        
        return records.filter { record in
            guard FileManager.default.fileExists(atPath: record.sourcePath) else {
                return true  // Source deleted
            }
            
            // Check modification date
            if let attrs = try? FileManager.default.attributesOfItem(atPath: record.sourcePath),
               let modDate = attrs[.modificationDate] as? Date {
                return modDate > record.analyzedAt
            }
            
            return false
        }
    }
    
    /// Clean up old cache entries
    public func cleanCache() async throws {
        let cutoff = Date().addingTimeInterval(-config.maxCacheAge)
        let records = try await listAll()
        
        for record in records {
            if record.analyzedAt < cutoff {
                try await delete(id: record.id)
            }
        }
    }
    
    /// Get storage statistics
    public func getStatistics() async throws -> IndexStatistics {
        let records = try await listAll()
        
        let totalSize = records.reduce(Int64(0)) { $0 + ($1.mediaProfile?.fileSize ?? 0) }
        let totalDuration = records.reduce(0.0) { $0 + ($1.mediaProfile?.duration ?? 0) }
        
        let byStatus = Dictionary(grouping: records, by: { $0.status })
        
        return IndexStatistics(
            recordCount: records.count,
            totalSourceSize: totalSize,
            totalDuration: totalDuration,
            completeCount: byStatus[.complete]?.count ?? 0,
            pendingCount: byStatus[.pending]?.count ?? 0,
            failedCount: byStatus[.failed]?.count ?? 0,
            staleCount: byStatus[.stale]?.count ?? 0
        )
    }
    
    // MARK: - Private
    
    private func recordURL(for id: UUID) -> URL {
        config.storageDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}

// MARK: - Indexed Footage Record

/// Complete indexed record for a media file - used by FootageIndexRepository
public struct IndexedFootageRecord: Codable, Sendable, Identifiable {
    // MARK: - Identity
    public let id: UUID
    public let sourcePath: String
    public let analyzedAt: Date
    public let version: String
    
    // MARK: - Source Metadata
    public let mediaProfile: EnhancedMediaProfile?
    
    // MARK: - Analysis Results
    public let sceneDetection: SceneDetectionResult?
    public let audioMetrics: AudioMetrics?
    public let transcript: Transcript?
    public let diarization: DiarizationResult?
    
    // MARK: - Generated Outputs
    public let captionsPath: String?
    public let thumbnailPaths: [String]
    
    // MARK: - Quality
    public let qualityScore: Float
    public let issues: [String]
    
    // MARK: - Status
    public let status: IndexStatus
    public let processingTime: Double
    public let error: String?
    
    public init(
        id: UUID = UUID(),
        sourcePath: String,
        analyzedAt: Date = Date(),
        version: String = "1.0",
        mediaProfile: EnhancedMediaProfile? = nil,
        sceneDetection: SceneDetectionResult? = nil,
        audioMetrics: AudioMetrics? = nil,
        transcript: Transcript? = nil,
        diarization: DiarizationResult? = nil,
        captionsPath: String? = nil,
        thumbnailPaths: [String] = [],
        qualityScore: Float = 0,
        issues: [String] = [],
        status: IndexStatus = .pending,
        processingTime: Double = 0,
        error: String? = nil
    ) {
        self.id = id
        self.sourcePath = sourcePath
        self.analyzedAt = analyzedAt
        self.version = version
        self.mediaProfile = mediaProfile
        self.sceneDetection = sceneDetection
        self.audioMetrics = audioMetrics
        self.transcript = transcript
        self.diarization = diarization
        self.captionsPath = captionsPath
        self.thumbnailPaths = thumbnailPaths
        self.qualityScore = qualityScore
        self.issues = issues
        self.status = status
        self.processingTime = processingTime
        self.error = error
    }
}

/// Index record status
public enum IndexStatus: String, Codable, Sendable {
    case pending
    case processing
    case complete
    case failed
    case stale
}

/// Index statistics
public struct IndexStatistics: Codable, Sendable {
    public let recordCount: Int
    public let totalSourceSize: Int64
    public let totalDuration: Double
    public let completeCount: Int
    public let pendingCount: Int
    public let failedCount: Int
    public let staleCount: Int
    
    public var formattedSourceSize: String {
        ByteCountFormatter.string(fromByteCount: totalSourceSize, countStyle: .file)
    }
    
    public var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
