#include <metal_stdlib>
#include "ColorSpace.metal"
#include "ACES.metal"

using namespace metal;

// MARK: - Tone Mapping

// ACES Filmic Tone Mapping (SDR)
kernel void fx_tonemap_aces(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &exposure [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 color = sourceTexture.sample(s, uv);
    float3 x = color.rgb * exp2(exposure); // Apply exposure
    
    // ACEScg -> Rec.709 Linear
    // Narkowicz curve expects Rec.709 primaries
    x = float3x3(MAT_ACEScg_to_Rec709) * x;
    
    // ACES approximation (Narkowicz 2015)
    float3 mapped = ACESFilm(x);
    
    // Gamma correction (Linear -> sRGB)
    float3 finalColor = pow(mapped, float3(1.0 / 2.2));
    
    destTexture.write(float4(finalColor, color.a), gid);
}

// PQ Tone Mapping (HDR)
kernel void fx_tonemap_pq(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &maxNits [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 color = sourceTexture.sample(s, uv);
    
    // Use ACES library helper for the full chain
    float3 pqColor = Core::ACES::ACEScg_to_Rec2020_PQ(color.rgb, maxNits);
    
    destTexture.write(float4(pqColor, color.a), gid);
}

// MARK: - Display ODTs (terminal transforms)

// Output Device Transform: ACEScg Linear -> Rec.2020 PQ (HDR)
// NOTE: This is a Sprint 24k integration hook.
// The underlying mapping is intentionally a placeholder until the full ACES 1.3 RRT/ODT chain lands.
kernel void odt_acescg_to_pq1000(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    float4 pixel = source.read(gid);
    float3 pq = Core::ACES::ACEScg_to_Rec2020_PQ(pixel.rgb, 1000.0);

    // Force opaque alpha for video export pipelines.
    dest.write(float4(pq, 1.0), gid);
}

// Tunable HDR PQ1000 ODT (shader fallback experimentation)
// Parameters:
// - maxNits: mastering peak, typically 1000
// - pqScale: multiplier applied before PQ (default-ish 0.1)
// - highlightDesat: 0..1, desaturate as luminance increases
kernel void odt_acescg_to_pq1000_tuned(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &maxNits [[buffer(0)]],
    constant float &pqScale [[buffer(1)]],
    constant float &highlightDesat [[buffer(2)]],
    constant float &kneeNits [[buffer(3)]],
    constant float &gamutCompress [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    float4 pixel = source.read(gid);

    // 1) Approximate RRT in the working space.
    float3 rrt = Core::ACES::ACES_RRT(pixel.rgb);

    // 2) Convert to Rec.2020 display primaries (linear).
    float3 rec2020Linear = float3x3(MAT_ACEScg_to_Rec2020) * rrt;
    rec2020Linear = max(rec2020Linear, 0.0);

    // 2b) Luminance-preserving chroma compression (very lightweight RGC-ish behavior).
    // Do the gating in approximate display-nits so it actually engages for HDR highlights.
    float gc = clamp(gamutCompress, 0.0, 1.0);
    if (gc > 0.0) {
        float luma2020 = dot(rec2020Linear, float3(0.2627, 0.6780, 0.0593));

        // Approximate absolute brightness *before* the knee: this is what matters for HDR ODT behavior.
        float lumaNits = luma2020 * maxNits * pqScale;
        float tLum = smoothstep(100.0, 600.0, max(lumaNits, 0.0));

        // Conservative defaults: focus compression on bright, saturated values.
        float strength = gc * tLum;
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

    // 3) Simple highlight-dependent desaturation (helps reduce hue skews vs LUT in bright patches).
    float luma = dot(rec2020Linear, float3(0.2627, 0.6780, 0.0593));
    float t = clamp(luma / 1.0, 0.0, 1.0);
    float desatAmount = clamp(highlightDesat * t, 0.0, 1.0);
    rec2020Linear = mix(rec2020Linear, float3(luma), desatAmount);

    // 4) Map to absolute nits.
    // Preserve baseline-ish shadows to avoid black-patch outliers while still letting pqScale tune highlights.
    float lumaN = dot(rec2020Linear, float3(0.2627, 0.6780, 0.0593));
    float tScale = smoothstep(0.02, 0.20, max(lumaN, 0.0));
    const float pqScaleShadow = 0.10; // baseline-ish
    float pqScaleEff = mix(pqScaleShadow, pqScale, tScale);
    float3 nits = rec2020Linear * maxNits * pqScaleEff;

    // 5) Soft highlight compression (component-wise) above a knee.
    float knee = max(kneeNits, 1.0);
    nits = nits / (1.0 + (nits / knee));

    float3 pqLinear = nits / 10000.0;
    float3 pq = Linear_to_PQ(pqLinear);

    dest.write(float4(pq, 1.0), gid);
}
