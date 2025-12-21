#include <metal_stdlib>
#include "../Core/Noise.metal"
#include "../Core/Color.metal"

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
    // If size is 1.0, we use original UVs.
    // If size is 2.0, we divide UVs by 2.0 to stretch the noise (making grains larger).
    float2 grainUV = uv / max(0.1, size);
    
    // Generate Gaussian Noise using Box-Muller Transform
    // We need two uniform random numbers [0, 1]
    // Use UV/Position as seed
    float2 seed = grainUV + float2(time * 100.0, time * 200.0);
    
    // Use Core::Noise::hash12
    float u1 = Core::Noise::hash12(seed);
    float u2 = Core::Noise::hash12(seed + float2(1000.0, 1000.0));
    
    // Avoid log(0) and log(>1) which causes NaNs in sqrt
    // Clamp to safe range [0.00001, 0.99999]
    half h_u1 = half(clamp(u1, 0.00001f, 0.99999f));
    half h_u2 = half(u2);
    
    // Box-Muller Transform
    // Returns a value with Mean 0 and StdDev 1
    // Use half precision for expensive math
    half r = sqrt(-2.0h * log(h_u1));
    half theta = 6.28318530718h * h_u2;
    half gaussian = r * cos(theta);
    
    // Luminance Masking
    // Grain is most visible in midtones and shadows (silver halide response)
    // Less visible in clipped highlights where grains are saturated
    half luminance = Core::Color::luminance(color);
    
    // Asymmetric masking: Boost shadows, full grain in midtones, reduced in highlights
    // shadows (0.0-0.5): boosted grain (mask > 1.0)
    // midtones (0.5-0.7): full grain (mask = 1.0)  
    // highlights (0.7-1.0): reduced grain (mask falls off)
    
    // Use shadowBoostParam to control the shadow boost strength
    half boost = half(shadowBoostParam);
    half shadowCurve = 1.0h + (boost - 1.0h) * (1.0h - smoothstep(0.0h, 0.5h, luminance));
    
    half highlightFalloff = smoothstep(0.7h, 1.0h, luminance);
    half mask = (1.0h - highlightFalloff * 0.7h) * shadowCurve;
    
    // Apply Grain
    // Use Additive mixing instead of Multiplicative to ensure grain is visible in shadows
    // (Film grain is due to silver halide crystals, which exist even in dark areas of the negative)
    
    // SAFETY: Clamp intensity to avoid catastrophic amplification if uniform is uninitialized
    half safeIntensity = clamp(half(intensity), 0.0h, 1.0h);
    
    half grainAmount = gaussian * safeIntensity * mask;
    
    // SAFETY: Clamp final grain amount to prevent signal destruction
    grainAmount = clamp(grainAmount, -0.5h, 0.5h);
    
    // Simple addition
    return color + grainAmount;
}

inline float3 Apply(float3 color, float2 uv, float time, float intensity, float size, float shadowBoost) {
    return float3(Apply(half3(color), uv, time, intensity, size, shadowBoost));
}

} // namespace FilmGrain
} // namespace Effects

struct FilmGrainUniforms {
    float time;
    float intensity;
    float size;        // V6.3: Grain scale
    float shadowBoost; // V6.3: Shadow sensitivity
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
