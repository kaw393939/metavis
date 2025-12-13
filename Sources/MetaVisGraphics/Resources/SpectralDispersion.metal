#include <metal_stdlib>
using namespace metal;

struct SpectralDispersionParams {
    float intensity;
    float spread;
    float2 center;
    float falloff;
    float angle;
    uint samples;
    float _padding[2]; // Alignment
};

kernel void cs_spectral_dispersion(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant SpectralDispersionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) {
        return;
    }
    
    if (params.intensity <= 0.0) {
        outTexture.write(inTexture.read(gid), gid);
        return;
    }
    
    uint width = outTexture.get_width();
    uint height = outTexture.get_height();
    float2 uv = float2(gid) / float2(width, height);
    float2 delta = uv - params.center;
    
    float dist = length(delta);
    float dispersionAmount = pow(dist, params.falloff) * params.intensity;
    
    float2 dir;
    if (params.angle == 0.0) {
        dir = normalize(delta + 0.0001);
    } else {
        dir = float2(cos(params.angle), sin(params.angle));
    }
    
    // Scale spread
    float spreadPixels = params.spread * (float(height) / 1080.0);
    float spreadUV = spreadPixels / float(height);
    
    float2 offsetR = dir * (-1.0) * spreadUV * dispersionAmount;
    float2 offsetG = float2(0.0);
    float2 offsetB = dir * (1.0) * spreadUV * dispersionAmount;
    
    // Linear sampler needed for fractional offsets, but we are reading not sampling (texture2d<...read>)
    // 'read' only takes uint2. To interpolate, we need 'sample'.
    // The legacy code used 'read' with clamped integer coordinates (posR, posG, posB).
    // This is "Fast" dispersion.
    
    float2 uvR = uv + offsetR;
    float2 uvG = uv + offsetG;
    float2 uvB = uv + offsetB;
    
    uint2 posR = uint2(clamp(uvR * float2(width, height), float2(0.0), float2(width - 1, height - 1)));
    uint2 posG = uint2(clamp(uvG * float2(width, height), float2(0.0), float2(width - 1, height - 1)));
    uint2 posB = uint2(clamp(uvB * float2(width, height), float2(0.0), float2(width - 1, height - 1)));
    
    float r = inTexture.read(posR).r;
    float g = inTexture.read(posG).g;
    float b = inTexture.read(posB).b;
    float a = inTexture.read(gid).a;
    
    float3 original = inTexture.read(gid).rgb;
    float3 dispersed = float3(r, g, b);
    float3 final = mix(original, dispersed, params.intensity);
    
    outTexture.write(float4(final, a), gid);
}
