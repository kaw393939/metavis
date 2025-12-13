#include <metal_stdlib>
#include "ColorSpace.metal"
using namespace metal;

// MARK: - Anamorphic Streaks
// Simulates horizontal lens flares characteristic of anamorphic cinematography

// 1. Anamorphic Threshold (High pass for streaks)
kernel void fx_anamorphic_threshold(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 destRes = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / destRes;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 color = sourceTexture.sample(s, uv);
    
    // Max component luminance for streaks (picks up colored brights better)
    float luminance = max(color.r, max(color.g, color.b));
    
    float4 streakColor = float4(0.0, 0.0, 0.0, 1.0);
    if (luminance > threshold) {
        streakColor.rgb = color.rgb;
    }
    
    destTexture.write(streakColor, gid);
}

// 2. Anamorphic Composite (Tinted Additive)
struct AnamorphicCompositeUniforms {
    float intensity;
    float3 tint;
    float _padding; // Alignment for float3
};

kernel void fx_anamorphic_composite(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::sample> streakTexture [[texture(1)]],
    texture2d<float, access::write> destTexture [[texture(2)]],
    constant AnamorphicCompositeUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 source = sourceTexture.sample(s, uv);
    float4 streak = streakTexture.sample(s, uv);
    
    // Additive blend with tint
    float4 finalColor = source + float4(streak.rgb * uniforms.tint * uniforms.intensity, 0.0);
    
    destTexture.write(finalColor, gid);
}
