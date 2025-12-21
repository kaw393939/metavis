#include <metal_stdlib>
#include "../Core/Noise.metal"
using namespace metal;

// MARK: - Physical Vignette
// Implements Natural Vignetting (Cos^4 Law) based on physical sensor/lens data

namespace Effects {
namespace Vignette {

struct Params {
    float sensorWidth; // mm
    float focalLength; // mm
    float intensity;   // 0.0 to 1.0 (Scaling factor for artistic control)
    float smoothness;  // V6.3: Controls falloff curve (0.0=Hard, 1.0=Soft/Physical)
    float roundness;   // V6.3: Controls shape (0.0=Rectangular, 1.0=Circular)
    float padding;
};

// Apply Vignette
// uv: Normalized UV coordinates (0-1)
// aspect: Aspect ratio (width/height)
inline float CalculateFalloff(float2 uv, float aspect, float sensorWidth, float focalLength, float smoothness, float roundness) {
    // Center UVs (-0.5 to 0.5)
    float2 p = uv - 0.5;
    
    // Roundness Logic
    // roundness=1.0 -> Circular (Physical) -> use aspect ratio correction
    // roundness=0.0 -> Rectangular -> ignore aspect ratio correction (distance is max(x, y))
    // We blend the coordinate space itself.
    
    // Physical (Circular) coords
    float2 pos_mm_circ = float2(p.x * sensorWidth, p.y * (sensorWidth / aspect));
    
    // Rectangular coords (scaled to fit sensor width)
    float2 pos_mm_rect = float2(p.x * sensorWidth, p.y * sensorWidth); // No aspect correction on Y means it stretches to square in UV space?
    // Actually, rectangular vignette usually means it follows the frame borders.
    // So we want distance to be based on max(abs(x), abs(y))?
    // Let's keep it simple: Roundness blends between Elliptical (Physical) and Rectangular (Frame-hugging).
    
    // Better approach for Roundness:
    // Modify the distance metric.
    // d = length(pos) is L2 norm (Circle).
    // d = max(abs(x), abs(y)) is L-infinity norm (Square).
    
    float2 d_vec = abs(pos_mm_circ);
    float dist_circ = length(d_vec);
    float dist_rect = max(d_vec.x, d_vec.y);
    
    // Blend distance
    float dist_mm = mix(dist_rect, dist_circ, roundness);
    
    // Cos^4 Law of Illumination Falloff
    // E = E0 * cos^4(theta)
    // cos(theta) = f / sqrt(f^2 + d^2)
    
    float f = focalLength;
    float cosTheta = f / sqrt(f * f + dist_mm * dist_mm);
    
    // Smoothness Logic
    // Physical is cos^4.
    // We allow varying the power.
    // smoothness 1.0 -> power 4.0
    // smoothness 0.0 -> power 0.0 (No falloff) -> Wait, that's intensity.
    // Let's map smoothness to power: 0.5 -> 4.0, 1.0 -> 2.0 (Softer), 0.0 -> 10.0 (Harder)
    // Or just map directly: power = 4.0 / max(0.1, smoothness)
    // Let's stick to the user's likely intent:
    // "Smoothness" usually means how gradual the fade is.
    // Let's use it to interpolate the final falloff curve.
    
    float power = mix(10.0, 2.0, smoothness); // 0.0=Hard(10), 1.0=Soft(2)
    float falloff = pow(cosTheta, power);
    
    return falloff;
}

inline float3 Apply(float3 color, float2 uv, float aspect, float sensorWidth, float focalLength, float intensity, float smoothness, float roundness) {
    float falloff = CalculateFalloff(uv, aspect, sensorWidth, focalLength, smoothness, roundness);
    // Apply intensity (mix between 1.0 and physical falloff)
    float v = mix(1.0, falloff, intensity);
    return color * v;
}

} // namespace Vignette
} // namespace Effects

kernel void fx_vignette_physical(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant Effects::Vignette::Params &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / resolution;
    float aspect = resolution.x / resolution.y;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 color = sourceTexture.sample(s, uv);
    
    float3 finalColor = Effects::Vignette::Apply(color.rgb, uv, aspect, params.sensorWidth, params.focalLength, params.intensity, params.smoothness, params.roundness);
    
    // Add Micro-Noise Dithering to break up banding ("Fold Lines")
    float noise = Core::Noise::interleavedGradientNoise(float2(gid));
    // Magnitude: 1/255 is approx 0.004. We use slightly less.
    finalColor += (noise - 0.5) * 0.002;
    
    destTexture.write(float4(finalColor, color.a), gid);
}
