#include <metal_stdlib>
#include "../Core/ACES.metal"

using namespace metal;

// MARK: - 3D LUT Color Grading

namespace Effects {
namespace ColorGrading {

// Apply 3D LUT
// color: Input color (Linear ACEScg)
// lut: 3D Texture
// intensity: Mix factor
inline float3 ApplyLUT(float3 color, texture3d<float, access::sample> lut, float intensity) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // 1. Linear ACEScg -> ACEScct (Log)
    // LUTs are usually baked for Log space to preserve range
    float3 logColor = Core::ACES::Linear_to_ACEScct(color);
    
    // 2. Sample LUT
    // Clamp coordinate to 0-1
    float3 coord = clamp(logColor, 0.0, 1.0);
    float3 lutLogColor = lut.sample(s, coord).rgb;
    
    // 3. ACEScct -> Linear ACEScg
    float3 lutLinearColor = Core::ACES::ACEScct_to_Linear(lutLogColor);
    
    return mix(color, lutLinearColor, intensity);
}

} // namespace ColorGrading
} // namespace Effects

kernel void fx_apply_lut(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    texture3d<float, access::sample> lutTexture [[texture(2)]],
    constant float &intensity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 color = sourceTexture.sample(s, uv);
    
    float3 finalRGB = Effects::ColorGrading::ApplyLUT(color.rgb, lutTexture, intensity);
    
    destTexture.write(float4(finalRGB, color.a), gid);
}
