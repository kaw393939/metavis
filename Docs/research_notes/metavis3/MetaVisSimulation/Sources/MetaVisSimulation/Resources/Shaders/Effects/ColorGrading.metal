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

struct ColorGradeParams {
    // 1. Input Transforms
    float exposure;      // Stops (2^exposure)
    float temperature;   // Kelvin offset (approx)
    float tint;          // Green/Magenta
    float _pad0;
    
    // 2. ASC CDL (Slope, Offset, Power)
    float3 slope;        // Multiplier (Gain)
    float _pad1;
    
    float3 offset;       // Additive (Lift-ish)
    float _pad2;
    
    float3 power;        // Gamma (Power function)
    float _pad3;
    
    // 3. Saturation
    float saturation;    // 0.0 = Grayscale, 1.0 = Normal
    
    // 4. Contrast
    float contrast;      // Contrast amount
    float contrastPivot; // Pivot point (usually 0.18 for scene linear)
    
    // 5. LUT
    float lutIntensity;  // 0.0 = Off, 1.0 = Full
};

// ACEScg Luma Coefficients (AP1 primaries)
constant float3 LUMA_ACESCG = float3(0.2722287168, 0.6740817658, 0.0536895174);

kernel void fx_color_grade_aces(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    texture3d<float, access::sample> lutTexture [[texture(2)]],
    constant ColorGradeParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 color = sourceTexture.sample(s, uv);
    float3 rgb = color.rgb;
    
    // --- 1. Input Transforms ---
    
    // Exposure (Scene Linear)
    rgb *= exp2(params.exposure);
    
    // White Balance (Simple LMS-like gain approx for now)
    // TODO: Implement full Bradford CAT based on Kelvin
    float3 wbGains = float3(1.0);
    wbGains.r += params.temperature * 0.01; // Warm/Cool
    wbGains.b -= params.temperature * 0.01;
    wbGains.g += params.tint * 0.01;        // Magenta/Green
    rgb *= wbGains;
    
    // --- 2. ASC CDL (Slope, Offset, Power) ---
    // Formula: out = (in * slope + offset)^power
    // Note: ASC CDL is usually defined on Log space, but can be applied linearly with care.
    // For "Vibe Coding", we often apply Slope/Offset in Linear, Power in Log or Linear.
    // Standard CDL is: clamp(slope * in + offset)^power
    
    // Slope
    rgb *= params.slope;
    
    // Offset
    rgb += params.offset;
    
    // Power (Gamma) - Apply safely
    // We use a safe power function that handles negatives (though scene linear shouldn't be negative usually)
    float3 power = max(params.power, 0.0001); // Prevent div by zero or negative power issues
    rgb = pow(max(rgb, 0.0), power);
    
    // --- 3. Contrast ---
    // Apply in Log space for perceptual uniformity or Linear with pivot?
    // In Scene Linear, contrast is a pivot around mid-gray (0.18)
    // Formula: (x - pivot) * contrast + pivot
    rgb = (rgb - params.contrastPivot) * params.contrast + params.contrastPivot;
    
    // --- 4. Saturation ---
    float luma = dot(rgb, LUMA_ACESCG);
    rgb = mix(float3(luma), rgb, params.saturation);
    
    // --- 5. LUT (LMT) ---
    if (params.lutIntensity > 0.0) {
        rgb = Effects::ColorGrading::ApplyLUT(rgb, lutTexture, params.lutIntensity);
    }
    
    // Clamp negatives? In ACEScg we might want to keep them for wide gamut, 
    // but for grading usually we clamp to 0.
    rgb = max(rgb, 0.0);
    
    destTexture.write(float4(rgb, color.a), gid);
}

// MARK: - Fragment Shader Version (For Render Pass)

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

fragment float4 fx_color_grade_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    texture3d<float> lutTexture [[texture(1)]],
    constant ColorGradeParams &params [[buffer(0)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = sourceTexture.sample(s, in.texCoord);
    float3 rgb = color.rgb;
    
    // --- 1. Input Transforms ---
    rgb *= exp2(params.exposure);
    
    float3 wbGains = float3(1.0);
    wbGains.r += params.temperature * 0.01;
    wbGains.b -= params.temperature * 0.01;
    wbGains.g += params.tint * 0.01;
    rgb *= wbGains;
    
    // --- 2. ASC CDL ---
    rgb *= params.slope;
    rgb += params.offset;
    float3 power = max(params.power, 0.0001);
    rgb = pow(max(rgb, 0.0), power);
    
    // --- 3. Contrast ---
    rgb = (rgb - params.contrastPivot) * params.contrast + params.contrastPivot;
    
    // --- 4. Saturation ---
    float luma = dot(rgb, LUMA_ACESCG);
    rgb = mix(float3(luma), rgb, params.saturation);
    
    // --- 5. LUT (LMT) ---
    if (params.lutIntensity > 0.0) {
        rgb = Effects::ColorGrading::ApplyLUT(rgb, lutTexture, params.lutIntensity);
    }
    
    rgb = max(rgb, 0.0);
    
    return float4(rgb, color.a);
}

kernel void fx_color_grade_simple(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant ColorGradeParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float4 color = sourceTexture.read(gid);
    float3 rgb = color.rgb;
    
    // Exposure
    rgb *= exp2(params.exposure);
    
    // Contrast
    rgb = mix(float3(0.5), rgb, params.contrast);
    
    // Saturation
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(luma), rgb, params.saturation);
    
    // Temperature/Tint (Simplified)
    rgb.r += params.temperature * 0.1;
    rgb.b -= params.temperature * 0.1;
    rgb.g += params.tint * 0.1;
    
    destTexture.write(float4(rgb, color.a), gid);
}

kernel void fx_mask_invert(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float4 color = sourceTexture.read(gid);
    // Invert the red channel (assuming mask is grayscale/red)
    float inverted = 1.0 - color.r;
    
    destTexture.write(float4(inverted, inverted, inverted, 1.0), gid);
}

kernel void fx_mask_composite(
    texture2d<float, access::sample> baseTexture [[texture(0)]],
    texture2d<float, access::sample> overlayTexture [[texture(1)]],
    texture2d<float, access::sample> maskTexture [[texture(2)]],
    texture2d<float, access::write> destTexture [[texture(3)]],
    constant float &opacity [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float4 base = baseTexture.read(gid);
    float4 overlay = overlayTexture.read(gid);
    float mask = maskTexture.read(gid).r; // Assume mask is in R channel
    
    float mixFactor = mask * opacity;
    
    float3 finalRGB = mix(base.rgb, overlay.rgb, mixFactor);
    
    destTexture.write(float4(finalRGB, base.a), gid);
}
