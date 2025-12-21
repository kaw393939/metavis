// FaceEnhance.metal
// MetaVisRender
//
// AI-powered face enhancement shader for interviews and portrait video.
// IMPORTANT: This should be VERY subtle - barely noticeable enhancement.

#include <metal_stdlib>
#include "../Core/ACES.metal"
#include "../Core/Color.metal"
#include "../Core/Noise.metal"

using namespace metal;

#ifndef EFFECTS_FACE_ENHANCE_METAL
#define EFFECTS_FACE_ENHANCE_METAL

// MARK: - Uniforms

struct FaceEnhanceParams {
    float skinSmoothing;        // 0-1: bilateral filter strength (keep LOW)
    float highlightProtection;  // 0-1: highlight rolloff
    float eyeBrightening;       // 0-1: eye enhancement
    float localContrast;        // 0-1: clarity/definition
    float colorCorrection;      // 0-1: neutralize color casts
    float saturationProtection; // 0-1: prevent over-saturation
    float intensity;            // 0-1: master blend
    float debugMode;            // 0=off, 1=mask, 2=skin, 3=diff
};

// MARK: - Skin Tone Detection

namespace FaceEnhance {

/// Skin tone weight using YCbCr - better for diverse skin tones
inline float skinToneWeight(float3 rgb) {
    // Convert linear RGB to YCbCr
    float Y  = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
    float Cb = -0.1146 * rgb.r - 0.3854 * rgb.g + 0.5 * rgb.b + 0.5;
    float Cr = 0.5 * rgb.r - 0.4542 * rgb.g - 0.0458 * rgb.b + 0.5;
    
    // Skin cluster in Cb-Cr space (wide ellipse for all skin tones)
    float2 skinCenter = float2(0.38, 0.56);
    float2 skinRadius = float2(0.14, 0.18);
    
    float2 dist = (float2(Cb, Cr) - skinCenter) / skinRadius;
    float ellipseDist = length(dist);
    
    // Soft falloff
    float skinWeight = saturate(1.0 - smoothstep(0.5, 1.3, ellipseDist));
    
    // Reduce for very dark/bright
    float lumaWeight = smoothstep(0.03, 0.15, Y) * smoothstep(0.98, 0.88, Y);
    
    return skinWeight * lumaWeight;
}

// MARK: - VERY Gentle Bilateral Filter

/// Minimal bilateral filter - just takes the edge off, preserves texture
inline float3 bilateralFilter(
    texture2d<float, access::sample> src,
    sampler s,
    float2 uv,
    float2 texelSize,
    float strength
) {
    float3 centerColor = src.sample(s, uv).rgb;
    
    // At strength 0.15, we want MINIMAL blur
    // spatialSigma controls sample spread
    // rangeSigma controls edge preservation (smaller = more edges kept)
    float spatialMult = 0.5 + strength * 0.5;  // 0.5 to 1.0 texel spread
    float rangeSigma = 0.02 + strength * 0.03;  // 0.02 to 0.05 (very tight)
    
    float3 sum = centerColor;
    float weightSum = 1.0;
    
    // Only 4-tap cross pattern for minimal blur
    const float offsets[4] = {-1.0, 1.0, -1.0, 1.0};
    const float2 dirs[4] = {float2(1,0), float2(1,0), float2(0,1), float2(0,1)};
    
    for (int i = 0; i < 4; ++i) {
        float2 offset = dirs[i] * offsets[i] * texelSize * spatialMult;
        float3 sampleColor = src.sample(s, uv + offset).rgb;
        
        float3 colorDiff = sampleColor - centerColor;
        float colorDist = length(colorDiff);
        float rangeWeight = exp(-colorDist * colorDist / (2.0 * rangeSigma * rangeSigma));
        
        // Very low spatial weight
        float spatialWeight = 0.25;
        float weight = spatialWeight * rangeWeight;
        
        sum += sampleColor * weight;
        weightSum += weight;
    }
    
    return sum / weightSum;
}

// MARK: - Highlight Protection (Late Knee)

inline float3 protectHighlights(float3 color, float strength) {
    float luma = Core::Color::luminance(color);
    
    // Very late knee at 0.9 - only compress truly bright areas
    float knee = 0.90;
    
    if (luma > knee) {
        float excess = luma - knee;
        float range = 1.0 - knee;
        float normalized = excess / range;
        float compressed = normalized / (1.0 + normalized * strength * 0.5);
        float newLuma = knee + compressed * range;
        color *= newLuma / max(luma, 0.0001);
    }
    
    return color;
}

// MARK: - Minimal Local Contrast

inline float3 enhanceLocalContrast(float3 center, float3 blurred, float strength) {
    float3 highFreq = center - blurred;
    return center + highFreq * strength * 0.15;  // Very subtle
}

// MARK: - Color Correction (Minimal)

inline float3 correctSkinColor(float3 color, float strength) {
    if (strength < 0.05) return color;
    
    float3 hsl = Core::Color::rgbToHsl(color);
    float targetHue = 0.08;
    float hueDiff = hsl.x - targetHue;
    if (hueDiff > 0.5) hueDiff -= 1.0;
    if (hueDiff < -0.5) hueDiff += 1.0;
    
    if (abs(hueDiff) > 0.06) {
        hsl.x -= hueDiff * strength * 0.1;
        if (hsl.x < 0.0) hsl.x += 1.0;
        if (hsl.x > 1.0) hsl.x -= 1.0;
    }
    
    return Core::Color::hslToRgb(hsl);
}

// MARK: - Saturation Protection

inline float3 protectSaturation(float3 color, float strength) {
    float3 hsl = Core::Color::rgbToHsl(color);
    float maxSat = 0.6 - strength * 0.1;
    
    if (hsl.y > maxSat) {
        float excess = hsl.y - maxSat;
        hsl.y = maxSat + excess * (1.0 - strength * 0.3);
    }
    
    return Core::Color::hslToRgb(hsl);
}

} // namespace FaceEnhance

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
    
    // Sample face mask
    float mask = faceMask.sample(s, uv).r;
    
    // DEBUG MODE 1: Show mask as green overlay
    if (params.debugMode >= 0.5 && params.debugMode < 1.5) {
        float3 debugColor = mix(color, float3(0.0, 1.0, 0.0), mask * 0.6);
        dest.write(float4(debugColor, 1.0), gid);
        return;
    }
    
    // DEBUG MODE 2: Show skin detection as orange overlay
    if (params.debugMode >= 1.5 && params.debugMode < 2.5) {
        float skinWeight = FaceEnhance::skinToneWeight(color);
        float3 debugColor = mix(color, float3(1.0, 0.5, 0.0), skinWeight * mask * 0.6);
        dest.write(float4(debugColor, 1.0), gid);
        return;
    }
    
    // Early out if no mask or effect disabled
    if (mask < 0.01 || params.intensity < 0.01) {
        dest.write(sourceColor, gid);
        return;
    }
    
    // Get skin weight
    float skinWeight = FaceEnhance::skinToneWeight(color);
    float combinedMask = sqrt(mask * max(skinWeight, 0.3));  // Don't let skin weight go too low
    
    float3 enhanced = color;
    
    // 1. Very gentle smoothing
    if (params.skinSmoothing > 0.01) {
        float3 smoothed = FaceEnhance::bilateralFilter(source, s, uv, texelSize, params.skinSmoothing);
        float smoothBlend = combinedMask * params.skinSmoothing * 0.4;  // Max 40% blend
        enhanced = mix(enhanced, smoothed, smoothBlend);
    }
    
    // 2. Highlight protection
    if (params.highlightProtection > 0.01) {
        float3 protected_c = FaceEnhance::protectHighlights(enhanced, params.highlightProtection);
        enhanced = mix(enhanced, protected_c, mask * params.highlightProtection * 0.5);
    }
    
    // 3. Local contrast
    if (params.localContrast > 0.01) {
        float3 blurred = float3(0.0);
        float samples = 0.0;
        for (int dy = -2; dy <= 2; ++dy) {
            for (int dx = -2; dx <= 2; ++dx) {
                float2 offset = float2(dx, dy) * texelSize * 3.0;
                blurred += source.sample(s, uv + offset).rgb;
                samples += 1.0;
            }
        }
        blurred /= samples;
        float3 contrasted = FaceEnhance::enhanceLocalContrast(enhanced, blurred, params.localContrast);
        enhanced = mix(enhanced, contrasted, mask * params.localContrast * 0.4);
    }
    
    // 4. Color correction
    if (params.colorCorrection > 0.01) {
        float3 corrected = FaceEnhance::correctSkinColor(enhanced, params.colorCorrection);
        enhanced = mix(enhanced, corrected, combinedMask * params.colorCorrection * 0.3);
    }
    
    // 5. Saturation protection
    if (params.saturationProtection > 0.01) {
        float3 satProtected = FaceEnhance::protectSaturation(enhanced, params.saturationProtection);
        enhanced = mix(enhanced, satProtected, combinedMask * params.saturationProtection * 0.4);
    }
    
    // Final blend with master intensity
    float3 finalColor = mix(color, enhanced, params.intensity * mask);
    
    // DEBUG MODE 3: Amplified difference
    if (params.debugMode >= 2.5) {
        float3 diff = (finalColor - color) * 10.0 + 0.5;
        dest.write(float4(diff, 1.0), gid);
        return;
    }
    
    // Dither
    float dither = Core::Noise::interleavedGradientNoise(float2(gid));
    finalColor += (dither - 0.5) / 255.0;
    
    dest.write(float4(finalColor, sourceColor.a), gid);
}

