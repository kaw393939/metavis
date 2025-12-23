#include <metal_stdlib>
#include "ColorSpace.metal"
#include "Noise.metal"

using namespace metal;

// MARK: - Blur Kernels

// 2. Separable Gaussian Blur (Horizontal) - HIGH QUALITY
#define MAX_BLUR_RADIUS 128

kernel void fx_blur_h(
    texture2d<half, access::read> sourceTexture [[texture(0)]],
    texture2d<half, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint2 gid [[thread_position_in_grid]]
) {
    const uint width = destTexture.get_width();
    const uint height = destTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    const float effectiveRadius = min(radius, (float)MAX_BLUR_RADIUS);
    if (effectiveRadius < 0.5) {
        destTexture.write(sourceTexture.read(gid), gid);
        return;
    }

    // Gaussian Sigma: sigma = radius / 2.0
    const float sigma = max(effectiveRadius / 2.0, 0.01);
    const float twoSigmaSq = 2.0 * sigma * sigma;
    const int r = min(int(ceil(effectiveRadius)), MAX_BLUR_RADIUS);

    threadgroup half weights[(MAX_BLUR_RADIUS * 2) + 1];
    threadgroup float totalWeight;

    if (tid == 0) {
        float sum = 0.0;
        for (int i = -r; i <= r; ++i) {
            const float xf = float(i);
            const float wf = exp(-(xf * xf) / twoSigmaSq);
            weights[i + r] = half(wf);
            sum += wf;
        }
        totalWeight = sum;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    half4 accumColor = half4(0.0h);
    const int y = int(gid.y);
    const int wMax = int(width) - 1;
    for (int i = -r; i <= r; ++i) {
        const int sx = clamp(int(gid.x) + i, 0, wMax);
        const half weight = weights[i + r];
        accumColor += sourceTexture.read(uint2(uint(sx), uint(y))) * weight;
    }

    const float tw = max(totalWeight, 0.0000001);
    destTexture.write(accumColor / half(tw), gid);
}

kernel void fx_blur_v(
    texture2d<half, access::read> sourceTexture [[texture(0)]],
    texture2d<half, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint2 gid [[thread_position_in_grid]]
) {
    const uint width = destTexture.get_width();
    const uint height = destTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    const float effectiveRadius = min(radius, (float)MAX_BLUR_RADIUS);
    if (effectiveRadius < 0.5) {
        destTexture.write(sourceTexture.read(gid), gid);
        return;
    }

    const float sigma = max(effectiveRadius / 2.0, 0.01);
    const float twoSigmaSq = 2.0 * sigma * sigma;
    const int r = min(int(ceil(effectiveRadius)), MAX_BLUR_RADIUS);

    threadgroup half weights[(MAX_BLUR_RADIUS * 2) + 1];
    threadgroup float totalWeight;

    if (tid == 0) {
        float sum = 0.0;
        for (int i = -r; i <= r; ++i) {
            const float yf = float(i);
            const float wf = exp(-(yf * yf) / twoSigmaSq);
            weights[i + r] = half(wf);
            sum += wf;
        }
        totalWeight = sum;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    half4 accumColor = half4(0.0h);
    const int x = int(gid.x);
    const int hMax = int(height) - 1;
    for (int i = -r; i <= r; ++i) {
        const int sy = clamp(int(gid.y) + i, 0, hMax);
        const half weight = weights[i + r];
        accumColor += sourceTexture.read(uint2(uint(x), uint(sy))) * weight;
    }

    const float tw = max(totalWeight, 0.0000001);
    destTexture.write(accumColor / half(tw), gid);
}

// MARK: - Mip-LOD Blur (O(1))
// Approximates a large-radius blur by sampling from a mipmapped input texture.
// Expected to be used with an engine-generated mip pyramid.

kernel void fx_mip_blur(
    texture2d<half, access::sample> sourceTexture [[texture(0)]],
    texture2d<half, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    const uint width = destTexture.get_width();
    const uint height = destTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }

    // Preserve semantics for tiny radii.
    if (radius < 0.5f) {
        // Use base mip level.
        destTexture.write(sourceTexture.read(gid), gid);
        return;
    }

    // Trilinear mip sampling is the core of the O(1) blur.
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge, coord::normalized);

    float2 outSize = float2(width, height);
    float2 uv = (float2(gid) + 0.5f) / outSize;

    float maxAvailLod = float(max(0u, sourceTexture.get_num_mip_levels() - 1u));
    float desiredMaxLod = clamp(log2(max(radius, 1.0f)), 0.0f, maxAvailLod);

    // O(1) per pixel: single trilinear LOD sample.
    half4 c = sourceTexture.sample(s, uv, level(desiredMaxLod));
    destTexture.write(c, gid);
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

    // Adaptive sampling: avoid a fixed 64-sample loop for all radii.
    // Caps worst-case texture samples per pixel while preserving quality for small radii.
    const int samples = int(clamp(ceil(radius * 1.25), 8.0, 32.0));
    const float invSamples = 1.0 / float(samples);
    const float goldenAngle = 2.39996323;
    
    float c, s_val;
    s_val = sincos(goldenAngle, c);
    float2x2 rot = float2x2(c, -s_val, s_val, c);
    float2 dir = float2(1.0, 0.0); 

    for (int i = 0; i < samples; ++i) {
        float r = sqrt((float(i) + 0.5) * invSamples) * radius;
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
