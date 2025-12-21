import Foundation
import GRDB

/// Manages the SQLite database for the Perception stack.
public class DatabaseManager {
    public let dbWriter: any DatabaseWriter
    
    /// Initializes a generic DatabaseManager.
    /// - Parameter dbWriter: The GRDB DatabaseWriter (DatabaseQueue or DatabasePool).
    public init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }
    
    /// Initializes the DatabaseManager with an on-disk database at the specified path.
    public static func open(atPath path: String) throws -> DatabaseManager {
        let dbQueue = try DatabaseQueue(path: path)
        return try DatabaseManager(dbWriter: dbQueue)
    }
    
    /// Initializes an in-memory database for testing.
    public static func inMemory() throws -> DatabaseManager {
        let dbQueue = try DatabaseQueue()
        return try DatabaseManager(dbWriter: dbQueue)
    }
    
    /// The database migrator defining the schema.
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1") { db in
            // Table: Assets
            try db.create(table: "assets") { t in
                t.column("id", .text).primaryKey() // UUID string
                t.column("path", .text).notNull()
                t.column("tier", .integer).notNull().defaults(to: 0)
                t.column("tech_specs", .text) // JSON
            }
            
            // Table: Entities
            try db.create(table: "entities") { t in
                t.column("id", .text).primaryKey() // UUID string
                t.column("type", .text).notNull()
                t.column("name", .text)
                t.column("embedding", .blob)
            }
            
            // Table: TimeRanges
            try db.create(table: "time_ranges") { t in
                t.column("id", .text).primaryKey() // UUID string
                t.column("asset_id", .text).notNull().references("assets", onDelete: .cascade)
                t.column("start_time", .double).notNull()
                t.column("end_time", .double).notNull()
                t.column("type", .text).notNull()
                t.column("entity_id", .text).references("entities", onDelete: .setNull)
                t.column("data", .text) // JSON
            }
        }
        
        return migrator
    }
    
    /// Registers custom SQL functions.
    private func registerFunctions(_ db: Database) throws {
        // Register cosine_distance(blob, blob) -> float
        let cosineDistance = DatabaseFunction("cosine_distance", argumentCount: 2, pure: true) { dbValues in
            guard let blob1 = Data.fromDatabaseValue(dbValues[0]),
                  let blob2 = Data.fromDatabaseValue(dbValues[1]) else {
                return 1.0 // Maximum distance if null
            }
            
            do {
                let v1 = try VectorUtils.deserialize(blob1)
                let v2 = try VectorUtils.deserialize(blob2)
                return VectorUtils.cosineDistance(v1, v2)
            } catch {
                return 1.0 // Return max distance on error
            }
        }
        db.add(function: cosineDistance)
    }
    
    /// Performs a semantic search for entities similar to the query embedding.
    /// - Parameters:
    ///   - embedding: The query vector.
    ///   - limit: Maximum number of results.
    /// - Returns: List of (EntityID, Distance).
    public func search(embedding: [Float], limit: Int = 5) async throws -> [(id: String, distance: Float)] {
        let queryBlob = try VectorUtils.serialize(embedding)
        
        return try await dbWriter.read { db in
            try self.registerFunctions(db) // Ensure function is available
            
            let sql = """
            SELECT id, cosine_distance(embedding, ?) AS distance
            FROM entities
            WHERE embedding IS NOT NULL
            ORDER BY distance ASC
            LIMIT ?
            """
            
            let rows = try Row.fetchCursor(db, sql: sql, arguments: [queryBlob, limit])
            var results: [(id: String, distance: Float)] = []
            
            while let row = try rows.next() {
                if let id: String = row["id"], let dist: Float = row["distance"] {
                    results.append((id: id, distance: dist))
                }
            }
            return results
        }
    }
}
