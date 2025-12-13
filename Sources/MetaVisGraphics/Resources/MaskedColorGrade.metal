#include <metal_stdlib>
#include "ColorSpace.metal"

using namespace metal;

struct MaskedColorGradeParams {
    float3 targetColor;   // Color to select (if mode == COLOR_KEY)
    float tolerance;      // Selection range
    float softness;       // Edge feather
    float hueShift;       // Shift for selected area
    float saturation;     // Saturation for selected area
    float exposure;       // Exposure for selected area
    float invertMask;     // 1.0 to invert logic
    float mode;           // 0 = Mask Input, 1 = Color Key
};

// MARK: - Helper

inline float3 adjustColor(float3 linearColor, float hueShift, float satMult, float expAdd) {
    // 1. Exposure
    float3 res = linearColor * exp2(expAdd);
    
    // 2. HSL
    float3 hsl = rgbToHsl(res);
    hsl.x += hueShift;
    if (hsl.x > 1.0) hsl.x -= 1.0;
    if (hsl.x < 0.0) hsl.x += 1.0;
    
    // Saturation
    float luma = hslToRgb(float3(hsl.x, hsl.y, hsl.z)).g; // Approximate luma from greenish channel? No.
    // Use proper luma
    // Just simpler: Convert back to RGB, then saturate.
    
    float3 rgb = hslToRgb(hsl);
    float L = Core::Color::luminance(rgb);
    rgb = mix(float3(L), rgb, satMult);
    
    return rgb;
}

kernel void fx_masked_grade(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    texture2d<float, access::sample> maskParams [[texture(2)]], // Segmentation Mask
    constant MaskedColorGradeParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 texelSize = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    
    float4 srcVal = source.sample(s, uv);
    float3 color = srcVal.rgb;
    
    float maskVal = 0.0;
    
    if (params.mode < 0.5) {
        // Mode 0: Use Input Mask Texture (Segmentation)
        maskVal = maskParams.sample(s, uv).r;
    } else {
        // Mode 1: Color Key Check
        float3 diff = abs(color - params.targetColor);
        float dist = max(diff.r, max(diff.g, diff.b)); // Box distance
        
        maskVal = 1.0 - smoothstep(params.tolerance, params.tolerance + params.softness, dist);
    }
    
    if (params.invertMask > 0.5) {
        maskVal = 1.0 - maskVal;
    }
    
    // Apply Adjustment
    float3 graded = adjustColor(color, params.hueShift, params.saturation, params.exposure);
    
    // Blend
    float3 final = mix(color, graded, maskVal);
    
    dest.write(float4(final, srcVal.a), gid);
}
