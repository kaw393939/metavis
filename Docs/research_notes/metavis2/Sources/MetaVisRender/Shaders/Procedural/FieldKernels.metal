//
//  FieldKernels.metal
//  MetaVisRender
//
//  Compute shaders for procedural field generation
//

#include <metal_stdlib>
#include "../Core/Procedural.metal"
using namespace metal;

// MARK: - Field Parameters

/// Parameters for procedural field generation
/// Must match Swift struct exactly (alignment!)
struct FieldParams {
    int fieldType;          // 0=Perlin, 1=Simplex, 2=Worley, 3=FBM
    float frequency;        // Base frequency multiplier
    int octaves;            // For FBM only (1-10)
    float lacunarity;       // Frequency multiplier per octave (default: 2.0)
    float gain;             // Amplitude multiplier per octave (default: 0.5)
    int domainWarp;         // Bool: apply domain warping
    float warpStrength;     // Warp displacement strength
    float2 scale;           // Scale coordinate space
    float2 offset;          // Translate coordinate space
    float rotation;         // Rotate coordinate space (radians)
    int colorCount;         // Number of gradient stops
    int loopGradient;       // Bool: wrap gradient
    float time;             // Animation time parameter
    float padding;          // Explicit padding for alignment
};

// MARK: - Procedural Field Kernel

/// Main procedural field generation kernel
kernel void fx_procedural_field(
    texture2d<float, access::write> output [[texture(0)]],
    constant FieldParams& params [[buffer(0)]],
    constant GradientStop* gradient [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Early exit for out-of-bounds threads
    uint2 textureSize = uint2(output.get_width(), output.get_height());
    if (gid.x >= textureSize.x || gid.y >= textureSize.y) {
        return;
    }
    
    // 1. Calculate UV coordinates [0, 1]
    float2 resolution = float2(textureSize);
    float2 uv = float2(gid) / resolution;
    
    // 2. Apply domain operations
    // Start with UV, apply transformations
    float2 p = uv;
    
    // Scale
    p = domainScale(p, params.scale);
    
    // Offset
    p += params.offset;
    
    // Rotate
    if (params.rotation != 0.0) {
        // Rotate around center
        float2 center = params.scale * 0.5;
        p -= center;
        p = domainRotate(p, params.rotation);
        p += center;
    }
    
    // Apply frequency
    p *= params.frequency;
    
    // 3. Domain warp (optional)
    if (params.domainWarp != 0) {
        // Generate warp field using two Perlin samples at different offsets
        float2 warpField = float2(
            perlin(p + float2(0.0, 0.0) + params.time * 0.1),
            perlin(p + float2(5.2, 1.3) + params.time * 0.1)
        );
        p = domainWarp(p, params.warpStrength, warpField);
    }
    
    // Add time offset for animation
    p += float2(params.time * 0.05, params.time * 0.03);
    
    // 4. Evaluate noise function
    float value = 0.0;
    
    switch (params.fieldType) {
        case 0: // Perlin
            value = perlin(p);
            break;
        case 1: // Simplex
            value = simplex(p);
            break;
        case 2: // Worley
            value = worley(p);
            break;
        case 3: // FBM
            value = fbm(p, params.octaves, params.lacunarity, params.gain);
            break;
        default:
            value = 0.0;
    }
    
    // 5. Safety checks
    if (isnan(value) || isinf(value)) {
        value = 0.0;
    }
    
    // 6. Remap to [0, 1]
    // Perlin/Simplex/FBM output approximately [-1, 1]
    // Worley outputs [0, 1]
    if (params.fieldType != 2) {  // Not Worley
        value = value * 0.5 + 0.5;
    }
    value = clamp(value, 0.0, 1.0);
    
    // 7. Map to color gradient
    float3 color = mapToGradient(
        value,
        gradient,
        params.colorCount,
        params.loopGradient != 0
    );
    
    // 8. Safety check for color
    if (any(isnan(color)) || any(isinf(color))) {
        color = float3(0.0);
    }
    color = clamp(color, 0.0, 10.0);  // Clamp to reasonable range for ACEScg
    
    // 9. Output with full alpha
    output.write(float4(color, 1.0), gid);
}

// MARK: - Simple Background Kernels
// NOTE: Background functions (fx_solid_background, fx_gradient_background, fx_starfield_background)
// are now exclusively defined in Background.metal to avoid duplicate function errors.
// Use Background.metal for all background rendering.
