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

inline float3 ACES_sweeteners_fast(float3 acescg) {
    // Minimal analytic sweeteners to reduce the largest LUT mismatches in fallback mode.
    // This is intentionally lightweight and not a full ACES 1.3 implementation.
    float luma = dot(acescg, Core::Color::LumaWeights);
    float3 gray = float3(luma);

    float highlight = smoothstep(1.0, 4.0, max(luma, 0.0));
    acescg = mix(acescg, gray, 0.12 * highlight);

    float maxGB = max(acescg.g, acescg.b);
    float redDom = smoothstep(0.0, 0.25, (acescg.r - maxGB));
    float sat = length(acescg - gray);
    float satW = smoothstep(0.03, 0.25, sat);
    float w = redDom * satW;
    acescg.r = mix(acescg.r, luma, 0.06 * w);
    return acescg;
}

inline float3 ACES_glow(float3 acescg) {
    // Lightweight analytic approximation of ACES glow.
    // Goal: gently lift saturated mid/high values to better match the reference RRT/ODT look.
    // This is intentionally conservative to avoid destabilizing neutrals.
    float3 x = max(acescg, 0.0);
    float luma = dot(x, Core::Color::LumaWeights);
    float3 gray = float3(luma);

    // Saturation proxy in scene-linear.
    float sat = length(x - gray);
    float satW = smoothstep(0.02, 0.20, sat);

    // Engage mostly in mid/high luminance.
    float lumW = smoothstep(0.10, 2.0, max(luma, 0.0));

    // Small gain curve.
    float gain = 1.0 + 0.06 * satW * lumW;
    return x * gain;
}

inline float3 ACES_red_mod(float3 acescg) {
    // Lightweight analytic approximation of the ACES red modifier.
    // Goal: reduce "neon" reds and hue skews in red-dominant regions.
    float3 x = max(acescg, 0.0);
    float luma = dot(x, Core::Color::LumaWeights);
    float3 gray = float3(luma);

    float maxGB = max(x.g, x.b);
    float redDom = smoothstep(0.0, 0.25, (x.r - maxGB));
    float sat = length(x - gray);
    float satW = smoothstep(0.02, 0.25, sat);
    float lumW = smoothstep(0.10, 3.0, max(luma, 0.0));

    float w = redDom * satW * lumW;
    // Pull red slightly toward luminance (preserves overall brightness).
    x.r = mix(x.r, luma, 0.10 * w);
    return x;
}

// MARK: - Unified RRT

inline float3 ACES_RRT(float3 acescg) {
    float3 x = acescg;
    x = ACES_saturation_sweetener(x, 1.0);
    x = ACES_glow(x);
    x = ACES_red_mod(x);
    x = ACES_sweeteners_fast(x);
    x = ACES_RRT_curve(x);
    return x;
}

// MARK: - Public API (ODTs)

// ODT: Rec.709 (SDR)
inline float3 ACEScg_to_Rec709_SDR(float3 acescg) {
    // Apply an RRT-like curve in ACEScg, then convert to the target display primaries.
    // NOTE: This is still an approximation until Sprint 24k lands full ACES 1.3 RRT+ODT.
    float3 rrt = ACES_RRT(acescg);

    // ACEScg -> Rec.709 linear display primaries
    float3 linear709 = float3x3(MAT_ACEScg_to_Rec709) * rrt;
    linear709 = clamp(linear709, 0.0, 1.0);
    return Linear_to_sRGB(linear709);
}

// ODT: Rec.2020 (PQ HDR)
inline float3 ACEScg_to_Rec2020_PQ(float3 acescg, float maxDisplayNits) {
    // Sprint 24k integration: avoid ad-hoc HDR tonemapping by default.
    // Map scene-referred ACEScg through an RRT-like curve, then encode as Rec.2020 PQ.
    // NOTE: This is not yet the full ACES 1.3 HDR ODT; Phase 3 replaces this with reference behavior.
    float3 rrt = ACES_RRT(acescg);

    // Convert to Rec.2020 display primaries.
    float3 rec2020Linear = float3x3(MAT_ACEScg_to_Rec2020) * rrt;
    rec2020Linear = max(rec2020Linear, 0.0);

    // Reference Gamut Compression (RGC-style) in display primaries.
    // Gate by approximate display brightness so we focus the compression on HDR highlights.
    {
        float luma2020 = dot(rec2020Linear, float3(0.2627, 0.6780, 0.0593));
        float lumaNits = luma2020 * (maxDisplayNits / 10.0);
        float tLum = smoothstep(100.0, 600.0, max(lumaNits, 0.0));

        // Conservative defaults: leave normal content alone; reduce extreme highlight saturation.
        // Note: satLimit must be > satThreshold for the knee function; values above threshold are compressed toward satLimit.
        float strength = 0.60 * tLum;
        float satThreshold = 1.20;
        float satLimit = 1.50;
        rec2020Linear = Core::Color::RGC_compress_luma_preserving(
            rec2020Linear,
            float3(0.2627, 0.6780, 0.0593),
            satThreshold,
            satLimit,
            strength
        );
        rec2020Linear = max(rec2020Linear, 0.0);
    }

    // Map to absolute luminance for PQ.
    // The fitted RRT curve yields a display-referred signal that is closer to an SDR-relative
    // (100-nit) display-linear domain than a "1.0 == peak nits" domain.
    // Using a 100-nit reference at a 1000-nit mastering peak substantially reduces mismatch
    // vs the ACES PQ1000 LUT (while keeping the function parameterized).
    float3 nits = rec2020Linear * (maxDisplayNits / 10.0);

    // Normalize for PQ (0-1 where 1 = 10000 nits).
    float3 pqLinear = nits / 10000.0;
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
