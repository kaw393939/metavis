#include <metal_stdlib>
#include "Color.metal"
#include "Noise.metal"
using namespace metal;

#ifndef LIGHT_EFFECTS_METAL
#define LIGHT_EFFECTS_METAL

namespace LightEffects {

    // MARK: - Halation

    // Halation Source Generation
    // Input: Source Color, Threshold, Tint
    // Output: Halation Source (to be blurred)
    inline float3 ComputeHalation(float3 srcColor, float threshold, float3 tint) {
        float brightness = Core::Color::luminance(srcColor);
        float contribution = max(0.0f, brightness - threshold);
        return srcColor * contribution * tint;
    }

    // MARK: - Volumetrics

    // God Rays (Radial Blur)
    inline float4 ComputeGodRays(
        texture2d<float> src,
        sampler s,
        float2 uv,
        float2 lightPos,
        int samples,
        float density,
        float decay,
        float weight,
        float exposure
    ) {
        float2 deltaTextCoord = (uv - lightPos);
        deltaTextCoord *= 1.0f / float(samples) * density;
        
        float2 coord = uv;
        float illuminationDecay = 1.0f;
        float4 color = float4(0.0f);
        
        for (int i = 0; i < samples; i++) {
            coord -= deltaTextCoord;
            float4 sample = src.sample(s, coord);
            
            sample *= illuminationDecay * weight;
            color += sample;
            illuminationDecay *= decay;
        }
        
        return color * exposure;
    }

} // namespace LightEffects

// MARK: - Kernels

// God Rays Kernel
kernel void fx_god_rays(
    texture2d<float> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float2 &lightPos [[buffer(0)]],
    constant float &density [[buffer(1)]],
    constant float &decay [[buffer(2)]],
    constant float &weight [[buffer(3)]],
    constant float &exposure [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5f) / float2(dest.get_width(), dest.get_height());
    
    // Fixed samples for now, or pass as constant
    int samples = 64; 
    
    float4 rays = LightEffects::ComputeGodRays(source, s, uv, lightPos, samples, density, decay, weight, exposure);
    dest.write(rays, gid);
}

// Halation Prefilter Kernel
kernel void fx_halation_prefilter(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    constant float3 &tint [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 color = source.read(gid);
    float3 halation = LightEffects::ComputeHalation(color.rgb, threshold, tint);
    
    dest.write(float4(halation, 1.0), gid);
}

// MARK: - Legacy Kernels

// Simple Gaussian Blur for Glow
// This is a separable kernel, but for simplicity in this demo we'll do a single pass box/gaussian approximation
kernel void add_glow(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &radius [[buffer(0)]],
    constant float &intensity [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    float4 color = float4(0.0);
    float totalWeight = 0.0;
    int r = int(radius);

    // Simple box blur for performance in this demo context
    // In production, use a two-pass gaussian
    for (int y = -r; y <= r; y += 2) {
        for (int x = -r; x <= r; x += 2) {
            int2 coord = int2(gid.x + x, gid.y + y);
            
            // Clamp to edge
            coord.x = max(0, min(int(source.get_width()) - 1, coord.x));
            coord.y = max(0, min(int(source.get_height()) - 1, coord.y));
            
            float weight = 1.0 / (1.0 + float(x*x + y*y)); // Distance falloff
            color += source.read(uint2(coord)) * weight;
            totalWeight += weight;
        }
    }

    float4 original = source.read(gid);
    float4 blurred = color / totalWeight;
    
    // Add glow to original
    // We only glow the alpha channel's shape
    float4 finalColor = original + (blurred * intensity);
    
    dest.write(finalColor, gid);
}

// Shimmer / Light Sweep Effect
kernel void add_shimmer(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &time [[buffer(0)]],
    constant float &intensity [[buffer(1)]],
    constant float &width [[buffer(2)]],
    constant float &angle [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) {
        return;
    }

    float4 color = source.read(gid);
    
    // Normalized coordinates
    float2 uv = float2(gid) / float2(source.get_width(), source.get_height());
    
    // Calculate direction from angle (degrees)
    float rad = angle * 3.14159 / 180.0;
    float2 dir = float2(cos(rad), sin(rad));
    
    // Project UV onto direction vector
    float pos = dot(uv, dir);
    
    // Adjust time to cycle through the projection range
    // Range of dot(uv, dir) depends on angle. Max is length(diagonal) ~ 1.414
    // We assume time goes from 0 to ~2.0 for a full sweep
    
    float dist = abs(pos - time);
    
    // Sharp band with falloff
    float shimmer = 0.0;
    
    if (dist < width) {
        shimmer = 1.0 - (dist / width);
        shimmer = pow(shimmer, 3.0); // Sharpen the peak
    }
    
    // Only apply shimmer where there is opacity
    float alpha = color.a;
    
    // Add shimmer to RGB, keeping Alpha
    float3 rgb = color.rgb + (float3(1.0, 1.0, 1.0) * shimmer * intensity * alpha);
    
    dest.write(float4(rgb, alpha), gid);
}


#endif // LIGHT_EFFECTS_METAL
