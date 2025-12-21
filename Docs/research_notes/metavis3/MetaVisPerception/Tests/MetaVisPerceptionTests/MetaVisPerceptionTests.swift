import XCTest
@testable import MetaVisPerception
import GRDB

final class MetaVisPerceptionTests: XCTestCase {
    
    func testDatabaseSchema() throws {
        // Given
        let dbManager = try DatabaseManager.inMemory()
        
        // When
        try dbManager.dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO assets (id, path, tier) VALUES (?, ?, ?)
            """, arguments: ["test-asset-1", "/tmp/video.mp4", 1])
            
            try db.execute(sql: """
                INSERT INTO entities (id, type, name) VALUES (?, ?, ?)
            """, arguments: ["entity-1", "Person", "Keith"])
            
            try db.execute(sql: """
                INSERT INTO time_ranges (id, asset_id, start_time, end_time, type, entity_id) 
                VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: ["tr-1", "test-asset-1", 0.0, 5.0, "Face", "entity-1"])
        }
        
        // Then
        let count = try dbManager.dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_ranges")
        }
        XCTAssertEqual(count, 1)
    }
    
    func testFullIngestPipeline() async throws {
        // Given
        let dbManager = try DatabaseManager.inMemory()
        
        // Use Mock Services (default)
        let coordinator = IngestCoordinator(database: dbManager)
        
        // When
        let assetID = try await coordinator.ingest(file: "/tmp/simulation_test.mov")
        
        // Then
        XCTAssertNotNil(assetID)
        
        try await dbManager.dbWriter.read { db in
            // 1. Verify Asset
            let assetExists = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM assets WHERE id = ?)", arguments: [assetID])
            XCTAssertEqual(assetExists, true, "Asset should exist")
            
            // 2. Verify TimeRanges (Mock Whisper returns 3 segments)
            let timeRangesCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_ranges WHERE asset_id = ?", arguments: [assetID])
            XCTAssertEqual(timeRangesCount, 3, "Should have 3 time ranges")
            
            // 3. Verify Entities (Speech Segments)
            let entitiesCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entities WHERE type = 'SpeechSegment'")
            XCTAssertEqual(entitiesCount, 3, "Should have 3 speech entities")
            
            // 4. Verify Data Links
            let linkedEntityCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM time_ranges tr
                JOIN entities e ON tr.entity_id = e.id
                WHERE tr.asset_id = ? AND e.type = 'SpeechSegment'
            """, arguments: [assetID])
            XCTAssertEqual(linkedEntityCount, 3, "TimeRanges should be linked to Speech Entities")
        }
    }
}
