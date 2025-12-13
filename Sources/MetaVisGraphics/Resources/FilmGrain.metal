#include <metal_stdlib>
#include "Noise.metal"
#include "ColorSpace.metal"

using namespace metal;

// MARK: - Film Grain

namespace Effects {
namespace FilmGrain {

// Apply Film Grain to a color
// color: Input color (Linear or Log)
// uv: Texture coordinates (or pixel position for noise seed)
// time: Time for animation
// intensity: Grain strength
// size: Grain scale (1.0 = pixel perfect, >1.0 = larger grains)
// shadowBoostParam: Multiplier for shadow grain
inline half3 Apply(half3 color, float2 uv, float time, float intensity, float size, float shadowBoostParam) {
    // Scale UVs by size
    float2 grainUV = uv / max(0.1, size);
    
    // Generate Gaussian Noise using Box-Muller Transform
    // Use UV/Position as seed
    float2 seed = grainUV + float2(time * 100.0, time * 200.0);
    
    // Use Core::Noise::hash12
    float u1 = Core::Noise::hash12(seed);
    float u2 = Core::Noise::hash12(seed + float2(1000.0, 1000.0));
    
    // Avoid log(0) and log(>1)
    half h_u1 = half(clamp(u1, 0.00001f, 0.99999f));
    half h_u2 = half(u2);
    
    // Box-Muller Transform
    half r = sqrt(-2.0h * log(h_u1));
    half theta = 6.28318530718h * h_u2;
    half gaussian = r * cos(theta);
    
    // Luminance Masking
    half luminance = Core::Color::luminance(float3(color)); // explicit cast if needed, or overload in ColorSpace
    
    // Asymmetric masking
    half boost = half(shadowBoostParam);
    half shadowCurve = 1.0h + (boost - 1.0h) * (1.0h - smoothstep(0.0h, 0.5h, luminance));
    
    half highlightFalloff = smoothstep(0.7h, 1.0h, luminance);
    half mask = (1.0h - highlightFalloff * 0.7h) * shadowCurve;
    
    // Apply Grain
    half safeIntensity = clamp(half(intensity), 0.0h, 1.0h);
    half grainAmount = gaussian * safeIntensity * mask;
    
    // SAFETY
    grainAmount = clamp(grainAmount, -0.5h, 0.5h);
    
    return color + grainAmount;
}

} // namespace FilmGrain
} // namespace Effects

struct FilmGrainUniforms {
    float time;
    float intensity;
    float size;
    float shadowBoost;
};

kernel void fx_film_grain(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant FilmGrainUniforms &uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 uv = (float2(gid) + 0.5) / float2(destTexture.get_width(), destTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    half4 color = half4(sourceTexture.sample(s, uv));
    
    // Use pixel coordinates for noise seed to avoid stretching
    float2 noiseUV = float2(gid); 
    
    half3 finalColor = Effects::FilmGrain::Apply(color.rgb, noiseUV, uniforms.time, uniforms.intensity, uniforms.size, uniforms.shadowBoost);
    
    destTexture.write(float4(float3(finalColor), float(color.a)), gid);
}
