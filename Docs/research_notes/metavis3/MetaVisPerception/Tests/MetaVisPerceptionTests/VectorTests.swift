import XCTest
@testable import MetaVisPerception
import GRDB

final class VectorTests: XCTestCase {
    
    func testCosineDistance() {
        // Orthogonal vectors (90 degrees) -> Distance 1.0
        let v1: [Float] = [1, 0]
        let v2: [Float] = [0, 1]
        XCTAssertEqual(VectorUtils.cosineDistance(v1, v2), 1.0, accuracy: 0.0001)
        
        // Parallel vectors (0 degrees) -> Distance 0.0
        let v3: [Float] = [1, 1]
        let v4: [Float] = [2, 2]
        XCTAssertEqual(VectorUtils.cosineDistance(v3, v4), 0.0, accuracy: 0.0001)
        
        // Opposite vectors (180 degrees) -> Distance 2.0
        let v5: [Float] = [1, 0]
        let v6: [Float] = [-1, 0]
        XCTAssertEqual(VectorUtils.cosineDistance(v5, v6), 2.0, accuracy: 0.0001)
    }
    
    func testVectorSearch() async throws {
        // Given
        let dbManager = try DatabaseManager.inMemory()
        
        // target: [1, 0]
        let target: [Float] = [1, 0]
        
        // dist 0.0
        let vec1: [Float] = [1, 0]
        // dist 1.0
        let vec2: [Float] = [0, 1]
        // dist 2.0
        let vec3: [Float] = [-1, 0] 
        
        try await dbManager.dbWriter.write { db in
            try db.execute(sql: "INSERT INTO entities (id, type, name, embedding) VALUES (?, ?, ?, ?)",
                          arguments: ["id-1", "Match", "Exact", try VectorUtils.serialize(vec1)])
            try db.execute(sql: "INSERT INTO entities (id, type, name, embedding) VALUES (?, ?, ?, ?)",
                          arguments: ["id-2", "Orthogonal", "Perp", try VectorUtils.serialize(vec2)])
            try db.execute(sql: "INSERT INTO entities (id, type, name, embedding) VALUES (?, ?, ?, ?)",
                          arguments: ["id-3", "Opposite", "Anti", try VectorUtils.serialize(vec3)])
        }
        
        // When
        let results = try await dbManager.search(embedding: target, limit: 3)
        
        // Then
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].id, "id-1")
        XCTAssertEqual(results[0].distance, 0.0, accuracy: 0.01)
        
        XCTAssertEqual(results[1].id, "id-2")
        XCTAssertEqual(results[1].distance, 1.0, accuracy: 0.01)
        
        XCTAssertEqual(results[2].id, "id-3")
        XCTAssertEqual(results[2].distance, 2.0, accuracy: 0.01)
    }
}
