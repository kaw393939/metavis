// ColorSpace.swift
// Host-side color utilities shared with MetalVis

import simd

public enum ColorSpace {
    // MARK: - sRGB ↔ Linear

    @inline(__always)
    public static func sRGBToLinear(_ c: Float) -> Float {
        if c <= 0.04045 {
            return c / 12.92
        } else {
            return powf((c + 0.055) / 1.055, 2.4)
        }
    }

    @inline(__always)
    public static func linearToSRGB(_ c: Float) -> Float {
        if c <= 0.0031308 {
            return c * 12.92
        } else {
            return 1.055 * powf(c, 1.0 / 2.4) - 0.055
        }
    }

    @inline(__always)
    public static func sRGBToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            sRGBToLinear(c.x),
            sRGBToLinear(c.y),
            sRGBToLinear(c.z)
        )
    }

    @inline(__always)
    public static func linearToSRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(
            linearToSRGB(c.x),
            linearToSRGB(c.y),
            linearToSRGB(c.z)
        )
    }

    // MARK: - sRGB (linear) ↔ ACEScg

    /// 3×3 matrix: linear sRGB → ACEScg (AP1)
    /// Source: standard sRGB→AP1 gamut transform.
    /// Note: simd_float3x3 is column-major.
    /// Standard Matrix (Row-Major):
    /// 0.613097  0.339523  0.047379
    /// 0.070194  0.916354  0.013452
    /// 0.020616  0.109570  0.869815
    ///
    /// Transposed for Column-Major initialization:
    public static let sRGBToACEScg_M: simd_float3x3 = .init(
        SIMD3<Float>(0.613097, 0.070194, 0.020616), // Column 0 (R coeffs)
        SIMD3<Float>(0.339523, 0.916354, 0.109570), // Column 1 (G coeffs)
        SIMD3<Float>(0.047379, 0.013452, 0.869815) // Column 2 (B coeffs)
    )

    /// 3×3 matrix: ACEScg (AP1) → linear sRGB
    /// This is the inverse of sRGBToACEScg_M.
    public static let ACEScgToSRGB_M: simd_float3x3 = sRGBToACEScg_M.inverse

    @inline(__always)
    public static func linearSRGBToACEScg(_ c: SIMD3<Float>) -> SIMD3<Float> {
        return sRGBToACEScg_M * c
    }

    @inline(__always)
    public static func ACEScgToLinearSRGB(_ c: SIMD3<Float>) -> SIMD3<Float> {
        return ACEScgToSRGB_M * c
    }

    // MARK: - Convenience: sRGB (gamma) → ACEScg (linear)

    /// Input: sRGB-encoded (gamma) color in 0–1.
    /// Output: ACEScg-linear color.
    @inline(__always)
    public static func sRGBEncodedToACEScg(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let lin = sRGBToLinear(c)
        return linearSRGBToACEScg(lin)
    }

    /// Input: ACEScg-linear color.
    /// Output: sRGB-encoded (gamma) color in 0–1.
    @inline(__always)
    public static func ACEScgToSRGBEncoded(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let linSRGB = ACEScgToLinearSRGB(c)
        return linearToSRGB(linSRGB)
    }
}
