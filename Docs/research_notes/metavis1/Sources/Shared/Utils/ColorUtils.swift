import Foundation
import simd

public enum ColorUtils {
    public static func parseColor(_ hex: String?) -> SIMD4<Float>? {
        guard let hex = hex, hex.hasPrefix("#") else { return nil }
        let hexString = String(hex.dropFirst())
        guard let val = Int(hexString, radix: 16) else { return nil }

        let r = Float((val >> 16) & 0xFF) / 255.0
        let g = Float((val >> 8) & 0xFF) / 255.0
        let b = Float(val & 0xFF) / 255.0
        return SIMD4<Float>(r, g, b, 1.0)
    }

    public static func sRGBToLinear(_ srgb: SIMD4<Float>) -> SIMD4<Float> {
        func toLinear(_ v: Float) -> Float {
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return SIMD4<Float>(toLinear(srgb.x), toLinear(srgb.y), toLinear(srgb.z), srgb.w)
    }

    // Matrix multiplication helper
    private static func mul(_ m: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>), _ v: SIMD3<Float>) -> SIMD3<Float> {
        return v.x * m.0 + v.y * m.1 + v.z * m.2
    }

    /// Convert Linear sRGB to ACEScg
    public static func linearSRGBToACEScg(_ linear: SIMD4<Float>) -> SIMD4<Float> {
        // sRGB (Linear) -> XYZ (D65)
        // Matrix from http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
        let sRGB_to_XYZ = (
            SIMD3<Float>(0.4124564, 0.2126729, 0.0193339), // Column 0 (Red)
            SIMD3<Float>(0.3575761, 0.7151522, 0.1191920), // Column 1 (Green)
            SIMD3<Float>(0.1804375, 0.0721750, 0.9503041) // Column 2 (Blue)
        )

        // XYZ (D65) -> ACEScg
        // Matrix from AMPAS TB-2014-004
        let XYZ_to_ACEScg = (
            SIMD3<Float>(1.6410233797, -0.6636628587, 0.0117218943),
            SIMD3<Float>(-0.3248032942, 1.6153315917, -0.0082844420),
            SIMD3<Float>(-0.2364246952, 0.0165108263, 1.0083096685)
        )

        let rgb = SIMD3<Float>(linear.x, linear.y, linear.z)

        // Apply sRGB -> XYZ
        // Note: Our mul helper assumes columns, which matches the definition above
        let xyz = mul(sRGB_to_XYZ, rgb)

        // Apply XYZ -> ACEScg
        let acescg = mul(XYZ_to_ACEScg, xyz)

        return SIMD4<Float>(acescg.x, acescg.y, acescg.z, linear.w)
    }
}
