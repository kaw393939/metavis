#include <metal_stdlib>
using namespace metal;

// MARK: - Compositing Utilities

// Standard Alpha Blending (Source Over Destination)
kernel void fx_composite_over(
    texture2d<float, access::sample> backgroundTexture [[texture(0)]],
    texture2d<float, access::sample> foregroundTexture [[texture(1)]],
    texture2d<float, access::write> destTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 bg = backgroundTexture.sample(s, uv);
    float4 fg = foregroundTexture.sample(s, uv);
    
    // Standard Over Operator (Premultiplied Alpha)
    // Out = FG + BG * (1 - FG.a)
    // Note: FG.rgb is already multiplied by FG.a
    float3 finalRGB = fg.rgb + bg.rgb * (1.0 - fg.a);
    float finalA = fg.a + bg.a * (1.0 - fg.a);
    
    destTexture.write(float4(finalRGB, finalA), gid);
}
