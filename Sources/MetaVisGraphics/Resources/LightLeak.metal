#include <metal_stdlib>
#include "Noise.metal"

using namespace metal;

struct LightLeakParams {
    float intensity;
    float3 tint;
    float2 position;
    float size;
    float softness;
    float angle;
    float animation;
    uint mode;
    float _padding; // Alignment
};

// MARK: - Light Leak Helper

inline float computeLeakShape(
    float2 uv,
    float2 position,
    float size,
    float softness,
    float angle,
    float animation
) {
    float2 delta = uv - position;
    
    float c = cos(angle);
    float s = sin(angle);
    float2x2 rot = float2x2(c, -s, s, c);
    delta = rot * delta;
    
    float wobble = sin(animation * 6.28318) * 0.1;
    delta.x += wobble * 0.05;
    
    float2 scaledDelta = delta / float2(size * 1.5, size);
    float dist = length(scaledDelta);
    
    // Noise variation (using Core::Noise)
    float noiseVal = Core::Noise::simplex(delta * 3.0 + animation) * 0.3; // Simplex instead of FBM to simplify
    dist += noiseVal;
    
    float leak = 1.0 - smoothstep(0.0, 1.0 + softness, dist);
    return leak;
}

kernel void cs_light_leak(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant LightLeakParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    if (params.intensity <= 0.0) {
        outTexture.write(inTexture.read(gid), gid);
        return;
    }
    
    float2 uv = float2(gid) / float2(outTexture.get_width(), outTexture.get_height());
    float4 original = inTexture.read(gid);
    
    float leakAmount = computeLeakShape(
        uv,
        params.position,
        params.size,
        params.softness,
        params.angle,
        params.animation
    );
    
    float3 leakColor = params.tint * leakAmount * params.intensity;
    
    // Simple Additive Blend for now (can expand later)
    float3 result = original.rgb + leakColor;
    
    outTexture.write(float4(result, original.a), gid);
}
