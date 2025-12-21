#include <metal_stdlib>
#include "../Core/Color.metal"
#include "../Core/QualitySettings.metal"
#include "../Core/Noise.metal"
using namespace metal;

#ifndef EFFECTS_BLUR_METAL
#define EFFECTS_BLUR_METAL

namespace Effects {
namespace Blur {

// Optimized Gaussian Kernel Weights for 13-tap separable blur
// MARK: - Constants
constant float centerWeight = 0.1125;
constant float2 blurKernel[3] = {
    float2(1.475, 0.2077), // Offset, Weight
    float2(3.440, 0.1509),
    float2(5.410, 0.0851)
};

} // namespace Blur
} // namespace Effects

// MARK: - Blur Kernels
// 2. Separable Gaussian Blur (Horizontal) - HIGH QUALITY
// Uses a dense loop with dynamic Gaussian weights to ensure perfect smoothness
// and circularity (when combined with vertical pass) at any radius.
// No more "stepping" or "grid" artifacts from sparse sampling.

#define MAX_BLUR_RADIUS 128

kernel void fx_blur_h(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    constant MVQualitySettings &quality [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // Clamp radius based on quality settings
    float effectiveRadius = min(radius, quality.blurMaxRadius);
    
    if (effectiveRadius < 0.5) {
        destTexture.write(sourceTexture.sample(s, uv), gid);
        return;
    }
    
    half4 accumColor = half4(0.0h);
    float totalWeight = 0.0;
    
    // Gaussian Sigma
    // For smoother falloff in high quality modes, we can adjust sigma.
    // Standard: sigma = radius / 2.0
    float sigma = max(effectiveRadius / 2.0, 0.01);
    float twoSigmaSq = 2.0 * sigma * sigma;
    
    // Limit loop based on quality settings (tap count) or radius
    // We use the smaller of the two to ensure performance
    int r = min(int(ceil(effectiveRadius)), MAX_BLUR_RADIUS);
    
    // Optimization: If tap count is low (Realtime), we might skip pixels?
    // For now, we stick to the dense loop but respect the max radius.
    
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

// 3. Separable Gaussian Blur (Vertical) - HIGH QUALITY
kernel void fx_blur_v(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &radius [[buffer(0)]],
    constant MVQualitySettings &quality [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float effectiveRadius = min(radius, quality.blurMaxRadius);
    
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

// MARK: - FX #9: Spectral Bloom (Wavelength-dependent Blur)
// Simulates different diffraction/scattering radii for R, G, B channels.
// Red (longer wavelength) typically blooms wider in vintage optics.
// UPDATED: Uses dense Gaussian loop for high quality.

struct SpectralBlurParams {
    float3 channelScales; // e.g. (1.0, 0.9, 0.8) for Red-wide
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
    
    // Base radius is hardcoded or passed? 
    // The original shader used fixed kernel offsets.
    // We'll assume a base radius of ~5.0 (similar to the old kernel max offset)
    // or we should add a radius parameter.
    // Since we can't change the signature easily without breaking Swift,
    // we'll assume a moderate radius of 8.0 for the base.
    float baseRadius = 8.0;
    
    float3 resultRGB = float3(0.0);
    float3 totalWeight = float3(0.0);
    
    // Add Jitter to break up combing artifacts
    float noise = Core::Noise::interleavedGradientNoise(float2(gid));
    float jitter = (noise - 0.5) * 0.5; // +/- 0.25 pixel jitter
    
    int r = 16; // Fixed loop for spectral
    
    for (int i = -r; i <= r; ++i) {
        float x = float(i) + jitter;
        float offset = x * texelSize.x;
        
        // Red
        float r_rad = baseRadius * params.channelScales.r;
        float r_sig = max(r_rad / 2.0, 0.01);
        float r_w = exp(-(x*x)/(2.0*r_sig*r_sig));
        resultRGB.r += sourceTexture.sample(s, uv + float2(offset, 0.0)).r * r_w;
        totalWeight.r += r_w;
        
        // Green
        float g_rad = baseRadius * params.channelScales.g;
        float g_sig = max(g_rad / 2.0, 0.01);
        float g_w = exp(-(x*x)/(2.0*g_sig*g_sig));
        resultRGB.g += sourceTexture.sample(s, uv + float2(offset, 0.0)).g * g_w;
        totalWeight.g += g_w;
        
        // Blue
        float b_rad = baseRadius * params.channelScales.b;
        float b_sig = max(b_rad / 2.0, 0.01);
        float b_w = exp(-(x*x)/(2.0*b_sig*b_sig));
        resultRGB.b += sourceTexture.sample(s, uv + float2(offset, 0.0)).b * b_w;
        totalWeight.b += b_w;
    }
    
    // Normalize
    resultRGB.r /= max(totalWeight.r, 0.001);
    resultRGB.g /= max(totalWeight.g, 0.001);
    resultRGB.b /= max(totalWeight.b, 0.001);
    
    destTexture.write(float4(resultRGB, 1.0), gid);
}

kernel void fx_spectral_blur_v(
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
    
    float baseRadius = 8.0;
    float3 resultRGB = float3(0.0);
    float3 totalWeight = float3(0.0);
    
    int r = 16;
    
    for (int i = -r; i <= r; ++i) {
        float y = float(i);
        float offset = y * texelSize.y;
        
        // Red
        float r_rad = baseRadius * params.channelScales.r;
        float r_sig = max(r_rad / 2.0, 0.01);
        float r_w = exp(-(y*y)/(2.0*r_sig*r_sig));
        resultRGB.r += sourceTexture.sample(s, uv + float2(0.0, offset)).r * r_w;
        totalWeight.r += r_w;
        
        // Green
        float g_rad = baseRadius * params.channelScales.g;
        float g_sig = max(g_rad / 2.0, 0.01);
        float g_w = exp(-(y*y)/(2.0*g_sig*g_sig));
        resultRGB.g += sourceTexture.sample(s, uv + float2(0.0, offset)).g * g_w;
        totalWeight.g += g_w;
        
        // Blue
        float b_rad = baseRadius * params.channelScales.b;
        float b_sig = max(b_rad / 2.0, 0.01);
        float b_w = exp(-(y*y)/(2.0*b_sig*b_sig));
        resultRGB.b += sourceTexture.sample(s, uv + float2(0.0, offset)).b * b_w;
        totalWeight.b += b_w;
    }
    
    resultRGB.r /= max(totalWeight.r, 0.001);
    resultRGB.g /= max(totalWeight.g, 0.001);
    resultRGB.b /= max(totalWeight.b, 0.001);
    
    destTexture.write(float4(resultRGB, 1.0), gid);
}

// MARK: - Camera Lens Effects

struct FocusZone {
    float zMin;
    float zMax;
    float focusDistance;
    float fStop;
};

struct DoFParams {
    float focusDistance;
    float fStop;
    float focalLength;
    float maxRadius;
    int zoneCount;
    float3 padding;
    FocusZone zones[4];
};

// Depth of Field Blur (Physically Based)
// Uses depth buffer to calculate Circle of Confusion (CoC)
kernel void fx_depth_of_field(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    texture2d<float, access::sample> depthTexture [[texture(2)]],
    constant DoFParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // 1. Calculate CoC
    float depth = depthTexture.sample(s, uv).r;
    
    // Convert depth to meters (assuming linear depth 0-1 maps to near-far)
    // This depends on projection. For now, let's assume depth is linear distance for simplicity
    // or we need near/far planes.
    // Standard Metal depth is 0-1.
    // Let's assume a simple mapping for this demo engine: 0.1m to 1000m
    // z = near * far / (far - depth * (far - near)) ? No, that's for non-linear.
    // If we used linear depth in GeometryPass, we are good.
    // Let's assume depth buffer contains linear Z for now as it's a custom engine.
    // If not, we might get weird results, but better than global blur.
    
    // Actually, GeometryPass uses standard perspective projection, so depth is non-linear.
    // z_linear = (2.0 * near * far) / (far + near - z_ndc * (far - near));
    // z_ndc = 2.0 * depth - 1.0;
    
    float near = 0.1;
    float far = 1000.0;
    float z_ndc = 2.0 * depth - 1.0;
    float z_linear = (2.0 * near * far) / (far + near - z_ndc * (far - near));
    
    // Determine Focus Parameters (Global or Zone-based)
    float currentFocusDist = params.focusDistance;
    float currentFStop = params.fStop;
    
    if (params.zoneCount > 0) {
        for (int i = 0; i < params.zoneCount; ++i) {
            if (z_linear >= params.zones[i].zMin && z_linear <= params.zones[i].zMax) {
                currentFocusDist = params.zones[i].focusDistance;
                currentFStop = params.zones[i].fStop;
                break;
            }
        }
    }
    
    // CoC Formula: A * (|z - z_focus| / z) * (f / (z_focus - f))
    // A = f / N
    float f = params.focalLength / 1000.0; // mm to m
    float A = f / currentFStop;
    float z_focus = currentFocusDist;
    
    float coc = 0.0;
    if (z_linear > 0.001) {
        float term1 = abs(z_linear - z_focus) / z_linear;
        float term2 = f / max(z_focus - f, 0.001);
        coc = A * term1 * term2; // CoC in meters
    }
    
    // Convert CoC to pixels
    // Sensor width is 36mm (0.036m). Image width is e.g. 1920.
    // pixels = coc / sensorWidth * imageWidth
    float sensorWidth = 0.036;
    float cocPixels = (coc / sensorWidth) * float(destTexture.get_width());
    
    // Clamp radius
    float radius = min(cocPixels * 0.5, params.maxRadius); // Radius is half diameter
    
    if (radius < 0.5) {
        destTexture.write(sourceTexture.sample(s, uv), gid);
        return;
    }
    
    // 2. Blur (Disk Sampling)
    half4 accumColor = half4(0.0h);
    half totalWeight = 0.0h;
    
    const int samples = 64; // Increased samples for better quality and circularity
    const float goldenAngle = 2.39996323;
    
    float c, s_val;
    s_val = sincos(goldenAngle, c);
    float2x2 rot = float2x2(c, -s_val, s_val, c);
    float2 dir = float2(1.0, 0.0); 

    for (int i = 0; i < samples; ++i) {
        float r = sqrt(float(i) / float(samples)) * radius;
        float2 offset = dir * r * texelSize;
        dir = rot * dir;
        
        half4 sample = half4(sourceTexture.sample(s, uv + offset));
        
        // Simple weight
        accumColor += sample;
        totalWeight += 1.0h;
    }
    
    if (totalWeight > 0.0h) {
        accumColor /= totalWeight;
    }
    
    destTexture.write(float4(accumColor), gid);
}

// Circular Bokeh Blur (Simulates Defocus)
// Uses a disk sampling pattern to create realistic "circles of confusion"
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
    
    half4 accumColor = half4(0.0h);
    half totalWeight = 0.0h;
    
    // Golden Angle Disk Sampling
    // Efficiently samples a disk without grid artifacts
    // UPDATED: Increased samples to 256 for Hollywood quality
    const int samples = 256; 
    const float goldenAngle = 2.39996323;
    
    // Optimization: Iterative rotation to avoid sin/cos in loop
    float c, s_val;
    s_val = sincos(goldenAngle, c);
    float2x2 rot = float2x2(c, -s_val, s_val, c);
    float2 dir = float2(1.0, 0.0); 

    for (int i = 0; i < samples; ++i) {
        float r = sqrt(float(i) / float(samples)) * radius;
        
        float2 offset = dir * r * texelSize;
        
        // Rotate for next iteration
        dir = rot * dir;
        
        // Bokeh Weighting: Brighter pixels contribute more (creates nice highlights)
        half4 sample = half4(sourceTexture.sample(s, uv + offset));
        half luminance = Core::Color::luminance(sample.rgb);
        half weight = 1.0h + luminance * 4.0h; // Increased highlight boost for more "pop"
        
        accumColor += sample * weight;
        totalWeight += weight;
    }
    
    if (totalWeight > 0.0h) {
        accumColor /= totalWeight;
    }
    
    destTexture.write(float4(accumColor), gid);
}

// Circular Halation Blur (Exponential Falloff)
// Uses a disk sampling pattern to create smooth exponential glow
kernel void fx_halation_blur_disk(
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
    
    half4 accumColor = half4(0.0h);
    half totalWeight = 0.0h;
    
    // Golden Angle Disk Sampling
    // 128 samples is sufficient for smooth glow if we use random rotation
    const int samples = 128; 
    const float goldenAngle = 2.39996323;
    
    float c, s_val;
    s_val = sincos(goldenAngle, c);
    float2x2 rot = float2x2(c, -s_val, s_val, c);
    float2 dir = float2(1.0, 0.0); 

    // Exponential decay constant
    // exp(-k * radius) = 0.0001 => k = 9.2 / radius (Smoother cutoff)
    float k = 9.2 / max(radius, 0.01);

    for (int i = 0; i < samples; ++i) {
        float r_norm = sqrt(float(i) / float(samples));
        float r = r_norm * radius;
        
        float2 offset = dir * r * texelSize;
        dir = rot * dir;
        
        half4 sample = half4(sourceTexture.sample(s, uv + offset));
        
        // Exponential weight
        half weight = half(exp(-k * r));
        
        accumColor += sample * weight;
        totalWeight += weight;
    }
    
    if (totalWeight > 0.0h) {
        accumColor /= totalWeight;
    }
    
    destTexture.write(float4(accumColor), gid);
}

// MARK: - Halation Blur (Exponential Falloff)
// Uses exponential weights for smooth glow: w(r) = exp(-k*r)
// UPDATED: Uses dense loop to avoid stepping artifacts.
// Note: Separable exponential blur creates a diamond shape.
// For circular halation, use fx_blur_h (Gaussian) or a 2D kernel.
// We keep this for legacy/stylistic "Star" halation but make it smooth.

kernel void fx_halation_blur_h(
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
    
    half4 accumColor = half4(0.0h);
    half totalWeight = 0.0h;
    
    // Exponential decay constant
    // We want weight to drop to ~0.01 at radius.
    // exp(-k * radius) = 0.01 => -k * radius = ln(0.01) = -4.6
    // k = 4.6 / radius
    float k = 4.6 / max(radius, 0.01);
    
    int r = min(int(ceil(radius)), MAX_BLUR_RADIUS);
    
    for (int i = -r; i <= r; ++i) {
        half x = half(i);
        half weight = half(exp(-k * abs(float(x))));
        
        float offset = float(x) * texelSize.x;
        accumColor += half4(sourceTexture.sample(s, uv + float2(offset, 0.0))) * weight;
        totalWeight += weight;
    }
    
    if (totalWeight > 0.0h) {
        accumColor /= totalWeight;
    }
    
    destTexture.write(float4(accumColor), gid);
}

kernel void fx_halation_blur_v(
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
    
    half4 accumColor = half4(0.0h);
    half totalWeight = 0.0h;
    
    float k = 4.6 / max(radius, 0.01);
    int r = min(int(ceil(radius)), MAX_BLUR_RADIUS);
    
    for (int i = -r; i <= r; ++i) {
        half y = half(i);
        half weight = half(exp(-k * abs(float(y))));
        
        float offset = float(y) * texelSize.y;
        accumColor += half4(sourceTexture.sample(s, uv + float2(0.0, offset))) * weight;
        totalWeight += weight;
    }
    
    if (totalWeight > 0.0h) {
        accumColor /= totalWeight;
    }
    
    destTexture.write(float4(accumColor), gid);
}

// MARK: - Anamorphic Blur (Wide Horizontal)
kernel void fx_anamorphic_blur(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &spread [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    half4 result = half4(0.0h);
    half totalWeight = 0.0h;
    
    // Wide horizontal blur (Optimized Linear Sampling)
    // We step by 2.0 pixels and sample in between to double the reach
    int samples = 16;
    for (int i = -samples; i <= samples; ++i) {
        half weight = 1.0h - (abs(half(i)) / half(samples)); // Linear falloff
        weight = weight * weight; // Exponential falloff looks better
        
        // Offset by 4.0 * i to use linear filtering and wider spread
        float offset = float(i) * 4.0 * texelSize.x * spread;
        result += half4(sourceTexture.sample(s, uv + float2(offset, 0.0))) * weight;
        totalWeight += weight;
    }
    
    if (totalWeight > 0.0h) {
        result /= totalWeight;
    }
    
    destTexture.write(float4(result), gid);
}

#endif // EFFECTS_BLUR_METAL
