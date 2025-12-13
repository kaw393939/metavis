import Foundation

/// Defines the interface for a Semantic Search Engine (Long-Term Memory).
/// In the future, this will wrap a local Vector Store (e.g. USearch or SQLite-Vector).
public protocol VectorDB {
    
    /// Adds an embedding to the store.
    func add(embedding: [Float], id: String, metadata: [String: String]) async throws
    
    /// Searches for similar embeddings.
    /// Returns list of IDs and scores.
    func search(query: [Float], limit: Int) async throws -> [(id: String, score: Float)]
}

/// A placeholder in-memory implementation for development.
public actor InMemoryVectorDB: VectorDB {
    
    private struct Record {
        let embedding: [Float]
        let metadata: [String: String]
    }
    
    private var store: [String: Record] = [:]
    
    public init() {}
    
    public func add(embedding: [Float], id: String, metadata: [String : String]) async throws {
        store[id] = Record(embedding: embedding, metadata: metadata)
    }
    
    public func search(query: [Float], limit: Int) async throws -> [(id: String, score: Float)] {
        // Brute force cosine similarity
        let results = store.map { (id, record) -> (String, Float) in
            let score = cosineSimilarity(a: query, b: record.embedding)
            return (id, score)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        
        return Array(results)
    }
    
    private func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        // Simplified dot product
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        return dot / (sqrt(magA) * sqrt(magB) + 1e-6)
    }
}