// MARK: - Face Mask Generation

kernel void fx_generate_face_mask(
    texture2d<float, access::write> mask [[texture(0)]],
    constant float4* faceRects [[buffer(0)]],
    constant uint& faceCount [[buffer(1)]],
    constant float& featherAmount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= mask.get_width() || gid.y >= mask.get_height()) return;
    
    float2 uv = (float2(gid) + 0.5) / float2(mask.get_width(), mask.get_height());
    uv.y = 1.0 - uv.y;  // Flip Y for Vision coordinates
    
    float maxMask = 0.0;
    
    for (uint i = 0; i < faceCount && i < 16; ++i) {
        float4 rect = faceRects[i];
        float2 center = rect.xy + rect.zw * 0.5;
        
        // Expand more vertically (especially upward for forehead/scalp)
        // This helps with bald heads and forehead highlights
        float2 halfSize = rect.zw * 0.5;
        halfSize.x *= 1.2;  // Horizontal: slight expansion
        halfSize.y *= 1.5;  // Vertical: more expansion for head/forehead
        
        // Shift center upward slightly to cover more forehead/scalp
        center.y += rect.w * 0.15;  // Move up 15% of face height
        
        float2 d = abs(uv - center) / halfSize;
        float dist = length(d) - 1.0;
        
        float feather = featherAmount * 0.4;
        float faceMask = 1.0 - smoothstep(-feather, feather, dist);
        
        maxMask = max(maxMask, faceMask);
    }
    
    mask.write(float4(maxMask), gid);
}

