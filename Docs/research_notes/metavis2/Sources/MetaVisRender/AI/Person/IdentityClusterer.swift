// IdentityClusterer.swift
// MetaVisRender
//
// Created for Sprint 06: Person Intelligence
// Clusters face embeddings into person identities

import Foundation
import Accelerate

// MARK: - Identity Clusterer

/// Clusters face embeddings into distinct person identities
/// using hierarchical agglomerative clustering with cosine distance.
public actor IdentityClusterer {
    
    // MARK: - Types
    
    public enum Error: Swift.Error, Equatable {
        case noEmbeddings
        case clusteringFailed
        case invalidThreshold
    }
    
    public struct Config: Sendable {
        /// Distance threshold for merging clusters (0-1)
        /// Lower = more clusters, higher = fewer clusters
        public let distanceThreshold: Float
        
        /// Minimum observations for a valid identity
        public let minObservationsPerIdentity: Int
        
        /// Maximum number of identities to output
        public let maxIdentities: Int
        
        /// Linkage method for hierarchical clustering
        public let linkage: LinkageMethod
        
        public init(
            distanceThreshold: Float = 0.4,
            minObservationsPerIdentity: Int = 2,
            maxIdentities: Int = 50,
            linkage: LinkageMethod = .average
        ) {
            self.distanceThreshold = distanceThreshold
            self.minObservationsPerIdentity = minObservationsPerIdentity
            self.maxIdentities = maxIdentities
            self.linkage = linkage
        }
        
        public static let `default` = Config()
        
        /// Strict mode - requires higher similarity
        public static let strict = Config(
            distanceThreshold: 0.3,
            minObservationsPerIdentity: 3
        )
        
        /// Lenient mode - merges more aggressively
        public static let lenient = Config(
            distanceThreshold: 0.5,
            minObservationsPerIdentity: 1
        )
    }
    
    public enum LinkageMethod: String, Codable, Sendable {
        /// Average distance between all pairs
        case average
        /// Minimum distance (single linkage)
        case single
        /// Maximum distance (complete linkage)
        case complete
        /// Centroid distance
        case centroid
    }
    
    // MARK: - Properties
    
    private let config: Config
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Clustering
    
    /// Cluster face embeddings into person identities
    public func clusterFaces(
        observations: [FaceEmbeddingObservation]
    ) throws -> [PersonIdentity] {
        guard !observations.isEmpty else {
            throw Error.noEmbeddings
        }
        
        // Extract embeddings
        let embeddings = observations.map { $0.embedding }
        
        // Compute initial distance matrix
        let distances = computeDistanceMatrix(embeddings)
        
        // Perform hierarchical clustering
        let clusterAssignments = hierarchicalClustering(
            distanceMatrix: distances,
            threshold: config.distanceThreshold
        )
        
        // Build person identities from clusters
        return buildIdentities(
            observations: observations,
            assignments: clusterAssignments
        )
    }
    
    /// Cluster and assign IDs to observations
    public func clusterAndAssign(
        observations: inout [FaceEmbeddingObservation]
    ) throws -> [PersonIdentity] {
        let identities = try clusterFaces(observations: observations)
        
        // Create lookup by embedding hash
        var identityLookup: [Int: UUID] = [:]
        for identity in identities {
            if let embedding = identity.representativeEmbedding {
                identityLookup[embedding.hashValue] = identity.id
            }
        }
        
        // Assign person IDs to observations based on which cluster they belong to
        let embeddings = observations.map { $0.embedding }
        let assignments = hierarchicalClustering(
            distanceMatrix: computeDistanceMatrix(embeddings),
            threshold: config.distanceThreshold
        )
        
        for (index, clusterId) in assignments.enumerated() {
            if clusterId < identities.count {
                observations[index].personId = identities[clusterId].id
            }
        }
        
        return identities
    }
    
    // MARK: - Private Methods
    
    /// Compute distance matrix using cosine distance
    private func computeDistanceMatrix(_ embeddings: [[Float]]) -> [[Float]] {
        let n = embeddings.count
        var distances = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        
        for i in 0..<n {
            for j in (i + 1)..<n {
                let similarity = cosineSimilarity(embeddings[i], embeddings[j])
                let distance = 1 - similarity
                distances[i][j] = distance
                distances[j][i] = distance
            }
        }
        
        return distances
    }
    
    /// Perform hierarchical agglomerative clustering
    private func hierarchicalClustering(
        distanceMatrix: [[Float]],
        threshold: Float
    ) -> [Int] {
        let n = distanceMatrix.count
        guard n > 0 else { return [] }
        
        // Initialize: each point is its own cluster
        var clusterAssignments = Array(0..<n)
        var activeClusters = Set(0..<n)
        
        // Copy distance matrix (will be modified)
        var distances = distanceMatrix
        
        // Track cluster sizes for linkage computation
        var clusterSizes = [Int](repeating: 1, count: n)
        
        while activeClusters.count > 1 {
            // Find minimum distance pair
            var minDist: Float = .infinity
            var minI = -1
            var minJ = -1
            
            let activeList = Array(activeClusters).sorted()
            for (idx, i) in activeList.enumerated() {
                for j in activeList[(idx + 1)...] {
                    if distances[i][j] < minDist {
                        minDist = distances[i][j]
                        minI = i
                        minJ = j
                    }
                }
            }
            
            // Check if we should stop merging
            if minDist > threshold || minI < 0 || minJ < 0 {
                break
            }
            
            // Merge clusters minI and minJ (keep minI, remove minJ)
            // Update assignments
            for k in 0..<n {
                if clusterAssignments[k] == minJ {
                    clusterAssignments[k] = minI
                }
            }
            
            // Update distances based on linkage method
            let sizeI = clusterSizes[minI]
            let sizeJ = clusterSizes[minJ]
            
            for k in activeClusters where k != minI && k != minJ {
                let newDist = computeLinkageDistance(
                    distI: distances[minI][k],
                    distJ: distances[minJ][k],
                    sizeI: sizeI,
                    sizeJ: sizeJ,
                    sizeK: clusterSizes[k]
                )
                distances[minI][k] = newDist
                distances[k][minI] = newDist
            }
            
            // Update cluster size
            clusterSizes[minI] = sizeI + sizeJ
            
            // Remove minJ from active clusters
            activeClusters.remove(minJ)
        }
        
        // Renumber clusters to be consecutive
        return renumberClusters(clusterAssignments)
    }
    
    /// Compute linkage distance based on method
    private func computeLinkageDistance(
        distI: Float,
        distJ: Float,
        sizeI: Int,
        sizeJ: Int,
        sizeK: Int
    ) -> Float {
        switch config.linkage {
        case .single:
            return min(distI, distJ)
        case .complete:
            return max(distI, distJ)
        case .average:
            return (Float(sizeI) * distI + Float(sizeJ) * distJ) / Float(sizeI + sizeJ)
        case .centroid:
            // Approximation using weighted average
            let alpha = Float(sizeI) / Float(sizeI + sizeJ)
            let beta = Float(sizeJ) / Float(sizeI + sizeJ)
            return alpha * distI + beta * distJ
        }
    }
    
    /// Renumber clusters to consecutive integers starting from 0
    private func renumberClusters(_ assignments: [Int]) -> [Int] {
        var mapping: [Int: Int] = [:]
        var nextId = 0
        
        return assignments.map { cluster in
            if let mapped = mapping[cluster] {
                return mapped
            } else {
                let newId = nextId
                mapping[cluster] = newId
                nextId += 1
                return newId
            }
        }
    }
    
    /// Build PersonIdentity objects from cluster assignments
    private func buildIdentities(
        observations: [FaceEmbeddingObservation],
        assignments: [Int]
    ) -> [PersonIdentity] {
        // Group observations by cluster
        var clusters: [Int: [FaceEmbeddingObservation]] = [:]
        for (index, obs) in observations.enumerated() {
            let clusterId = assignments[index]
            clusters[clusterId, default: []].append(obs)
        }
        
        // Build identities
        var identities: [PersonIdentity] = []
        
        for (_, clusterObs) in clusters.sorted(by: { $0.key < $1.key }) {
            // Skip clusters with too few observations
            guard clusterObs.count >= config.minObservationsPerIdentity else {
                continue
            }
            
            // Compute representative embedding (average)
            let avgEmbedding = averageEmbedding(clusterObs.map { $0.embedding })
            
            // Compute confidence based on intra-cluster similarity
            let confidence = computeClusterConfidence(embeddings: clusterObs.map { $0.embedding })
            
            // Find time range
            let timestamps = clusterObs.map { $0.timestamp }
            let firstAppearance = timestamps.min() ?? 0
            let lastAppearance = timestamps.max() ?? 0
            
            let identity = PersonIdentity(
                id: UUID(),
                label: "PERSON_\(String(format: "%02d", identities.count))",
                representativeEmbedding: avgEmbedding,
                confidence: confidence,
                observationCount: clusterObs.count,
                firstAppearance: firstAppearance,
                lastAppearance: lastAppearance
            )
            
            identities.append(identity)
            
            // Stop if we hit max identities
            if identities.count >= config.maxIdentities {
                break
            }
        }
        
        return identities
    }
    
    /// Compute average embedding for a cluster
    private func averageEmbedding(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        let dim = first.count
        
        var avg = [Float](repeating: 0, count: dim)
        
        for emb in embeddings {
            for i in 0..<dim {
                avg[i] += emb[i]
            }
        }
        
        let count = Float(embeddings.count)
        for i in 0..<dim {
            avg[i] /= count
        }
        
        // L2 normalize
        return l2Normalize(avg)
    }
    
    /// Compute cluster confidence based on internal similarity
    private func computeClusterConfidence(embeddings: [[Float]]) -> Float {
        guard embeddings.count > 1 else { return 1.0 }
        
        var totalSim: Float = 0
        var count = 0
        
        for i in 0..<embeddings.count {
            for j in (i + 1)..<embeddings.count {
                totalSim += cosineSimilarity(embeddings[i], embeddings[j])
                count += 1
            }
        }
        
        return count > 0 ? totalSim / Float(count) : 1.0
    }
    
    /// Cosine similarity
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        
        let denominator = sqrt(normA * normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
    
    /// L2 normalize
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
}

// MARK: - Convenience Extensions

extension IdentityClusterer {
    /// Merge clusters from different sources
    public func mergeIdentities(
        _ identities: [[PersonIdentity]],
        threshold: Float? = nil
    ) -> [PersonIdentity] {
        let allIdentities = identities.flatMap { $0 }
        guard !allIdentities.isEmpty else { return [] }
        
        // Filter to those with embeddings
        let withEmbeddings = allIdentities.filter { $0.representativeEmbedding != nil }
        guard !withEmbeddings.isEmpty else { return allIdentities }
        
        let embeddings = withEmbeddings.compactMap { $0.representativeEmbedding }
        let distances = computeDistanceMatrix(embeddings)
        
        let mergeThreshold = threshold ?? config.distanceThreshold
        let assignments = hierarchicalClustering(
            distanceMatrix: distances,
            threshold: mergeThreshold
        )
        
        // Group by assignment
        var groups: [Int: [PersonIdentity]] = [:]
        for (index, identity) in withEmbeddings.enumerated() {
            groups[assignments[index], default: []].append(identity)
        }
        
        // Create merged identities
        var merged: [PersonIdentity] = []
        for (_, group) in groups.sorted(by: { $0.key < $1.key }) {
            let embeddings = group.compactMap { $0.representativeEmbedding }
            let avgEmb = averageEmbedding(embeddings)
            let totalObs = group.reduce(0) { $0 + $1.observationCount }
            let avgConf = group.reduce(0.0) { $0 + $1.confidence } / Float(group.count)
            
            let mergedIdentity = PersonIdentity(
                id: group.first?.id ?? UUID(),
                label: "PERSON_\(String(format: "%02d", merged.count))",
                name: group.first(where: { $0.name != nil })?.name,
                representativeEmbedding: avgEmb,
                confidence: avgConf,
                observationCount: totalObs,
                firstAppearance: group.map { $0.firstAppearance }.min() ?? 0,
                lastAppearance: group.map { $0.lastAppearance }.max() ?? 0,
                linkedSpeakerId: group.first(where: { $0.linkedSpeakerId != nil })?.linkedSpeakerId
            )
            merged.append(mergedIdentity)
        }
        
        return merged
    }
}
