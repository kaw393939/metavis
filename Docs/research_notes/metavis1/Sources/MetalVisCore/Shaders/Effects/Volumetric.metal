#include <metal_stdlib>
#include "../Core/Noise.metal"

using namespace metal;

// MARK: - Volumetric Light (Screen-Space God Rays)
// Screen-space raymarching from a light source to simulate atmospheric scattering
// NOTE: This is a 2D approximation and does not respect depth occlusion.
// For true volumetric fog, a 3D texture or depth-aware raymarch is required.

struct VolumetricParams {
    float2 lightPosition; // Normalized (0.5, 0.5 is center)
    float density;        // Ray step size / density
    float decay;          // Falloff per step
    float weight;         // Intensity of samples
    float exposure;       // Final brightness scaling
    int samples;          // Number of samples (e.g. 50-100)
    float lightDepth;     // Depth of the light source (NDC)
    float3 color;         // Volumetric color tint
};

kernel void fx_volumetric_light(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    texture2d<float, access::sample> depthTexture [[texture(2)]],
    constant VolumetricParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / resolution;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    // Calculate vector from pixel to light source
    float2 deltaTextCoord = uv - params.lightPosition;
    
    // Divide by number of samples for density
    // We clamp samples to avoid infinite loops if params are bad, but loop is fixed below
    deltaTextCoord *= 1.0 / float(params.samples) * params.density;
    
    float2 coord = uv;
    
    // Apply Dithering to start position to break up banding steps
    float jitter = Core::Noise::interleavedGradientNoise(float2(gid));
    coord -= deltaTextCoord * jitter;

    half illuminationDecay = 1.0h;
    half4 accumColor = half4(0.0h);
    
    // Ray Marching
    // Use fixed max samples to allow partial unrolling and better optimization
    const int MAX_SAMPLES = 100;
    
    for (int i = 0; i < MAX_SAMPLES; i++) {
        if (i >= params.samples) break;
        
        // Step towards light
        coord -= deltaTextCoord;
        
        // Depth Occlusion Check
        // If the sample point is occluded by foreground geometry, it shouldn't contribute light
        float sampleDepth = depthTexture.sample(s, coord).r;
        
        // In Metal, depth is 0 (near) to 1 (far) usually, or reverse depending on setup.
        // Assuming standard 0..1 depth.
        // If sampleDepth < lightDepth, the geometry is closer than the light.
        // This means the light ray is blocked by this object.
        if (sampleDepth < params.lightDepth) {
            sampleDepth = 0.0; // Dummy op to prevent optimization if needed
            // Break or reduce weight?
            // If we break, we get hard shadows.
            // If we multiply by 0, we get no light from this sample.
            illuminationDecay *= 0.0h; // Hard shadow
        }
        
        // Sample occlusion/brightness map
        half4 sample = half4(sourceTexture.sample(s, coord));
        
        // Accumulate weighted sample
        sample *= illuminationDecay * half(params.weight);
        accumColor += sample;
        
        // Decay light energy as we step
        illuminationDecay *= half(params.decay);
    }
    
    destTexture.write(float4(float3(accumColor.rgb) * params.color, float(accumColor.a)) * params.exposure, gid);
}
