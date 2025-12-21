import simd

public struct PBRMaterial: Sendable {
    public let baseColor: SIMD3<Float>
    public let roughness: Float
    public let metallic: Float
    public let emissive: SIMD3<Float>
    
    public init(baseColor: SIMD3<Float> = SIMD3(1, 1, 1), roughness: Float = 0.5, metallic: Float = 0.0, emissive: SIMD3<Float> = SIMD3(0, 0, 0)) {
        self.baseColor = baseColor
        self.roughness = roughness
        self.metallic = metallic
        self.emissive = emissive
    }
}
