#include <metal_stdlib>
#include "ColorSpace.metal"

using namespace metal;

#ifndef EFFECTS_HALATION_METAL
#define EFFECTS_HALATION_METAL

// MARK: - Halation

// 1. Halation Threshold (Extracts very bright highlights)
kernel void fx_halation_threshold(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 color = sourceTexture.sample(s, uv);
    
    // Calculate luminance
    float luminance = Core::Color::luminance(color.rgb);
    
    float4 halationColor = float4(0.0);
    if (luminance > threshold) {
        // We want the color of the light source
        halationColor.rgb = color.rgb;
        halationColor.a = 1.0;
    }
    
    destTexture.write(halationColor, gid);
}

// 2. Halation Composite (Red-Orange Tinted Screen Blend)
// Uses screen blend for energy conservation while preserving warm film look
struct HalationCompositeUniforms {
    float intensity;      // 4 bytes
    float time;           // 4 bytes (was _pad1)
    int radialFalloff;    // 4 bytes (V6.3: 0=disabled, 1=enabled)
    float _pad3;          // 4 bytes padding (align to 16)
    float3 tint;          // 12 bytes (+ 4 auto-pad = 16)
    // Total: 32 bytes (matches Swift SIMD3 layout)
};

// Simple hash for dithering
float hash12(float2 p) {
	float3 p3  = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

kernel void fx_halation_composite(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::sample> halationTexture [[texture(1)]],
    texture2d<float, access::write> destTexture [[texture(2)]],
    constant HalationCompositeUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 source = sourceTexture.sample(s, uv);
    float4 halation = halationTexture.sample(s, uv);
    
    // Apply V6.3 Radial Falloff (reduces halation at edges)
    float falloffMultiplier = 1.0;
    if (uniforms.radialFalloff != 0) {
        float2 centered = uv - 0.5; // UV centered at (0, 0)
        float dist = length(centered) * 2.0; // Normalize to 0-1 (corner = ~1.414)
        // Smooth falloff: full intensity at center, fades to 0 at edges
        falloffMultiplier = 1.0 - smoothstep(0.3, 1.0, dist);
    }
    
    // Apply tint, intensity, and falloff to halation
    float3 tintedHalation = halation.rgb * uniforms.tint * uniforms.intensity * falloffMultiplier;
    
    // Additive blend for physical correctness in HDR
    float3 finalRGB = source.rgb + tintedHalation;
    
    destTexture.write(float4(finalRGB, source.a), gid);
}

#endif // EFFECTS_HALATION_METAL
