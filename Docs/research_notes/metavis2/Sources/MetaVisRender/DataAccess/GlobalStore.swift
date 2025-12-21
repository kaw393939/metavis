// GlobalStore.swift
// MetaVisRender
//
// Created for Sprint 09: Data Access Layer
// Shared identity database across all projects

import Foundation
import SQLite3

// MARK: - GlobalStore

/// Shared identity database across all projects
/// Stores known faces/voices for auto-matching in new projects
public actor GlobalStore {
    
    // MARK: - Singleton
    
    public static let shared = GlobalStore()
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private var isInitialized = false
    
    // MARK: - Initialization
    
    private init() {
        Task {
            try? await initialize()
        }
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    /// Initialize the global store
    public func initialize() async throws {
        guard !isInitialized else { return }
        
        try MetavisPaths.ensureDirectoriesExist()
        
        let dbPath = MetavisPaths.globalIdentitiesDB
        var dbHandle: OpaquePointer?
        
        let result = sqlite3_open(dbPath.path, &dbHandle)
        guard result == SQLITE_OK, let handle = dbHandle else {
            let message = String(cString: sqlite3_errmsg(dbHandle))
            throw DataAccessError.globalStoreError("Failed to open global database: \(message)")
        }
        
        self.db = handle
        
        try execute("""
            -- Known persons across all projects
            CREATE TABLE IF NOT EXISTS known_persons (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                embedding BLOB NOT NULL,
                voice_print BLOB,
                source_project TEXT NOT NULL,
                created_at TEXT NOT NULL,
                last_seen_at TEXT NOT NULL
            );
            
            -- Projects where each person appears
            CREATE TABLE IF NOT EXISTS person_projects (
                person_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                local_person_id TEXT NOT NULL,
                matched_at TEXT NOT NULL,
                confidence REAL,
                PRIMARY KEY (person_id, project_id),
                FOREIGN KEY (person_id) REFERENCES known_persons(id) ON DELETE CASCADE
            );
            
            -- Settings and preferences
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            
            -- Initialize default settings
            INSERT OR IGNORE INTO settings (key, value) VALUES 
                ('match_threshold', '0.7'),
                ('auto_match', 'true');
        """)
        
        isInitialized = true
    }
    
    // MARK: - Public API
    
    /// Add a person to the global identity database
    /// - Parameters:
    ///   - name: The person's name
    ///   - embedding: 512-dimensional face embedding
    ///   - voicePrint: Optional voice print data
    ///   - sourceProject: Project where this person was first identified
    /// - Returns: The global person ID
    public func addPerson(
        name: String,
        embedding: [Float],
        voicePrint: Data?,
        sourceProject: String
    ) async throws -> GlobalPersonID {
        try await ensureInitialized()
        
        let id = GlobalPersonID(UUID().uuidString)
        let now = ISO8601DateFormatter().string(from: Date())
        
        // Convert embedding to Data
        let embeddingData = embedding.withUnsafeBytes { buffer in
            Data(buffer)
        }
        
        try execute("""
            INSERT INTO known_persons (id, name, embedding, voice_print, source_project, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [id.rawValue, name, embeddingData, voicePrint as Any, sourceProject, now, now])
        
        return id
    }
    
    /// Find matching global identities for a face embedding
    /// - Parameters:
    ///   - embedding: The face embedding to match
    ///   - threshold: Minimum similarity threshold (default: 0.7)
    /// - Returns: Array of matches sorted by similarity
    public func findMatches(
        embedding: [Float],
        threshold: Float = 0.7
    ) async throws -> [GlobalMatch] {
        try await ensureInitialized()
        
        let rows = try query("SELECT id, name, embedding FROM known_persons")
        
        var matches: [GlobalMatch] = []
        
        for row in rows {
            guard let storedData = row["embedding"] as? Data else { continue }
            
            let storedEmbedding = storedData.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
            
            let similarity = cosineSimilarity(embedding, storedEmbedding)
            
            if similarity >= threshold {
                matches.append(GlobalMatch(
                    globalPersonID: GlobalPersonID(row["id"] as? String ?? ""),
                    name: row["name"] as? String ?? "Unknown",
                    similarity: similarity,
                    method: .faceEmbedding
                ))
            }
        }
        
        return matches.sorted { $0.similarity > $1.similarity }
    }
    
    /// Get all known persons
    public func allPersons() async throws -> [GlobalPerson] {
        try await ensureInitialized()
        
        let rows = try query("SELECT * FROM known_persons ORDER BY name")
        
        return rows.map { row in
            let embeddingData = row["embedding"] as? Data ?? Data()
            let embedding = embeddingData.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
            
            // Get projects for this person
            let personId = row["id"] as? String ?? ""
            let projectRows = (try? query(
                "SELECT project_id FROM person_projects WHERE person_id = ?",
                [personId]
            )) ?? []
            let projects = projectRows.compactMap { $0["project_id"] as? String }
            
            return GlobalPerson(
                id: GlobalPersonID(personId),
                name: row["name"] as? String ?? "Unknown",
                embedding: embedding,
                voicePrint: row["voice_print"] as? Data,
                sourceProject: row["source_project"] as? String ?? "",
                projects: projects,
                createdAt: parseDate(row["created_at"] as? String) ?? Date(),
                lastSeenAt: parseDate(row["last_seen_at"] as? String) ?? Date()
            )
        }
    }
    
    /// Get a specific global person
    public func person(id: GlobalPersonID) async throws -> GlobalPerson? {
        try await ensureInitialized()
        
        let rows = try query("SELECT * FROM known_persons WHERE id = ?", [id.rawValue])
        guard let row = rows.first else { return nil }
        
        let embeddingData = row["embedding"] as? Data ?? Data()
        let embedding = embeddingData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        
        // Get projects for this person
        let projectRows = try query(
            "SELECT project_id FROM person_projects WHERE person_id = ?",
            [id.rawValue]
        )
        let projects = projectRows.compactMap { $0["project_id"] as? String }
        
        return GlobalPerson(
            id: id,
            name: row["name"] as? String ?? "Unknown",
            embedding: embedding,
            voicePrint: row["voice_print"] as? Data,
            sourceProject: row["source_project"] as? String ?? "",
            projects: projects,
            createdAt: parseDate(row["created_at"] as? String) ?? Date(),
            lastSeenAt: parseDate(row["last_seen_at"] as? String) ?? Date()
        )
    }
    
    /// Update a global person's name
    public func updateName(id: GlobalPersonID, name: String) async throws {
        try await ensureInitialized()
        try execute("UPDATE known_persons SET name = ? WHERE id = ?", [name, id.rawValue])
    }
    
    /// Update the embedding for a global person (e.g., average with new observations)
    public func updateEmbedding(id: GlobalPersonID, embedding: [Float]) async throws {
        try await ensureInitialized()
        
        let embeddingData = embedding.withUnsafeBytes { buffer in
            Data(buffer)
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        try execute(
            "UPDATE known_persons SET embedding = ?, last_seen_at = ? WHERE id = ?",
            [embeddingData, now, id.rawValue]
        )
    }
    
    /// Record that a global person was found in a project
    public func recordProjectMatch(
        personID: GlobalPersonID,
        projectID: String,
        localPersonID: String,
        confidence: Float
    ) async throws {
        try await ensureInitialized()
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        try execute("""
            INSERT OR REPLACE INTO person_projects 
            (person_id, project_id, local_person_id, matched_at, confidence)
            VALUES (?, ?, ?, ?, ?)
        """, [personID.rawValue, projectID, localPersonID, now, confidence])
        
        // Update last_seen_at
        try execute(
            "UPDATE known_persons SET last_seen_at = ? WHERE id = ?",
            [now, personID.rawValue]
        )
    }
    
    /// Delete a global person
    public func deletePerson(id: GlobalPersonID) async throws {
        try await ensureInitialized()
        try execute("DELETE FROM known_persons WHERE id = ?", [id.rawValue])
    }
    
    /// Get a setting value
    public func getSetting(_ key: String) async throws -> String? {
        try await ensureInitialized()
        let rows = try query("SELECT value FROM settings WHERE key = ?", [key])
        return rows.first?["value"] as? String
    }
    
    /// Set a setting value
    public func setSetting(_ key: String, value: String) async throws {
        try await ensureInitialized()
        try execute(
            "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
            [key, value]
        )
    }
    
    /// Get the match threshold setting
    public func matchThreshold() async throws -> Float {
        let value = try await getSetting("match_threshold")
        return Float(value ?? "0.7") ?? 0.7
    }
    
    /// Check if auto-matching is enabled
    public func isAutoMatchEnabled() async throws -> Bool {
        let value = try await getSetting("auto_match")
        return value?.lowercased() == "true"
    }
    
    // MARK: - Private Helpers
    
    private func ensureInitialized() async throws {
        if !isInitialized {
            try await initialize()
        }
    }
    
    private func execute(_ sql: String, _ params: [Any] = []) throws {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DataAccessError.globalStoreError("Failed to prepare: \(message)")
        }
        
        defer { sqlite3_finalize(statement) }
        
        try bindParams(statement: statement, params: params)
        
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DataAccessError.globalStoreError("Failed to execute: \(message)")
        }
    }
    
    private func query(_ sql: String, _ params: [Any] = []) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw DataAccessError.globalStoreError("Failed to prepare: \(message)")
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
                    throw DataAccessError.globalStoreError("Unsupported parameter type")
                }
            }
        }
    }
    
    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
    
    /// Compute cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
}
