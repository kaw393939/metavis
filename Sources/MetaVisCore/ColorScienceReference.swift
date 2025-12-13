import Foundation
import simd

/// CPU Reference implementation of Color Transforms.
/// Used for Unit Testing and Headless Rendering.
public struct ColorScienceReference {
    
    // MARK: - Matrices (Row Major)
    
    // matches MAT_Rec709_to_ACEScg
    static let mat709toACES = matrix_float3x3(
        columns: (
            SIMD3<Float>(0.6131, 0.3395, 0.0474), // Column 0
            SIMD3<Float>(0.0702, 0.9164, 0.0134), // Column 1
            SIMD3<Float>(0.0206, 0.1096, 0.8698)  // Column 2
        )
    )
    
    // matches MAT_ACEScg_to_Rec709
    static let matACESto709 = matrix_float3x3(
        columns: (
            SIMD3<Float>(1.7049, -0.6217, -0.0833),
            SIMD3<Float>(-0.1301, 1.1407, -0.0106),
            SIMD3<Float>(-0.0240, -0.1289, 1.1530)
        )
    )
    
    // MARK: - Functions
    
    public static func srgbToLinear(_ srgb: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            degamma(srgb.x),
            degamma(srgb.y),
            degamma(srgb.z)
        )
    }
    
    public static func linearToSRGB(_ lin: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            gamma(lin.x),
            gamma(lin.y),
            gamma(lin.z)
        )
    }
    
    private static func degamma(_ v: Float) -> Float {
        if v <= 0.04045 { return v / 12.92 }
        return pow((v + 0.055) / 1.055, 2.4)
    }
    
    private static func gamma(_ v: Float) -> Float {
        if v <= 0.0031308 { return 12.92 * v }
        return 1.055 * pow(v, 1.0/2.4) - 0.055
    }
    
    // MARK: - Pipelines
    
    public static func IDT_Rec709_ACEScg(_ pixel: SIMD3<Float>) -> SIMD3<Float> {
        let linear = srgbToLinear(pixel)
        return mat709toACES * linear
    }
    
    public static func ODT_ACEScg_Rec709(_ pixel: SIMD3<Float>) -> SIMD3<Float> {
        let linear709 = matACESto709 * pixel
        return linearToSRGB(linear709)
    }
    
    // MARK: - ASC CDL
    
    public static func cdlCorrect(
        _ rgb: SIMD3<Float>,
        slope: SIMD3<Float>,
        offset: SIMD3<Float>,
        power: SIMD3<Float>,
        saturation: Float
    ) -> SIMD3<Float> {
        // 1. Slope & Offset
        var out = rgb * slope + offset
        
        // 2. Power (Clamp negative)
        out = simd_max(out, SIMD3<Float>(0,0,0))
        out = SIMD3<Float>(
            pow(out.x, power.x),
            pow(out.y, power.y),
            pow(out.z, power.z)
        )
        
        // 3. Saturation (AP1 Weighted)
        let lumaWeights = SIMD3<Float>(0.2722287, 0.6740818, 0.0536895)
        let luma = dot(out, lumaWeights)
        out = SIMD3<Float>(luma, luma, luma) + saturation * (out - SIMD3<Float>(luma, luma, luma))
        
        return out
    }
    
    // MARK: - Tone Mapping
    
    public static func acesFilm(_ x: SIMD3<Float>) -> SIMD3<Float> {
        let a: Float = 2.51
        let b: Float = 0.03
        let c: Float = 2.43
        let d: Float = 0.59
        let e: Float = 0.14
        
        // (x*(a*x+b))/(x*(c*x+d)+e)
        let numerator = x * (x * a + b)
        let denominator = x * (x * c + d) + e
        return clamp(numerator / denominator, min: 0.0, max: 1.0)
    }
}
