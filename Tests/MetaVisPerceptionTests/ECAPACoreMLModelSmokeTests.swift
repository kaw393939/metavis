import XCTest
import MetaVisCore
@testable import MetaVisPerception

final class ECAPACoreMLModelSmokeTests: XCTestCase {

    func test_real_ecapa_model_outputs_non_constant_embeddings_whenEnabled() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["METAVIS_RUN_ECAPA_COREML_TESTS"] == "1" else {
            throw XCTSkip("Set METAVIS_RUN_ECAPA_COREML_TESTS=1 to enable real ECAPA CoreML smoke test")
        }
        guard let modelPath = env["METAVIS_ECAPA_MODEL"], !modelPath.isEmpty else {
            throw XCTSkip("Set METAVIS_ECAPA_MODEL=<path to ecapa .mlmodelc>")
        }

        let modelURL = URL(fileURLWithPath: modelPath)
        let model = try ECAPATDNNCoreMLSpeakerEmbeddingModel(
            modelURL: modelURL,
            inputName: nil,
            outputName: nil,
            windowSeconds: 3.0,
            sampleRate: 16_000,
            embeddingDimension: nil
        )

        let n = Int((model.windowSeconds * model.sampleRate).rounded(.toNearestOrAwayFromZero))
        XCTAssertGreaterThan(n, 0)

        // Two distinct deterministic inputs.
        let zeros = [Float](repeating: 0, count: n)
        var noise = [Float](repeating: 0, count: n)
        for i in 0..<n {
            // Cheap deterministic pseudo-noise.
            let x = Float((i * 48271) % 2147483647) / Float(2147483647)
            noise[i] = (x - 0.5) * 0.2
        }

        let e0 = try model.embed(windowedMonoPCM: zeros)
        let e1 = try model.embed(windowedMonoPCM: noise)

        XCTAssertEqual(e0.count, e1.count)
        XCTAssertGreaterThan(e0.count, 8)

        let sim = SpeakerEmbeddingMath.cosineSimilarityUnitVectors(e0, e1)
        // If this is ~1.0, the model is likely degenerate (constant output).
        XCTAssertLessThan(sim, 0.999, "Expected real ECAPA model to produce different embeddings for different inputs. cosine=\(sim)")
    }
}
