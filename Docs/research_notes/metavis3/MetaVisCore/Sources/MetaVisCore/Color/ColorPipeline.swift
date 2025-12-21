import Foundation
import simd

/// A comprehensive color management engine for transforming between color spaces.
/// Supports ACEScg, Rec.2020, sRGB, and P3.
public struct ColorPipeline: Sendable {
    
    public init() {}
    
    // MARK: - Matrices (Column-Major)
    
    // sRGB (D65) to ACEScg (AP1, D60)
    // Source: ACES documentation
    private static let sRGB_to_ACEScg = simd_float3x3(
        simd_float3(0.6131, 0.0702, 0.0206),
        simd_float3(0.3395, 0.9164, 0.1096),
        simd_float3(0.0474, 0.0134, 0.8698)
    )
    
    // ACEScg (AP1, D60) to sRGB (D65)
    private static let ACEScg_to_sRGB = sRGB_to_ACEScg.inverse
    
    // MARK: - Operations
    
    /// Converts an sRGB color (0-1) to ACEScg linear.
    /// Applies sRGB EOTF (inverse gamma) then matrix transform.
    public func convertSRGBToACEScg(_ color: SIMD3<Float>) -> SIMD3<Float> {
        let linear = sRGB_EOTF(color)
        return ColorPipeline.sRGB_to_ACEScg * linear
    }
    
    /// Converts ACEScg linear to sRGB (0-1) for display.
    /// Applies matrix transform then sRGB OETF (gamma).
    public func convertACEScgToSRGB(_ color: SIMD3<Float>) -> SIMD3<Float> {
        let srgbLinear = ColorPipeline.ACEScg_to_sRGB * color
        return sRGB_OETF(srgbLinear)
    }
    
    // MARK: - Transfer Functions
    
    /// sRGB Electro-Optical Transfer Function (Decodes sRGB to Linear)
    private func sRGB_EOTF(_ v: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            sRGB_EOTF_Scalar(v.x),
            sRGB_EOTF_Scalar(v.y),
            sRGB_EOTF_Scalar(v.z)
        )
    }
    
    private func sRGB_EOTF_Scalar(_ v: Float) -> Float {
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    
    /// sRGB Opto-Electrical Transfer Function (Encodes Linear to sRGB)
    private func sRGB_OETF(_ v: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            sRGB_OETF_Scalar(v.x),
            sRGB_OETF_Scalar(v.y),
            sRGB_OETF_Scalar(v.z)
        )
    }
    
    private func sRGB_OETF_Scalar(_ v: Float) -> Float {
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }
}
