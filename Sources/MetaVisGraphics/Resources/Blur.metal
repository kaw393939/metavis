#include <metal_stdlib>
#include "ColorSpace.metal"
#include "Noise.metal"

using namespace metal;

// MARK: - Blur Kernels

// 2. Separable Gaussian Blur (Horizontal) - HIGH QUALITY
#define MAX_BLUR_RADIUS 128

kernel void fx_blur_h(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float effectiveRadius = min(radius, (float)MAX_BLUR_RADIUS);
    
    if (effectiveRadius < 0.5) {
        destTexture.write(sourceTexture.sample(s, uv), gid);
        return;
    }
    
    half4 accumColor = half4(0.0h);
    float totalWeight = 0.0;
    
    // Gaussian Sigma: sigma = radius / 2.0
    float sigma = max(effectiveRadius / 2.0, 0.01);
    float twoSigmaSq = 2.0 * sigma * sigma;
    
    int r = min(int(ceil(effectiveRadius)), MAX_BLUR_RADIUS);
    
    for (int i = -r; i <= r; ++i) {
        half x = half(i);
        half weight = half(exp(-(float(x * x)) / twoSigmaSq));
        float offset = float(x) * texelSize.x;
        accumColor += half4(sourceTexture.sample(s, uv + float2(offset, 0.0))) * weight;
        totalWeight += float(weight);
    }
    
    if (totalWeight > 0.0) {
        accumColor /= half(totalWeight);
    }
    
    destTexture.write(float4(accumColor), gid);
}

kernel void fx_blur_v(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float effectiveRadius = min(radius, (float)MAX_BLUR_RADIUS);
    
    if (effectiveRadius < 0.5) {
        destTexture.write(sourceTexture.sample(s, uv), gid);
        return;
    }
    
    half4 accumColor = half4(0.0h);
    float totalWeight = 0.0;
    float sigma = max(effectiveRadius / 2.0, 0.01);
    float twoSigmaSq = 2.0 * sigma * sigma;
    int r = min(int(ceil(effectiveRadius)), MAX_BLUR_RADIUS);
    
    for (int i = -r; i <= r; ++i) {
        half y = half(i);
        half weight = half(exp(-(float(y * y)) / twoSigmaSq));
        float offset = float(y) * texelSize.y;
        accumColor += half4(sourceTexture.sample(s, uv + float2(0.0, offset))) * weight;
        totalWeight += float(weight);
    }
    
    if (totalWeight > 0.0) {
        accumColor /= half(totalWeight);
    }
    
    destTexture.write(float4(accumColor), gid);
}

// MARK: - Spectral Bloom

struct SpectralBlurParams {
    float3 channelScales;
    float baseRadius; // Added this parameter directly to struct
};

kernel void fx_spectral_blur_h(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant SpectralBlurParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float baseRadius = params.baseRadius;
    float3 resultRGB = float3(0.0);
    float3 totalWeight = float3(0.0);
    
    float noise = Core::Noise::interleavedGradientNoise(float2(gid));
    float jitter = (noise - 0.5) * 0.5;
    
    int r = 16;
    
    for (int i = -r; i <= r; ++i) {
        float x = float(i) + jitter;
        float offset = x * texelSize.x;
        
        float r_rad = baseRadius * params.channelScales.r;
        float r_sig = max(r_rad / 2.0, 0.01);
        float r_w = exp(-(x*x)/(2.0*r_sig*r_sig));
        
        float g_rad = baseRadius * params.channelScales.g;
        float g_sig = max(g_rad / 2.0, 0.01);
        float g_w = exp(-(x*x)/(2.0*g_sig*g_sig));
        
        float b_rad = baseRadius * params.channelScales.b;
        float b_sig = max(b_rad / 2.0, 0.01);
        float b_w = exp(-(x*x)/(2.0*b_sig*b_sig));
        
        float3 sample = sourceTexture.sample(s, uv + float2(offset, 0.0)).rgb;
        resultRGB.r += sample.r * r_w;
        resultRGB.g += sample.g * g_w;
        resultRGB.b += sample.b * b_w;
        
        totalWeight.r += r_w;
        totalWeight.g += g_w;
        totalWeight.b += b_w;
    }
    
    resultRGB.r /= max(totalWeight.r, 0.001);
    resultRGB.g /= max(totalWeight.g, 0.001);
    resultRGB.b /= max(totalWeight.b, 0.001);
    
    destTexture.write(float4(resultRGB, 1.0), gid);
}

// MARK: - Bokeh Blur

kernel void fx_bokeh_blur(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    if (radius < 0.5) {
        destTexture.write(sourceTexture.sample(s, uv), gid);
        return;
    }
    
    float4 accumColor = float4(0.0);
    float totalWeight = 0.0;
    
    const int samples = 64; 
    const float goldenAngle = 2.39996323;
    
    float c, s_val;
    s_val = sincos(goldenAngle, c);
    float2x2 rot = float2x2(c, -s_val, s_val, c);
    float2 dir = float2(1.0, 0.0); 

    for (int i = 0; i < samples; ++i) {
        float r = sqrt(float(i) / float(samples)) * radius;
        float2 offset = dir * r * texelSize;
        dir = rot * dir;
        
        float4 sample = sourceTexture.sample(s, uv + offset);
        float luminance = Core::Color::luminance(sample.rgb);
        float weight = 1.0 + luminance * 4.0; 
        
        accumColor += sample * weight;
        totalWeight += weight;
    }
    
    if (totalWeight > 0.0) {
        accumColor /= totalWeight;
    }
    
    destTexture.write(accumColor, gid);
}
