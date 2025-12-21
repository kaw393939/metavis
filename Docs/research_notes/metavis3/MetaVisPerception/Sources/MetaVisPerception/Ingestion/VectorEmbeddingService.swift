import Foundation

/// Service to convert text into vector embeddings.
public protocol VectorEmbeddingService {
    /// Generates an embedding vector for the given text.
    /// - Parameter text: The text to analyze.
    /// - Returns: A normalized float array (dimension depends on model, e.g., 384 or 1536).
    func embed(text: String) async throws -> [Float]
}

/// Mock service for testing vector pipeline without an LLM.
public class MockVectorEmbeddingService: VectorEmbeddingService {
    private let dimension: Int
    
    public init(dimension: Int = 384) {
        self.dimension = dimension
    }
    
    public func embed(text: String) async throws -> [Float] {
        // Deterministic pseudo-random generation based on text hash
        // This ensures the same text gets the same vector (basic consistency)
        var hasher = Hasher()
        hasher.combine(text)
        let seed = hasher.finalize()
        var rng = LinearCongruentialGenerator(seed: UInt64(abs(seed)))
        
        var vector = (0..<dimension).map { _ in Float(rng.next()) }
        
        // Normalize
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            vector = vector.map { $0 / magnitude }
        }
        
        return vector
    }
}

// Simple LCG for deterministic random numbers
fileprivate struct LinearCongruentialGenerator: RandomNumberGenerator {
    var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}
