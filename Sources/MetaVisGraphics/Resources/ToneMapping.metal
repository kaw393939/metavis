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
    x = float3x3(Core::Color::MAT_ACEScg_to_Rec709) * x;
    
    // ACES approximation (Narkowicz 2015)
    float3 mapped = Core::Color::ACESFilm(x);
    
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
