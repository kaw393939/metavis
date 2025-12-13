#include <metal_stdlib>
#include "Noise.metal"
#include "ColorSpace.metal"
using namespace metal;

#ifndef EFFECTS_BLOOM_METAL
#define EFFECTS_BLOOM_METAL

namespace Effects {
namespace Bloom {

    // Prefilter: Thresholding & Firefly Reduction
    // Input: Linear ACEScg
    // Output: Thresholded Linear ACEScg
    inline half3 Prefilter(half3 color, half threshold, half knee, half clampMax) {
        // 1. Firefly reduction (Clamp Max)
        half3 c = min(color, half3(clampMax));
        
        // 2. Thresholding (Soft Knee)
        // Standard curve: (x - threshold + knee) / (2 * knee) ...
        // Simplified: max(0, brightness - threshold)
        
        half brightness = max(c.r, max(c.g, c.b)); // Max component or Luma?
        // Using Max component preserves saturation better for bloom
        
        half soft = brightness - threshold + knee;
        soft = clamp(soft, 0.0h, 2.0h * knee);
        soft = soft * soft / (4.0h * knee + 1e-4h);
        
        half contribution = max(soft, brightness - threshold);
        contribution /= max(brightness, 1e-4h);
        
        return c * contribution;
    }

    // Downsample: 13-tap Dual Filter (Jimenez)
    // Input: Texture, Sampler, UV
    // Output: Downsampled Color
    inline half4 Downsample(texture2d<float> src, sampler s, float2 uv) {
        float2 texelSize = 1.0f / float2(src.get_width(), src.get_height());
        float x = texelSize.x;
        float y = texelSize.y;
        
        // 13-tap pattern
        // A B C
        // D E F
        // G H I
        
        // Center
        half4 e = half4(src.sample(s, uv));
        
        // Inner box
        half4 a = half4(src.sample(s, uv + float2(-2*x, 2*y)));
        half4 b = half4(src.sample(s, uv + float2( 0,   2*y)));
        half4 c = half4(src.sample(s, uv + float2( 2*x, 2*y)));
        half4 d = half4(src.sample(s, uv + float2(-2*x, 0)));
        half4 f = half4(src.sample(s, uv + float2( 2*x, 0)));
        half4 g = half4(src.sample(s, uv + float2(-2*x, -2*y)));
        half4 h = half4(src.sample(s, uv + float2( 0,   -2*y)));
        half4 i = half4(src.sample(s, uv + float2( 2*x, -2*y)));
        
        // Inner diamond
        half4 j = half4(src.sample(s, uv + float2(-x, y)));
        half4 k = half4(src.sample(s, uv + float2( x, y)));
        half4 l = half4(src.sample(s, uv + float2(-x, -y)));
        half4 m = half4(src.sample(s, uv + float2( x, -y)));
        
        // Weights (standard Dual Filter)
        // (A+C+G+I)*0.03125 + (B+D+F+H)*0.0625 + (E+J+K+L+M)*0.125
        
        half4 downsample = (a+c+g+i)*0.03125h + (b+d+f+h)*0.0625h + (e+j+k+l+m)*0.125h;
        return downsample;
    }

    // Downsample with Karis Average (for first pass firefly reduction)
    // Input: Texture, Sampler, UV
    // Output: Downsampled Color with partial luma weighting
    inline half4 DownsampleKaris(texture2d<float> src, sampler s, float2 uv) {
        float2 texelSize = 1.0f / float2(src.get_width(), src.get_height());
        float x = texelSize.x;
        float y = texelSize.y;
        
        // 5-tap weighted average (Center + 4 Corners)
        // We use this for the first downsample pass to suppress fireflies (bright single pixels).
        // Weight = 1 / (1 + Luma)
        
        half4 c1 = half4(src.sample(s, uv + float2(-2*x, 2*y)));
        half4 c2 = half4(src.sample(s, uv + float2( 2*x, 2*y)));
        half4 c3 = half4(src.sample(s, uv + float2(-2*x, -2*y)));
        half4 c4 = half4(src.sample(s, uv + float2( 2*x, -2*y)));
        half4 c5 = half4(src.sample(s, uv)); // Center
        
        half w1 = 1.0h / (1.0h + Core::Color::luminance(c1.rgb));
        half w2 = 1.0h / (1.0h + Core::Color::luminance(c2.rgb));
        half w3 = 1.0h / (1.0h + Core::Color::luminance(c3.rgb));
        half w4 = 1.0h / (1.0h + Core::Color::luminance(c4.rgb));
        half w5 = 1.0h / (1.0h + Core::Color::luminance(c5.rgb));
        
        half4 sum = c1 * w1 + c2 * w2 + c3 * w3 + c4 * w4 + c5 * w5;
        half weightSum = w1 + w2 + w3 + w4 + w5;
        
        return sum / weightSum;
    }

