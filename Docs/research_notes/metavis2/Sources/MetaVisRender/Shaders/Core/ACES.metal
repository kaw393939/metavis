#include <metal_stdlib>
#include "../ColorSpace.metal"
#include "Color.metal"

using namespace metal;

#ifndef CORE_ACES_METAL
#define CORE_ACES_METAL

// ACES 1.3 Implementation for MetaVis
// Based on the official ACES CTL and analytical approximations by Stephen Hill / Krzysztof Narkowicz
// but expanded for full RRT+ODT chain simulation.

namespace Core {
namespace ACES {

// MARK: - Constants

constant float3x3 AP1_to_AP0_MAT = float3x3(
    float3(0.695452241357, 0.140678696470, 0.163869062172),
    float3(0.044794563372, 0.859671118456, 0.095534318172),
    float3(-0.005526433255, 0.004027053365, 1.001499379890)
);

constant float3x3 AP0_to_AP1_MAT = float3x3(
    float3(1.451439316146, -0.236514813193, -0.214924502953),
    float3(-0.076553773396, 1.176229699833, -0.099675926437),
    float3(0.008316148426, -0.006032449791, 0.997716301365)
);

// MARK: - RRT Core

// ACES RRT+ODT fit by Stephen Hill (closer to reference than Narkowicz)
// Input: Linear ACEScg
// Output: Linear sRGB (approx) or Rec.709
inline float3 ACES_RRT_curve(float3 v) {
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

// MARK: - Sweeteners

// Saturation Sweetener
// Increases saturation in a perceptual-ish way
inline float3 ACES_saturation_sweetener(float3 acescg, float saturation) {
    // Luma coefficients for ACEScg
    float luma = dot(acescg, Core::Color::LumaACEScg);
    float3 diff = acescg - float3(luma);
    return float3(luma) + diff * saturation;
}

// Glow Sweetener (Placeholder / Subtle)
inline float3 ACES_glow(float3 acescg) {
    // v1: No-op or very subtle lift could go here.
    // For now, we keep it clean to avoid artifacts.
    return acescg;
}

// Red Modifier (Placeholder)
inline float3 ACES_red_mod(float3 acescg) {
    // v1: No-op.
    return acescg;
}

// MARK: - Unified RRT

// The main RRT function used by all SDR transforms
inline float3 ACES_RRT(float3 acescg) {
    float3 x = acescg;
    x = ACES_saturation_sweetener(x, 1.0); // Default saturation 1.0
    x = ACES_glow(x);
    x = ACES_red_mod(x);
    x = ACES_RRT_curve(x);
    return x;
}

// MARK: - Public API (ODTs)

// ODT: Rec.709 (SDR)
// Input: Linear ACEScg (AP1, scene-referred)
// Output: Rec.709 (Display Encoded, OETF applied)
inline float3 ACEScg_to_Rec709_SDR(float3 acescg) {
    // 1. RRT (produces Rec.709-like linear)
    float3 rrt = ACES_RRT(acescg);
    
    // 2. Clamp
    float3 linear709 = clamp(rrt, 0.0, 1.0);
    
    // 3. OETF
    return ColorSpace::LinearToRec709(linear709);
}

// ODT: P3-D65 (SDR)
// Input: Linear ACEScg
// Output: Display P3 (Display Encoded, sRGB-like OETF applied)
inline float3 ACEScg_to_P3D65_SDR(float3 acescg) {
    // 1. RRT (produces Rec.709-like linear)
    float3 rrt = ACES_RRT(acescg);
    
    // 2. Convert Rec.709-like linear -> XYZ -> P3 Linear
    // We treat the RRT output as if it were in Rec.709 primaries
    float3 xyz = ColorSpace::applyMatrix(ColorSpace::M_Rec709_to_XYZ, rrt);
    float3 p3Linear = ColorSpace::applyMatrix(ColorSpace::M_XYZ_to_P3D65, xyz);
    
    // 3. Clamp
    p3Linear = clamp(p3Linear, 0.0, 1.0);
    
    // 4. OETF (Display P3 uses sRGB transfer function)
    return ColorSpace::LinearToSRGB(p3Linear);
}

// ODT: Rec.2020 (PQ HDR)
// Input: Linear ACEScg
// Output: Rec.2020 PQ Encoded
// maxDisplayNits: Mastering peak (e.g. 1000 or 2000)
inline float3 ACEScg_to_Rec2020_PQ(float3 acescg, float maxDisplayNits) {
    // Per Phase 3 Spec: Treat input ACEScg linear as referenced to 1.0 = maxNits
    // This allows the input to fully utilize the target display range.
    const float sceneToNitsScale = maxDisplayNits;
    
    // 1. ACEScg -> Rec.2020 Linear
    float3 rec2020Linear = ColorSpace::ACEScgToRec2020(acescg);
    rec2020Linear = max(rec2020Linear, 0.0);
    
    // 2. Map to Nits
    float3 nits = rec2020Linear * sceneToNitsScale;
    
    // 3. Tone Mapping (Simple Reinhard-ish for HDR)
    // We want to preserve linearity for most of the range, but roll off highlights
    float shoulder = maxDisplayNits;
    float3 tonemappedNits = nits / (1.0 + nits / shoulder);
    
    // 4. Normalize for PQ (0-1 where 1 = 10000 nits)
    return ColorSpace::LinearNitsToPQ(tonemappedNits);
}

// ODT: Rec.2020 (HLG HDR)
// Input: Linear ACEScg (scene-referred)
// Output: Rec.2020 HLG Encoded (display-referred)
// This is the correct path for YouTube HDR and broadcast HDR
inline float3 ACEScg_to_Rec2020_HLG(float3 acescg) {
    // 1. Apply ACES RRT for tone mapping (scene → display transform)
    float3 rrt = ACES_RRT(acescg);
    
    // 2. Convert from RRT output (roughly Rec.709 primaries) to Rec.2020 primaries
    // RRT output is in a Rec.709-like space, convert to Rec.2020
    float3 xyz = ColorSpace::applyMatrix(ColorSpace::M_Rec709_to_XYZ, rrt);
    float3 rec2020Linear = ColorSpace::applyMatrix(ColorSpace::M_XYZ_to_Rec2020, xyz);
    
    // 3. Clamp negatives
    rec2020Linear = max(rec2020Linear, 0.0);
    
    // 4. Apply HLG OETF (Hybrid Log-Gamma transfer function)
    return ColorSpace::LinearToHLG(rec2020Linear);
}

// MARK: - ACEScct (Logarithmic Encoding for Grading/LUTs)

constant half ACEScct_X_BRK = 0.0078125h;
constant half ACEScct_Y_BRK = 0.155251141552511h;
constant half ACEScct_A = 10.5402377416545h;
constant half ACEScct_B = 0.0729055341958355h;

inline half3 Linear_to_ACEScct(half3 lin) {
    half3 out;
    // Unroll for half3
    for (int i = 0; i < 3; ++i) {
        if (lin[i] <= ACEScct_X_BRK) {
            out[i] = ACEScct_A * lin[i] + ACEScct_B;
        } else {
            out[i] = (log2(lin[i]) + 9.72h) / 17.52h;
        }
    }
    return out;
}

inline float3 Linear_to_ACEScct(float3 lin) {
    return float3(Linear_to_ACEScct(half3(lin)));
}

inline half3 ACEScct_to_Linear(half3 logC) {
    half3 out;
    for (int i = 0; i < 3; ++i) {
        if (logC[i] <= ACEScct_Y_BRK) {
            out[i] = (logC[i] - ACEScct_B) / ACEScct_A;
        } else {
            out[i] = exp2(logC[i] * 17.52h - 9.72h);
        }
    }
    return out;
}

inline float3 ACEScct_to_Linear(float3 logC) {
    return float3(ACEScct_to_Linear(half3(logC)));
}

} // namespace ACES
} // namespace Core

#endif // CORE_ACES_METAL
