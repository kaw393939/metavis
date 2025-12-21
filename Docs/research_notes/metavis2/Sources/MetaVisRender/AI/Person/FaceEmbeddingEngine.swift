// FaceEmbeddingEngine.swift
// MetaVisRender
//
// Created for Sprint 06: Person Intelligence
// Extracts face identity embeddings using CoreML

import Foundation
import CoreGraphics
import CoreImage
import Accelerate
import Vision

// MARK: - Face Embedding Engine

/// Extracts face identity embeddings for person recognition.
/// Uses a lightweight face recognition model to generate 512-dimensional
/// identity vectors that can be compared for similarity.
public actor FaceEmbeddingEngine {
    
    // MARK: - Types
    
    public enum Error: Swift.Error, Equatable {
        case modelLoadFailed
        case embeddingExtractionFailed
        case invalidFaceImage
        case faceTooSmall
        case faceAlignmentFailed
        case dimensionMismatch
    }
    
    public struct Config: Sendable {
        /// Minimum face size (as fraction of image)
        public let minFaceSize: Float
        
        /// Embedding dimension
        public let embeddingDimension: Int
        
        /// Whether to perform face alignment before embedding
        public let performAlignment: Bool
        
        /// Target size for face crops
        public let targetFaceSize: Int
        
        public init(
            minFaceSize: Float = 0.02,
            embeddingDimension: Int = 512,
            performAlignment: Bool = true,
            targetFaceSize: Int = 112
        ) {
            self.minFaceSize = minFaceSize
            self.embeddingDimension = embeddingDimension
            self.performAlignment = performAlignment
            self.targetFaceSize = targetFaceSize
        }
        
        public static let `default` = Config()
        
        /// Fast mode with less processing
        public static let fast = Config(
            minFaceSize: 0.05,
            performAlignment: false
        )
        
        /// High quality mode
        public static let quality = Config(
            minFaceSize: 0.01,
            performAlignment: true,
            targetFaceSize: 160
        )
    }
    
    // MARK: - Properties
    
    private let config: Config
    private let ciContext: CIContext
    
    // Cache for embeddings to avoid recomputation
    private var embeddingCache: [String: [Float]] = [:]
    private let maxCacheSize = 1000
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }
    
    // MARK: - Embedding Extraction
    
    /// Extract face embedding from a cropped face image
    public func extractEmbedding(from faceImage: CGImage) async throws -> [Float] {
        // Validate image size
        let minPixels = Int(Float(min(faceImage.width, faceImage.height)) * config.minFaceSize)
        guard faceImage.width >= minPixels && faceImage.height >= minPixels else {
            throw Error.faceTooSmall
        }
        
        // Generate cache key
        let cacheKey = "\(faceImage.width)x\(faceImage.height)_\(faceImage.hashValue)"
        if let cached = embeddingCache[cacheKey] {
            return cached
        }
        
        // Normalize and resize face
        let normalizedFace = try await normalizeFace(faceImage)
        
        // Extract embedding using lightweight feature extraction
        // In production, this would use a CoreML model like MobileFaceNet
        // For now, we use a deterministic feature extraction based on image statistics
        let embedding = try await extractFeatures(from: normalizedFace)
        
        // Cache the result
        if embeddingCache.count >= maxCacheSize {
            // Remove oldest entries (simple FIFO for now)
            let keysToRemove = Array(embeddingCache.keys.prefix(maxCacheSize / 4))
            keysToRemove.forEach { embeddingCache.removeValue(forKey: $0) }
        }
        embeddingCache[cacheKey] = embedding
        
        return embedding
    }
    
    /// Extract embedding from face observation and source frame
    public func extractEmbedding(
        from observation: FaceObservation,
        in frame: CGImage,
        at timestamp: Double
    ) async throws -> FaceEmbeddingObservation {
        // Crop face from frame
        let faceImage = try cropFace(from: frame, bounds: observation.bounds)
        
        // Extract embedding
        let embedding = try await extractEmbedding(from: faceImage)
        
        return FaceEmbeddingObservation(
            bounds: observation.bounds,
            confidence: observation.confidence,
            roll: observation.roll,
            yaw: observation.yaw,
            pitch: observation.pitch,
            timestamp: timestamp,
            embedding: embedding
        )
    }
    
    /// Extract embeddings for all faces in a frame
    public func extractEmbeddings(
        from observations: [FaceObservation],
        in frame: CGImage,
        at timestamp: Double
    ) async throws -> [FaceEmbeddingObservation] {
        var results: [FaceEmbeddingObservation] = []
        
        for observation in observations {
            do {
                let embeddingObs = try await extractEmbedding(
                    from: observation,
                    in: frame,
                    at: timestamp
                )
                results.append(embeddingObs)
            } catch Error.faceTooSmall {
                // Skip faces that are too small
                continue
            }
        }
        
        return results
    }
    
    // MARK: - Comparison
    
    /// Compare two face embeddings using cosine similarity
    /// Returns value between -1 (opposite) and 1 (identical)
    public func compareFaces(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        return cosineSimilarity(a, b)
    }
    
    /// Check if two embeddings likely represent the same person
    /// Uses a threshold-based decision
    public func isSamePerson(_ a: [Float], _ b: [Float], threshold: Float = 0.6) -> Bool {
        compareFaces(a, b) >= threshold
    }
    
    /// Find best matching embedding from a set
    public func findBestMatch(
        for query: [Float],
        in candidates: [[Float]],
        threshold: Float = 0.5
    ) -> (index: Int, similarity: Float)? {
        var bestIndex = -1
        var bestSimilarity: Float = threshold
        
        for (index, candidate) in candidates.enumerated() {
            let similarity = compareFaces(query, candidate)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestIndex = index
            }
        }
        
        return bestIndex >= 0 ? (bestIndex, bestSimilarity) : nil
    }
    
    // MARK: - Private Methods
    
    /// Normalize face image (resize, align, normalize pixels)
    private func normalizeFace(_ image: CGImage) async throws -> CGImage {
        let targetSize = CGSize(
            width: config.targetFaceSize,
            height: config.targetFaceSize
        )
        
        // Create resized image
        let ciImage = CIImage(cgImage: image)
        let scale = targetSize.width / CGFloat(image.width)
        
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Crop to target size
        let cropRect = CGRect(
            x: (scaledImage.extent.width - targetSize.width) / 2,
            y: (scaledImage.extent.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        let croppedImage = scaledImage.cropped(to: cropRect)
        
        guard let cgImage = ciContext.createCGImage(croppedImage, from: croppedImage.extent) else {
            throw Error.faceAlignmentFailed
        }
        
        return cgImage
    }
    
    /// Crop face region from full frame
    private func cropFace(from frame: CGImage, bounds: CGRect) throws -> CGImage {
        // Convert normalized bounds to pixel coordinates
        let pixelBounds = CGRect(
            x: bounds.minX * CGFloat(frame.width),
            y: (1 - bounds.maxY) * CGFloat(frame.height),  // Flip Y
            width: bounds.width * CGFloat(frame.width),
            height: bounds.height * CGFloat(frame.height)
        )
        
        // Add padding (20% on each side)
        let padding = min(pixelBounds.width, pixelBounds.height) * 0.2
        let expandedBounds = pixelBounds.insetBy(dx: -padding, dy: -padding)
        
        // Clamp to image bounds
        let clampedBounds = expandedBounds.intersection(
            CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        )
        
        guard !clampedBounds.isEmpty,
              let cropped = frame.cropping(to: clampedBounds) else {
            throw Error.invalidFaceImage
        }
        
        return cropped
    }
    
    /// Extract feature vector from normalized face
    /// This is a placeholder for CoreML model inference
    /// In production, replace with MobileFaceNet or similar
    private func extractFeatures(from image: CGImage) async throws -> [Float] {
        // Generate deterministic pseudo-embedding based on image content
        // This allows testing identity clustering without the actual model
        
        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        
        guard let data = image.dataProvider?.data,
              let pixels = CFDataGetBytePtr(data) else {
            throw Error.embeddingExtractionFailed
        }
        
        var embedding = [Float](repeating: 0, count: config.embeddingDimension)
        
        // Sample regions of the face to build feature vector
        let regionSize = 8
        let regionsX = width / regionSize
        let regionsY = height / regionSize
        let _ = config.embeddingDimension / (regionsX * regionsY + 1)
        
        var featureIndex = 0
        
        for ry in 0..<regionsY {
            for rx in 0..<regionsX {
                // Compute statistics for this region
                var sum: Float = 0
                var sumSq: Float = 0
                var count: Float = 0
                
                for y in (ry * regionSize)..<min((ry + 1) * regionSize, height) {
                    for x in (rx * regionSize)..<min((rx + 1) * regionSize, width) {
                        let offset = y * bytesPerRow + x * 4  // Assuming RGBA
                        let r = Float(pixels[offset]) / 255.0
                        let g = Float(pixels[offset + 1]) / 255.0
                        let b = Float(pixels[offset + 2]) / 255.0
                        let intensity = (r + g + b) / 3.0
                        
                        sum += intensity
                        sumSq += intensity * intensity
                        count += 1
                    }
                }
                
                if count > 0 && featureIndex < config.embeddingDimension {
                    let mean = sum / count
                    let variance = (sumSq / count) - (mean * mean)
                    let std = sqrt(max(variance, 0))
                    
                    // Store features
                    embedding[featureIndex] = mean
                    featureIndex += 1
                    if featureIndex < config.embeddingDimension {
                        embedding[featureIndex] = std
                        featureIndex += 1
                    }
                }
            }
        }
        
        // Fill remaining with gradient features
        while featureIndex < config.embeddingDimension {
            let t = Float(featureIndex) / Float(config.embeddingDimension)
            embedding[featureIndex] = sin(t * .pi * 4)
            featureIndex += 1
        }
        
        // L2 normalize the embedding
        embedding = l2Normalize(embedding)
        
        return embedding
    }
    
    /// L2 normalize a vector
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        
        guard norm > 0 else { return vector }
        
        var result = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))
        
        return result
    }
    
    /// Compute cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        
        let denominator = sqrt(normA * normB)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
    
    // MARK: - Cache Management
    
    /// Clear the embedding cache
    public func clearCache() {
        embeddingCache.removeAll()
    }
    
    /// Get cache statistics
    public var cacheStats: (count: Int, maxSize: Int) {
        (embeddingCache.count, maxCacheSize)
    }
}

// MARK: - Batch Processing Extension

extension FaceEmbeddingEngine {
    /// Process multiple frames in batch
    public func processFrames(
        _ frames: [(image: CGImage, observations: [FaceObservation], timestamp: Double)]
    ) async throws -> [FaceEmbeddingObservation] {
        var allEmbeddings: [FaceEmbeddingObservation] = []
        
        for frame in frames {
            let embeddings = try await extractEmbeddings(
                from: frame.observations,
                in: frame.image,
                at: frame.timestamp
            )
            allEmbeddings.append(contentsOf: embeddings)
        }
        
        return allEmbeddings
    }
    
    /// Compute distance matrix for clustering
    public func computeDistanceMatrix(
        embeddings: [[Float]]
    ) -> [[Float]] {
        let n = embeddings.count
        var distances = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        
        for i in 0..<n {
            for j in (i + 1)..<n {
                let similarity = cosineSimilarity(embeddings[i], embeddings[j])
                let distance = 1 - similarity  // Convert similarity to distance
                distances[i][j] = distance
                distances[j][i] = distance
            }
        }
        
        return distances
    }
}
