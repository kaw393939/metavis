#include <metal_stdlib>
using namespace metal;

#ifndef EFFECTS_LENS_METAL
#define EFFECTS_LENS_METAL

namespace Lens {

    // Standard Barrel/Pincushion Distortion
    // k > 0: Barrel, k < 0: Pincushion
    inline float2 DistortUV(float2 uv, float k) {
        float2 centered = uv - 0.5;
        float r2 = dot(centered, centered);
        return centered * (1.0 + k * r2) + 0.5;
    }

    // Vignette (Physical-ish)
    inline float ApplyVignette(float2 uv, float intensity, float smoothness) {
        float2 centered = uv * 2.0 - 1.0;
        float dist = length(centered);
        return 1.0 - smoothstep(1.0 - smoothness, 1.0, dist * intensity);
    }

} // namespace Lens

// MARK: - Unified Lens System (Distortion + CA)
// Physically coupled implementation where CA follows distortion

struct LensSystemParams {
    float k1;
    float k2;
    float chromaticAberration; // Max offset at edges
    float padding;
};

kernel void fx_lens_system(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant LensSystemParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = float2(gid) / resolution;
    
    // 1. Calculate Distorted UVs (Inverse Mapping: Screen -> Source)
    // Center UVs (-0.5 to 0.5)
    half2 p = half2(uv - 0.5);
    half r2 = dot(p, p);
    half r4 = r2 * r2;
    
    // Radial Distortion: (1 - k1*r^2 - k2*r^4)
    half scale = 1.0h - half(params.k1) * r2 - half(params.k2) * r4;
    half2 distortedP = p * scale;
    
    // 2. Chromatic Aberration (Lateral Color)
    half caFactor = half(params.chromaticAberration) * r2;
    
    half2 r_uv = distortedP * (1.0h - caFactor) + 0.5h;
    half2 g_uv = distortedP + 0.5h;
    half2 b_uv = distortedP * (1.0h + caFactor) + 0.5h;
    
    // 3. Sample
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // Check bounds for Green (Anchor) to apply border
    if (g_uv.x < 0.0h || g_uv.x > 1.0h || g_uv.y < 0.0h || g_uv.y > 1.0h) {
        destTexture.write(float4(0, 0, 0, 1), gid);
        return;
    }
    
    half r = half(sourceTexture.sample(s, float2(r_uv)).r);
    half g = half(sourceTexture.sample(s, float2(g_uv)).g);
    half b = half(sourceTexture.sample(s, float2(b_uv)).b);
    half a = half(sourceTexture.sample(s, float2(g_uv)).a);
    
    destTexture.write(float4(r, g, b, a), gid);
}

// MARK: - Specific Kernels

// Brown-Conrady Distortion (Standalone)
kernel void fx_lens_distortion_brown_conrady(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float2 &kParams [[buffer(0)]], // k1, k2
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = float2(gid) / resolution;
    
    half2 p = half2(uv - 0.5);
    half r2 = dot(p, p);
    half r4 = r2 * r2;
    
    // Inverse mapping: Source = Dest * (1 - k1*r^2 - k2*r^4)
    half scale = 1.0h - half(kParams.x) * r2 - half(kParams.y) * r4;
    half2 distortedUV = p * scale + 0.5h;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    if (distortedUV.x < 0.0h || distortedUV.x > 1.0h || distortedUV.y < 0.0h || distortedUV.y > 1.0h) {
        destTexture.write(float4(0, 0, 0, 1), gid);
    } else {
        destTexture.write(sourceTexture.sample(s, float2(distortedUV)), gid);
    }
}

// Spectral Chromatic Aberration (Standalone)
kernel void fx_spectral_ca(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = float2(gid) / resolution;
    
    half2 p = half2(uv - 0.5);
    half r2 = dot(p, p);
    
    // Cubic falloff for CA
    half caFactor = half(intensity) * r2;
    
    half2 r_uv = p * (1.0h - caFactor) + 0.5h;
    half2 g_uv = p + 0.5h;
    half2 b_uv = p * (1.0h + caFactor) + 0.5h;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    half r = half(sourceTexture.sample(s, float2(r_uv)).r);
    half g = half(sourceTexture.sample(s, float2(g_uv)).g);
    half b = half(sourceTexture.sample(s, float2(b_uv)).b);
    half a = half(sourceTexture.sample(s, float2(g_uv)).a);
    
    destTexture.write(float4(r, g, b, a), gid);
}

#endif // EFFECTS_LENS_METAL
