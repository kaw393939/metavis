import Foundation
import Accelerate

public protocol SpeakerEmbeddingModel {
    var name: String { get }
    var windowSeconds: Double { get }
    var sampleRate: Double { get }
    var embeddingDimension: Int { get }

    func embed(windowedMonoPCM: [Float]) throws -> [Float]
}

public enum SpeakerEmbeddingMath {

    public static func l2Normalize(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return v }
        var sumSq: Float = 0
        vDSP_svesq(v, 1, &sumSq, vDSP_Length(v.count))
        let denom = sqrt(max(1e-12, sumSq))
        var out = v
        var d = denom
        vDSP_vsdiv(out, 1, &d, &out, 1, vDSP_Length(out.count))
        return out
    }

    public static func cosineSimilarityUnitVectors(_ aUnit: [Float], _ bUnit: [Float]) -> Float {
        guard aUnit.count == bUnit.count, !aUnit.isEmpty else { return -1 }
        var dot: Float = 0
        vDSP_dotpr(aUnit, 1, bUnit, 1, &dot, vDSP_Length(aUnit.count))
        return dot
    }
}
