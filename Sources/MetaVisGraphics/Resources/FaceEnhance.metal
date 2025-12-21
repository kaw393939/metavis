#include <metal_stdlib>
#include "ColorSpace.metal" // Provides HSL functions globally
#include "Noise.metal"

using namespace metal;

// MARK: - Local Namespace

namespace FaceEnhance {

    // Simple skin tone weight
    inline float skinToneWeight(float3 rgb) {
        float Y  = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
        float Cb = -0.1146 * rgb.r - 0.3854 * rgb.g + 0.5 * rgb.b + 0.5;
        float Cr = 0.5 * rgb.r - 0.4542 * rgb.g - 0.0458 * rgb.b + 0.5;
        
        float2 skinCenter = float2(0.38, 0.56);
        float2 skinRadius = float2(0.14, 0.18);
        
        float2 dist = (float2(Cb, Cr) - skinCenter) / skinRadius;
        float ellipseDist = length(dist);
        
        float skinWeight = saturate(1.0 - smoothstep(0.5, 1.3, ellipseDist));
        float lumaWeight = smoothstep(0.03, 0.15, Y) * smoothstep(0.98, 0.88, Y);
        
        return skinWeight * lumaWeight;
    }
    
    inline float3 bilateralFilter(
        texture2d<float, access::sample> src,
        sampler s,
        float2 uv,
        float2 texelSize,
        float strength
    ) {
        float3 centerColor = src.sample(s, uv).rgb;
        float spatialMult = 0.5 + strength * 0.5;
        float rangeSigma = 0.02 + strength * 0.03;
        
        float3 sum = centerColor;
        float weightSum = 1.0;
        
        const float offsets[4] = {-1.0, 1.0, -1.0, 1.0};
        const float2 dirs[4] = {float2(1,0), float2(1,0), float2(0,1), float2(0,1)};
        
        for (int i = 0; i < 4; ++i) {
            float2 offset = dirs[i] * offsets[i] * texelSize * spatialMult;
            float3 sampleColor = src.sample(s, uv + offset).rgb;
            
            float3 colorDiff = sampleColor - centerColor;
            float colorDist = length(colorDiff);
            float rangeWeight = exp(-colorDist * colorDist / (2.0 * rangeSigma * rangeSigma));
            
            float spatialWeight = 0.25;
            float weight = spatialWeight * rangeWeight;
            
            sum += sampleColor * weight;
            weightSum += weight;
        }
        
        return sum / weightSum;
    }

} // namespace FaceEnhance

struct FaceEnhanceParams {
    float skinSmoothing;
    float highlightProtection;
    float eyeBrightening;
    float localContrast;
    float colorCorrection;
    float saturationProtection;
    float intensity;
    float debugMode;
};

struct BeautyEnhanceParams {
    float skinSmoothing;
    float intensity;
    float _p0;
    float _p1;
};

// MARK: - Main Kernel

kernel void fx_face_enhance(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    texture2d<float, access::sample> faceMask [[texture(2)]],
    constant FaceEnhanceParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 texelSize = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    
    float4 sourceColor = source.sample(s, uv);
    float3 color = sourceColor.rgb;
    
    // Check face mask
    float mask = faceMask.sample(s, uv).r;
    
    // Early out
    if (mask < 0.01 || params.intensity < 0.01) {
        dest.write(sourceColor, gid);
        return;
    }
    
    float skinWeight = FaceEnhance::skinToneWeight(color);
    float combinedMask = sqrt(mask * max(skinWeight, 0.3));
    
    float3 enhanced = color;
    
    // 1. Smoothing
    if (params.skinSmoothing > 0.01) {
        float3 smoothed = FaceEnhance::bilateralFilter(source, s, uv, texelSize, params.skinSmoothing);
        float smoothBlend = combinedMask * params.skinSmoothing * 0.4;
        enhanced = mix(enhanced, smoothed, smoothBlend);
    }
    
    // 2. Simplified Color Correction (using global HSL functions)
    if (params.colorCorrection > 0.01) {
        float3 hsl = rgbToHsl(enhanced);
        float targetHue = 0.08;
        float hueDiff = hsl.x - targetHue;
        if (hueDiff > 0.5) hueDiff -= 1.0;
        if (hueDiff < -0.5) hueDiff += 1.0;
        
        if (abs(hueDiff) > 0.06) {
            hsl.x -= hueDiff * params.colorCorrection * 0.1;
            if (hsl.x < 0.0) hsl.x += 1.0;
            if (hsl.x > 1.0) hsl.x -= 1.0;
            enhanced = mix(enhanced, hslToRgb(hsl), combinedMask * params.colorCorrection * 0.3);
        }
    }
    
    // Final Blend
    float3 finalColor = mix(color, enhanced, params.intensity * mask);
    
    dest.write(float4(finalColor, sourceColor.a), gid);
}

// MARK: - Simple Beauty Enhance (single-input)

kernel void fx_beauty_enhance(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant BeautyEnhanceParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 texelSize = 1.0 / float2(source.get_width(), source.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;

    float4 src = source.sample(s, uv);
    float3 color = src.rgb;

    float intensity = saturate(params.intensity);
    float smooth = saturate(params.skinSmoothing);
    if (intensity < 0.001 || smooth < 0.001) {
        dest.write(src, gid);
        return;
    }

    // Only affect likely skin-tones to avoid softening the whole frame.
    float skinWeight = FaceEnhance::skinToneWeight(color);
    if (skinWeight < 0.01) {
        dest.write(src, gid);
        return;
    }

    float3 smoothed = FaceEnhance::bilateralFilter(source, s, uv, texelSize, smooth);
    float blend = skinWeight * intensity * (0.25 + 0.55 * smooth);

    float3 outColor = mix(color, smoothed, blend);
    dest.write(float4(outColor, src.a), gid);
}
