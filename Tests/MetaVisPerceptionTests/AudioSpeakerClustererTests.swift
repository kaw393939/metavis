import XCTest
@testable import MetaVisPerception

final class AudioSpeakerClustererTests: XCTestCase {

    func test_clusters_two_alternating_speakers_into_two_clusters_deterministically() {
        let a = SpeakerEmbeddingMath.l2Normalize([1, 0, 0, 0])
        let b = SpeakerEmbeddingMath.l2Normalize([0, 1, 0, 0])

        let windows: [AudioSpeakerClusterer.WindowEmbedding] = (0..<20).map { i in
            let emb = (i % 2 == 0) ? a : b
            return .init(midSeconds: Double(i) * 0.5, embeddingUnit: emb)
        }

        let clusterer = AudioSpeakerClusterer()
        let out = clusterer.cluster(windows, options: .init(similarityThreshold: 0.8))

        let clusterIds = Set(out.map { $0.clusterId })
        XCTAssertEqual(clusterIds.count, 2)

        // Deterministic assignment: first window becomes C1.
        XCTAssertEqual(out.first?.clusterId, "C1")

        // Alternate should flip between exactly two cluster IDs.
        let seq = out.map { $0.clusterId }
        XCTAssertTrue(seq.contains("C1"))
        XCTAssertTrue(seq.contains("C2"))
    }

    func test_creates_new_cluster_when_similarity_below_threshold() {
        let a = SpeakerEmbeddingMath.l2Normalize([1, 0, 0, 0])
        let c = SpeakerEmbeddingMath.l2Normalize([0, 0, 1, 0])

        let windows: [AudioSpeakerClusterer.WindowEmbedding] = [
            .init(midSeconds: 0.5, embeddingUnit: a),
            .init(midSeconds: 1.0, embeddingUnit: c)
        ]

        let clusterer = AudioSpeakerClusterer()
        let out = clusterer.cluster(windows, options: .init(similarityThreshold: 0.95))
        XCTAssertEqual(out.map { $0.clusterId }, ["C1", "C2"])
    }
}
