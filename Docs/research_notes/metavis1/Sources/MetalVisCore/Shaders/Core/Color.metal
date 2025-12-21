#include <metal_stdlib>
using namespace metal;

#ifndef CORE_COLOR_METAL
#define CORE_COLOR_METAL

namespace Core {
namespace Color {

    // MARK: - Constants
    
    // Rec.709 Luma Coefficients (Standard sRGB/HDTV)
    // Using half precision for GPU performance - sufficient for perceptual luma
    constant half3 LumaRec709_h = half3(0.2126h, 0.7152h, 0.0722h);
    constant float3 LumaRec709 = float3(0.2126, 0.7152, 0.0722);
    
    // ACEScg (AP1) Luma Coefficients
    constant half3 LumaACEScg_h = half3(0.2722h, 0.6741h, 0.0537h);
    constant float3 LumaACEScg = float3(0.2722287168, 0.6740817658, 0.0536895174);

    // MARK: - Color Space Matrices
    
    // ACEScg -> Rec.709 (Linear)
    constant float3x3 ACEScg_to_Rec709 = float3x3(
        float3(1.70485868, -0.13007725, -0.02396407),
        float3(-0.62171602, 1.14073577, -0.12897547),
        float3(-0.08329937, -0.01055984, 1.15301402)
    );

    // ACEScg -> Rec.2020 (Linear)
    // Matrix approximation (D60 -> D65 adapted)
    constant float3x3 ACEScg_to_Rec2020 = float3x3(
        float3(0.6132, 0.3395, 0.0474),
        float3(0.0742, 0.9167, 0.0091),
        float3(0.0206, 0.1061, 0.8733)
    );

    // MARK: - Utilities
    
    inline float luminance(float3 color, float3 weights = LumaACEScg) {
        return dot(color, weights);
    }

    // Optimized half-precision luminance - prefer this for post-processing
    inline half luminance_h(half3 color) {
        return dot(color, LumaACEScg_h);
    }
    
    // Legacy overload for compatibility
    inline half luminance(half3 color) {
        return luminance_h(color);
    }

    // MARK: - Tone Mapping Curves
    
    // Narkowicz ACES Fitted Curve
    // Input: Linear Color (Rec.709 primaries expected for this specific curve fit, 
    // but often applied to others for "look")
    inline half3 TonemapACES_Narkowicz(half3 x) {
        half a = 2.51h;
        half b = 0.03h;
        half c = 2.43h;
        half d = 0.59h;
        half e = 0.14h;
        return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0h, 1.0h);
    }
    
    // Overload for float3 compatibility
    inline float3 TonemapACES_Narkowicz(float3 x) {
        return float3(TonemapACES_Narkowicz(half3(x)));
    }


    // ST.2084 (PQ) EOTF Inverse (Linear -> PQ)
    // Input: Linear normalized to 0-1 range (where 1.0 = 10000 nits)
    // NOTE: For canonical PQ encoding, use Core::ColorSpace::LinearNitsToPQ
    inline half3 LinearToPQ(half3 linearColor) {
        half m1 = 2610.0h / 4096.0h * 0.25h;
        half m2 = 2523.0h / 4096.0h * 128.0h;
        half c1 = 3424.0h / 4096.0h;
        half c2 = 2413.0h / 4096.0h * 32.0h;
        half c3 = 2392.0h / 4096.0h * 32.0h;
        
        half3 Y = pow(max(linearColor, 0.0h), m1);
        half3 L = pow((c1 + c2 * Y) / (1.0h + c3 * Y), m2);
        return L;
    }
    
    // Overload for float3 compatibility
    inline float3 LinearToPQ(float3 linearColor) {
        return float3(LinearToPQ(half3(linearColor)));
    }

} // namespace Color
} // namespace Core

#endif // CORE_COLOR_METAL
