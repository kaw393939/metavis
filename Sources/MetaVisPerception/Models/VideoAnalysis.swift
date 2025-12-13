import Foundation
import CoreGraphics

public struct VideoAnalysis: Sendable, Codable {
    public let dominantColors: [SIMD3<Float>]
    public let lumaHistogram: [Float] // 256 bins
    public let skinToneLikelihood: Float // 0..1
    public let faces: [CGRect] // normalized coordinates

    public init(
        dominantColors: [SIMD3<Float>],
        lumaHistogram: [Float],
        skinToneLikelihood: Float,
        faces: [CGRect]
    ) {
        self.dominantColors = dominantColors
        self.lumaHistogram = lumaHistogram
        self.skinToneLikelihood = skinToneLikelihood
        self.faces = faces
    }
}
