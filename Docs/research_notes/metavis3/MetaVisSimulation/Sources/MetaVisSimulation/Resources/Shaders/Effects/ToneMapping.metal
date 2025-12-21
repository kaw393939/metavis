#include <metal_stdlib>
#include "../Core/Color.metal"
#include "../Core/ACES.metal"

using namespace metal;

// MARK: - Tone Mapping

// ACES Filmic Tone Mapping
// Approximates the ACES RRT+ODT for a cinematic look
// Preserves hue in highlights better than simple Reinhard
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
    
    half4 color = half4(sourceTexture.sample(s, uv));
    half3 x = color.rgb * half(exp2(exposure)); // Apply exposure in stops
    
    // Convert ACEScg to Rec.709 Linear
    // Narkowicz curve expects Rec.709 primaries
    x = half3x3(Core::Color::ACEScg_to_Rec709) * x;
    // x = max(x, 0.0h); // REMOVED: Clamping causes "Black Dome" artifacts in dark gradients.
    
    // ACES approximation (Narkowicz 2015)
    // Modified to preserve deep blacks better (Toe adjustment)
    half3 mapped = Core::Color::TonemapACES_Narkowicz(x);
    
    // Gamma correction (Linear -> sRGB)
    // We assume the output needs to be sRGB for display
    half3 finalColor = pow(mapped, half3(1.0h / 2.2h));
    
    // Standard Output (No Swizzle)
    destTexture.write(float4(finalColor.r, finalColor.g, finalColor.b, float(color.a)), gid);
}

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
    
    half4 color = half4(sourceTexture.sample(s, uv));
    
    // 1. Convert ACEScg -> Rec.2020 Linear
    // Transpose for Metal multiplication (vector * matrix)
    half3 rec2020 = half3x3(Core::Color::ACEScg_to_Rec2020) * color.rgb;
    
    // 2. Scale to PQ range
    // Per Phase 3 Spec: Treat input ACEScg linear as referenced to 1.0 = maxNits
    half3 nits = rec2020 * half(maxNits);
    
    // 3. Tone Mapping (Simple Reinhard-ish for HDR)
    // We want to preserve linearity for most of the range, but roll off highlights
    half shoulder = half(maxNits);
    half3 tonemappedNits = nits / (1.0h + nits / shoulder);
    
    // 4. Normalize for PQ (0-1 where 1 = 10000 nits)
    half3 pqLinear = tonemappedNits / 10000.0h;
    
    // 5. Apply PQ Curve
    half3 pqColor = Core::Color::LinearToPQ(pqLinear);
    
    destTexture.write(float4(float3(pqColor), float(color.a)), gid);
}