// MARK: - Eye Enhancement

kernel void fx_enhance_eyes(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float4* eyeRects [[buffer(0)]],
    constant uint& eyeCount [[buffer(1)]],
    constant float& brightness [[buffer(2)]],
    constant float& intensity [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(dest.get_width(), dest.get_height());
    
    float4 sourceColor = source.sample(s, uv);
    float3 color = sourceColor.rgb;
    
    float2 uvFlipped = float2(uv.x, 1.0 - uv.y);
    float eyeMask = 0.0;
    
    for (uint i = 0; i < eyeCount && i < 2; ++i) {
        float4 rect = eyeRects[i];
        float2 center = rect.xy + rect.zw * 0.5;
        float2 halfSize = rect.zw * 0.5;
        
        float2 d = abs(uvFlipped - center) / halfSize;
        float dist = length(d) - 1.0;
        float em = 1.0 - smoothstep(-0.1, 0.1, dist);
        eyeMask = max(eyeMask, em);
    }
    
    if (eyeMask > 0.01) {
        float luma = Core::Color::luminance(color);
        if (luma > 0.5) {
            float lift = brightness * eyeMask * (luma - 0.5) * 0.5;
            color += float3(lift);
        }
    }
    
    dest.write(float4(color, sourceColor.a), gid);
}

// MARK: - Mask Combination

kernel void fx_combine_masks(
    texture2d<float, access::read> faceMask [[texture(0)]],
    texture2d<float, access::read> segmentationMask [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    float face = faceMask.read(gid).r;
    float person = segmentationMask.read(gid).r;
    
    // Multiply masks: only enhance face areas that are also part of person
    // This prevents background artifacts and tightens the mask
    float combined = face * person;
    
    output.write(float4(combined), gid);
}

#endif // EFFECTS_FACE_ENHANCE_METAL