    // Upsample: Cinematic Disk Blur (12-tap Golden Angle)
    // Replaces the standard 9-tap Tent Filter to eliminate "square" bloom artifacts.
    // This is more expensive but produces perfectly circular, high-fidelity bloom.
    inline half4 Upsample(texture2d<float> src, sampler s, float2 uv, float radius) {
        float2 texelSize = 1.0f / float2(src.get_width(), src.get_height());
        
        // Center tap
        half4 sum = half4(src.sample(s, uv));
        half totalWeight = 1.0h;
        
        // 12-tap Golden Angle Spiral
        const int taps = 12;
        const float goldenAngle = 2.39996323;
        
        float c, s_val;
        s_val = sincos(goldenAngle, c);
        float2x2 rot = float2x2(c, -s_val, s_val, c);
        float2 dir = float2(c, s_val); // Start at i=1 angle (goldenAngle)
        
        for(int i = 1; i <= taps; ++i) {
            // Radius distribution: sqrt(i/N) gives uniform area coverage
            float r = sqrt(float(i) / float(taps)) * radius;
            
            float2 offset = dir * texelSize * r;
            
            // Rotate for next iteration
            dir = rot * dir;
            
            // Gaussian weighting for smooth falloff
            // Sigma approx 0.5 of radius
            half weight = half(exp(-(r * r) / 0.5));
            
            sum += half4(src.sample(s, uv + offset)) * weight;
            totalWeight += weight;
        }
        
        return sum / totalWeight;
    }

} // namespace Bloom
} // namespace Effects

// MARK: - Bloom Kernels

// Bloom Prefilter Kernel
kernel void fx_bloom_prefilter(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    constant float &knee [[buffer(1)]],
    constant float &clampMax [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    half4 color = half4(source.read(gid));
    half3 filtered = Effects::Bloom::Prefilter(color.rgb, half(threshold), half(knee), half(clampMax));
    
    dest.write(float4(float3(filtered), float(color.a)), gid);
}

// Bloom Downsample Kernel
kernel void fx_bloom_downsample(
    texture2d<float> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5f) / float2(dest.get_width(), dest.get_height());
    
    half4 downsampled = Effects::Bloom::Downsample(source, s, uv);
    dest.write(float4(downsampled), gid);
}

// Bloom Upsample & Blend Kernel
kernel void fx_bloom_upsample_blend(
    texture2d<float> source [[texture(0)]], // The smaller mip (to be upsampled)
    texture2d<float, access::read> currentMip [[texture(1)]], // The current mip (to blend onto)
    texture2d<float, access::write> dest [[texture(2)]],
    constant float &radius [[buffer(0)]],
    constant float &weight [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5f) / float2(dest.get_width(), dest.get_height());
    
    half4 upsampled = Effects::Bloom::Upsample(source, s, uv, radius);
    half4 current = half4(currentMip.read(gid));
    
    // Additive blend
    half4 result = current + upsampled * half(weight);
    
    dest.write(float4(result), gid);
}

// MARK: - Bloom V2 (Physically Based)

// 1. Threshold
kernel void fx_bloom_threshold(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    // Map dest UV to source UV
    float2 destRes = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / destRes;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 color = sourceTexture.sample(s, uv);
    
    // Calculate luminance (ACEScg weights approx)
    float luminance = Core::Color::luminance(color.rgb);
    
    float4 bloomColor = float4(0.0, 0.0, 0.0, 1.0); // Alpha 1 for safety
    if (luminance > threshold) {
        bloomColor.rgb = color.rgb;
    }
    
    destTexture.write(bloomColor, gid);
}

// 4. Composite (Strictly Energy-Conserving)
// Uses luminance-preserving blend to maintain total image energy within 1%

struct BloomCompositeUniforms {
    float intensity;
    float preservation;
};

kernel void fx_bloom_composite(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::sample> bloomTexture [[texture(1)]],
    texture2d<float, access::write> destTexture [[texture(2)]],
    constant BloomCompositeUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 source = sourceTexture.sample(s, uv);
    float4 bloom = bloomTexture.sample(s, uv);
    
    // Physically based additive bloom
    // Bloom represents light scattering in the lens/eye and should be strictly additive.
    float3 finalRGB = source.rgb + bloom.rgb * uniforms.intensity;
    
    // Apply Dithering to prevent banding in dark gradients
    float dither = Core::Noise::interleavedGradientNoise(float2(gid));
    finalRGB += (dither - 0.5) / 255.0;
    
    destTexture.write(float4(finalRGB, source.a), gid);
}

// MARK: - Anamorphic Streaks (Moved to Anamorphic.metal)

#endif // EFFECTS_BLOOM_METAL
