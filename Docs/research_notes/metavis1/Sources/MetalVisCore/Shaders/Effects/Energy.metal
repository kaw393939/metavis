#include <metal_stdlib>
#include "../Core/Noise.metal"

using namespace metal;

// MARK: - Energy Field Generation

kernel void fx_energy_field(
    texture2d<float, access::write> destTexture [[texture(0)]],
    constant float &time [[buffer(0)]],
    constant float &intensity [[buffer(1)]],
    constant float &scale [[buffer(2)]],
    constant float3 &color [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(destTexture.get_width(), destTexture.get_height());
    float2 uv = float2(gid) / resolution;
    
    // Center UVs
    float2 p = (uv - 0.5) * scale;
    
    // 1. Gaussian Blob (Base Glow)
    // Elongated vertically
    float d = length(p * float2(1.0, 0.6));
    float glow = exp(-d * 4.0);
    
    // 2. Noise Layers (Subtle movement)
    // We want a "field" look, not a flame look.
    // Use simple hash/noise
    float n1 = Core::Noise::hash12(uv * 5.0 * scale + time * 0.1);
    float n2 = Core::Noise::hash12(uv * 10.0 * scale - time * 0.2);
    
    float noise = mix(n1, n2, 0.5);
    
    // 3. Composition
    // Diffuse, non-emissive (low intensity)
    float finalIntensity = (glow * 0.2 + noise * 0.05 * glow) * intensity;
    
    // Color: Deep Red/Orange (Background warmth)
    float3 finalColor = color * finalIntensity;
    
    destTexture.write(float4(finalColor, 1.0), gid);
}
