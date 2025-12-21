import Foundation

/// Utilities for vector operations.
public struct VectorUtils {
    
    /// Calculates the cosine distance between two float arrays.
    /// Cosine Distance = 1 - Cosine Similarity.
    /// Range: [0, 2] (0 = identical, 1 = orthogonal, 2 = opposite).
    /// - Parameters:
    ///   - v1: First vector.
    ///   - v2: Second vector.
    /// - Returns: The cosine distance, or 1.0 if invalid/zero magnitude.
    public static func cosineDistance(_ v1: [Float], _ v2: [Float]) -> Float {
        guard v1.count == v2.count, !v1.isEmpty else { return 1.0 }
        
        var dot: Float = 0.0
        var mag1: Float = 0.0
        var mag2: Float = 0.0
        
        for i in 0..<v1.count {
            let val1 = v1[i]
            let val2 = v2[i]
            dot += val1 * val2
            mag1 += val1 * val1
            mag2 += val2 * val2
        }
        
        if mag1 == 0 || mag2 == 0 { return 1.0 }
        
        let similarity = dot / (sqrt(mag1) * sqrt(mag2))
        return 1.0 - similarity
    }
    
    /// Serializes a float array to a Data blob (JSON) for storage.
    public static func serialize(_ vector: [Float]) throws -> Data {
        return try JSONEncoder().encode(vector)
    }
    
    /// Deserializes a Data blob (JSON) to a float array.
    public static func deserialize(_ data: Data) throws -> [Float] {
        return try JSONDecoder().decode([Float].self, from: data)
    }
}
