import Foundation
import Accelerate

public struct AudioSpeakerClusterer: Sendable {

    public struct Options: Sendable, Equatable {
        public var similarityThreshold: Float

        public init(similarityThreshold: Float = 0.72) {
            self.similarityThreshold = similarityThreshold
        }
    }

    public struct WindowEmbedding: Sendable, Equatable {
        public var midSeconds: Double
        public var embeddingUnit: [Float]

        public init(midSeconds: Double, embeddingUnit: [Float]) {
            self.midSeconds = midSeconds
            self.embeddingUnit = embeddingUnit
        }
    }

    public struct Assignment: Sendable, Equatable {
        public var midSeconds: Double
        public var clusterId: String

        public init(midSeconds: Double, clusterId: String) {
            self.midSeconds = midSeconds
            self.clusterId = clusterId
        }
    }

    private struct Cluster {
        var id: String
        var centroidUnit: [Float]
        var count: Int
    }

    public init() {}

    public func cluster(
        _ windows: [WindowEmbedding],
        options: Options = Options()
    ) -> [Assignment] {
        guard !windows.isEmpty else { return [] }

        // The original streaming centroid assignment is fast, but it can collapse alternating
        // speakers into a single cluster (the centroid becomes an average voice).
        // For diarization fixtures (short clips), prefer an agglomerative approach that starts
        // with one cluster per window and merges the most similar pair until the threshold.
        // This is deterministic and much more robust for turn-taking conversations.
        if windows.count <= 256 {
            struct AggCluster {
                var members: [Int]
                var centroidUnit: [Float]
                var count: Int
            }

            func weightedCentroidUnit(_ a: AggCluster, _ b: AggCluster) -> [Float] {
                var sum = a.centroidUnit
                var sa = Float(a.count)
                vDSP_vsmul(sum, 1, &sa, &sum, 1, vDSP_Length(sum.count))

                var other = b.centroidUnit
                var sb = Float(b.count)
                vDSP_vsmul(other, 1, &sb, &other, 1, vDSP_Length(other.count))

                vDSP_vadd(sum, 1, other, 1, &sum, 1, vDSP_Length(sum.count))
                return SpeakerEmbeddingMath.l2Normalize(sum)
            }

            var clusters: [AggCluster] = windows.enumerated().map { idx, w in
                AggCluster(members: [idx], centroidUnit: w.embeddingUnit, count: 1)
            }

            func firstMidSeconds(_ c: AggCluster) -> Double {
                var best = Double.greatestFiniteMagnitude
                for i in c.members {
                    best = min(best, windows[i].midSeconds)
                }
                return best
            }

            while clusters.count >= 2 {
                var bestI = 0
                var bestJ = 1
                var bestSim: Float = -1

                for i in 0..<(clusters.count - 1) {
                    for j in (i + 1)..<clusters.count {
                        let sim = SpeakerEmbeddingMath.cosineSimilarityUnitVectors(
                            clusters[i].centroidUnit,
                            clusters[j].centroidUnit
                        )
                        if sim > bestSim {
                            bestSim = sim
                            bestI = i
                            bestJ = j
                        } else if sim == bestSim {
                            // Deterministic tie-break: earlier first-mid wins.
                            let a = min(firstMidSeconds(clusters[i]), firstMidSeconds(clusters[j]))
                            let b = min(firstMidSeconds(clusters[bestI]), firstMidSeconds(clusters[bestJ]))
                            if a < b {
                                bestI = i
                                bestJ = j
                            }
                        }
                    }
                }

                guard bestSim >= options.similarityThreshold else { break }

                let a = clusters[bestI]
                let b = clusters[bestJ]
                let mergedCentroid = weightedCentroidUnit(a, b)
                let mergedMembers = (a.members + b.members).sorted()
                let merged = AggCluster(members: mergedMembers, centroidUnit: mergedCentroid, count: a.count + b.count)

                // Remove higher index first.
                if bestI > bestJ {
                    clusters.remove(at: bestI)
                    clusters.remove(at: bestJ)
                } else {
                    clusters.remove(at: bestJ)
                    clusters.remove(at: bestI)
                }
                clusters.append(merged)
            }

            // Create stable cluster IDs ordered by first occurrence.
            let ordered = clusters
                .enumerated()
                .map { (idx: $0.offset, first: firstMidSeconds($0.element)) }
                .sorted { a, b in
                    if a.first != b.first { return a.first < b.first }
                    return a.idx < b.idx
                }

            var clusterIdByClusterIndex: [Int: String] = [:]
            clusterIdByClusterIndex.reserveCapacity(ordered.count)
            for (rank, item) in ordered.enumerated() {
                clusterIdByClusterIndex[item.idx] = "C\(rank + 1)"
            }

            var clusterIndexByWindowIndex: [Int] = Array(repeating: -1, count: windows.count)
            for (ci, c) in clusters.enumerated() {
                for wi in c.members {
                    clusterIndexByWindowIndex[wi] = ci
                }
            }

            var assignments: [Assignment] = []
            assignments.reserveCapacity(windows.count)
            for (wi, w) in windows.enumerated() {
                let ci = clusterIndexByWindowIndex[wi]
                let cid = clusterIdByClusterIndex[ci] ?? "C1"
                assignments.append(Assignment(midSeconds: w.midSeconds, clusterId: cid))
            }
            return assignments
        }

        var clusters: [Cluster] = []
        clusters.reserveCapacity(8)

        var assignments: [Assignment] = []
        assignments.reserveCapacity(windows.count)

        var nextId = 1

        for w in windows {
            if clusters.isEmpty {
                let id = "C\(nextId)"
                nextId += 1
                clusters.append(Cluster(id: id, centroidUnit: w.embeddingUnit, count: 1))
                assignments.append(Assignment(midSeconds: w.midSeconds, clusterId: id))
                continue
            }

            var bestIdx: Int? = nil
            var bestSim: Float = -1

            for (idx, c) in clusters.enumerated() {
                let sim = SpeakerEmbeddingMath.cosineSimilarityUnitVectors(w.embeddingUnit, c.centroidUnit)
                if sim > bestSim {
                    bestSim = sim
                    bestIdx = idx
                } else if sim == bestSim {
                    // Deterministic tie-break: lower clusterId wins.
                    if let bi = bestIdx, c.id < clusters[bi].id { bestIdx = idx }
                }
            }

            if let bi = bestIdx, bestSim >= options.similarityThreshold {
                // Assign and update centroid deterministically.
                let id = clusters[bi].id
                let n = clusters[bi].count

                // centroid = normalize((centroid*n + embed) / (n+1))
                var sum = clusters[bi].centroidUnit
                var scale = Float(n)
                vDSP_vsmul(sum, 1, &scale, &sum, 1, vDSP_Length(sum.count))

                let e = w.embeddingUnit
                vDSP_vadd(sum, 1, e, 1, &sum, 1, vDSP_Length(sum.count))

                sum = SpeakerEmbeddingMath.l2Normalize(sum)

                clusters[bi].centroidUnit = sum
                clusters[bi].count = n + 1

                assignments.append(Assignment(midSeconds: w.midSeconds, clusterId: id))
            } else {
                let id = "C\(nextId)"
                nextId += 1
                clusters.append(Cluster(id: id, centroidUnit: w.embeddingUnit, count: 1))
                assignments.append(Assignment(midSeconds: w.midSeconds, clusterId: id))
            }
        }

        return assignments
    }
}
