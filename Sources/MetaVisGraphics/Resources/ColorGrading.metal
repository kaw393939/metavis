#include <metal_stdlib>
#include "ACES.metal"

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
    float3 logColor = Core::ACES::Linear_to_ACEScct(color);
    
    // 2. Sample LUT
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
    float exposure;
    float contrast;
    float saturation;
    float temperature;
    float tint;
    float _padding[3];
};

kernel void fx_color_grade_simple(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant ColorGradeParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    float4 color = sourceTexture.sample(s, uv);
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

struct FalseColorParams {
    float exposure;
    float gamma;
    float _padding[2];
};

// Turbo colormap approximation (Google Turbo). Input x in [0,1].
inline float3 turboColormap(float x) {
    // Keep NaNs from poisoning the output.
    if (!isfinite(x)) {
        x = 0.0;
    }

    x = clamp(x, 0.0, 1.0);

    // Polynomial approximation (Google Turbo).
    // Reference: https://gist.github.com/mikhailov-work/0d177465a8151eb6ede1768d51d476c7
    const float4 kRedVec4 = float4(0.13572138, 4.61539260, -42.66032258, 132.13108234);
    const float4 kGreenVec4 = float4(0.09140261, 2.19418839, 4.84296658, -14.18503333);
    const float4 kBlueVec4 = float4(0.10667330, 12.64194608, -60.58204836, 110.36276771);
    const float2 kRedVec2 = float2(-152.94239396, 59.28637943);
    const float2 kGreenVec2 = float2(4.27729857, 2.82956604);
    const float2 kBlueVec2 = float2(-89.90310912, 27.34824973);

    float4 v4 = float4(1.0, x, x * x, x * x * x);
    float2 v2 = v4.zw * v4.z; // (x^4, x^5)

    float3 rgb = float3(
        dot(v4, kRedVec4) + dot(v2, kRedVec2),
        dot(v4, kGreenVec4) + dot(v2, kGreenVec2),
        dot(v4, kBlueVec4) + dot(v2, kBlueVec2)
    );

    return clamp(rgb, 0.0, 1.0);
}

kernel void fx_false_color_turbo(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant FalseColorParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    float4 c = sourceTexture.sample(s, uv);

    float3 rgbIn = c.rgb;
    // Guard against non-finite values (common in scientific data).
    rgbIn = select(float3(0.0), rgbIn, isfinite(rgbIn));

    // FITS stills are typically grayscale; take luma for robustness.
    float intensity = dot(rgbIn, float3(0.2126, 0.7152, 0.0722));
    if (!isfinite(intensity)) {
        intensity = 0.0;
    }

    intensity = max(intensity, 0.0);
    intensity *= exp2(params.exposure);
    if (!isfinite(intensity)) {
        intensity = 0.0;
    }

    // Gamma: gamma > 1 darkens; gamma < 1 brightens.
    float g = max(params.gamma, 1e-6);
    intensity = pow(intensity, 1.0 / g);
    intensity = clamp(intensity, 0.0, 1.0);

    float3 rgb = turboColormap(intensity);
    destTexture.write(float4(rgb, c.a), gid);
}
