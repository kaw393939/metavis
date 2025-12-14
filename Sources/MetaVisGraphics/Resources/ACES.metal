#include <metal_stdlib>
#include "ColorSpace.metal"

using namespace metal;

#ifndef CORE_ACES_METAL
#define CORE_ACES_METAL

// ACES 1.3 Implementation for MetaVis
namespace Core {
namespace ACES {

// MARK: - RRT Core

// ACES RRT+ODT fit by Stephen Hill
// Input: Linear ACEScg
inline float3 ACES_RRT_curve(float3 v) {
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

// MARK: - Sweeteners

inline float3 ACES_saturation_sweetener(float3 acescg, float saturation) {
    float luma = dot(acescg, Core::Color::LumaWeights);
    float3 diff = acescg - float3(luma);
    return float3(luma) + diff * saturation;
}

inline float3 ACES_glow(float3 acescg) {
    return acescg; // Placeholder
}

inline float3 ACES_red_mod(float3 acescg) {
    return acescg; // Placeholder
}

// MARK: - Unified RRT

inline float3 ACES_RRT(float3 acescg) {
    float3 x = acescg;
    x = ACES_saturation_sweetener(x, 1.0);
    x = ACES_glow(x);
    x = ACES_red_mod(x);
    x = ACES_RRT_curve(x);
    return x;
}

// MARK: - Public API (ODTs)

// ODT: Rec.709 (SDR)
inline float3 ACEScg_to_Rec709_SDR(float3 acescg) {
    float3 rrt = ACES_RRT(acescg);
    float3 linear709 = clamp(rrt, 0.0, 1.0);
    return Linear_to_sRGB(linear709);
}

// ODT: Rec.2020 (PQ HDR)
inline float3 ACEScg_to_Rec2020_PQ(float3 acescg, float maxDisplayNits) {
    const float sceneToNitsScale = maxDisplayNits;
    
    // ACEScg -> Rec.2020 Linear
    float3 rec2020Linear = float3x3(MAT_ACEScg_to_Rec2020) * acescg;
    rec2020Linear = max(rec2020Linear, 0.0);
    
    float3 nits = rec2020Linear * sceneToNitsScale;
    
    // Tone Mapping (Reinhard-ish)
    float shoulder = maxDisplayNits;
    float3 tonemappedNits = nits / (1.0 + nits / shoulder);
    
    // Normalize for PQ (0-1 where 1 = 10000 nits)
    float3 pqLinear = tonemappedNits / 10000.0; // 0-1
    return Linear_to_PQ(pqLinear);
}

// MARK: - ACEScct (Logarithmic Encoding)

constant half ACEScct_X_BRK = 0.0078125h;
constant half ACEScct_Y_BRK = 0.155251141552511h;
constant half ACEScct_A = 10.5402377416545h;
constant half ACEScct_B = 0.0729055341958355h;

inline half3 Linear_to_ACEScct(half3 lin) {
    half3 out;
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
