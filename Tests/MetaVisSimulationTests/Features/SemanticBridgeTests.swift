import XCTest
import MetaVisCore
import CoreImage
@testable import MetaVisPerception

final class SemanticBridgeTests: XCTestCase {
    
    func testSemanticFrameEncoding() throws {
        let subject = DetectedSubject(rect: CGRect(x:0, y:0, width:0.5, height:0.5), label: "Person", attributes: ["mood": "happy"])
        let frame = SemanticFrame(timestamp: 1.0, subjects: [subject], contextTags: ["Test"])
        
        // Ensure Codable works (critical for LLM JSON serialization)
        let data = try JSONEncoder().encode(frame)
        let decoded = try JSONDecoder().decode(SemanticFrame.self, from: data)
        
        XCTAssertEqual(decoded.timestamp, 1.0)
        XCTAssertEqual(decoded.subjects.first?.label, "Person")
        XCTAssertEqual(decoded.subjects.first?.attributes["mood"], "happy")
    }
    
    func testVisualAggregator() async throws {
        // Needs a pixel buffer
        let width = 100
        let height = 100
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        
        guard let pb = pixelBuffer else {
            XCTFail("Failed to create pixel buffer")
            return
        }
        
        let aggregator = VisualContextAggregator()
        let frame = try await aggregator.analyze(pixelBuffer: pb, at: 0.5)
        
        // Assert basic structure
        XCTAssertEqual(frame.timestamp, 0.5)
        // Subjects might be empty on blank buffer, that's fine.
        // We checking pipeline integrity.
        XCTAssertNotNil(frame.contextTags)
    }
    
    func testVectorDBStub() async throws {
        let db = InMemoryVectorDB()
        let embeddingA: [Float] = [1.0, 0.0, 0.0]
        let embeddingB: [Float] = [0.0, 1.0, 0.0]
        
        try await db.add(embedding: embeddingA, id: "A", metadata: [:])
        try await db.add(embedding: embeddingB, id: "B", metadata: [:])
        
        let results = try await db.search(query: [0.9, 0.1, 0.0], limit: 1)
        XCTAssertEqual(results.first?.id, "A")
    }
}
