//
//  ProceduralField.metal
//  MetaVisRender
//
//  Procedural field generation kernel (FBM nebula, noise fields)
//  Extracted from FieldKernels.metal to avoid duplicate function names
//

#include <metal_stdlib>
#include "../Core/Procedural.metal"
#include "../Core/ACES.metal"
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
    int gradientColorSpace; // 0=linear (scene ACEScg), 1=display (perceptual)
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
    
    // DEBUG: Test if we can see UV gradient
    // output.write(float4(uv.x, uv.y, 0.0, 1.0), gid);
    // return;
    
    // 2. Apply domain operations
    // Start with UV, apply transformations
    float2 p = uv;
    
    // Apply frequency as base scale (controls noise detail)
    // Higher frequency = more noise cycles = smaller features
    // Typical range: 1.0-5.0 for good variation
    // The manifest has frequency=0.25 which is way too small!
    // We need to use it as a multiplier to get coordinates in a useful range
    // FIX: Interpret frequency as "zoom" - higher = more zoomed in
    // For visual variation, we want p in range ~[0, 3-5], not [0, 0.3]
    float effectiveFrequency = max(params.frequency, 0.01);  // Avoid divide by zero
    p *= (1.0 / effectiveFrequency);  // INVERT: 0.25 → 4x larger coordinates
    
    // Scale (aspect ratio adjustment)
    p = domainScale(p, params.scale);
    
    // Offset
    p += params.offset;
    
    // Rotate
    if (params.rotation != 0.0) {
        // Rotate around center
        float2 center = params.scale * 0.5 / effectiveFrequency;
        p -= center;
        p = domainRotate(p, params.rotation);
        p += center;
    }
    
    // DEBUG: Show coordinate range - should be colorful if p varies
    // output.write(float4(fract(p * 0.2), 0.0, 1.0), gid);
    // return;
    
    // 3. Domain warp (optional)
    if (params.domainWarp != 0) {
        // Generate warp field using two Perlin samples at different offsets
        // params.time is already scaled by animationSpeed, so use larger multipliers for visible motion
        float2 warpField = float2(
            perlin(p + float2(0.0, 0.0) + params.time * 1.5),
            perlin(p + float2(5.2, 1.3) + params.time * 1.5)
        );
        p = domainWarp(p, params.warpStrength, warpField);
    }
    
    // Add time offset for animation - increase multipliers for visible motion
    p += float2(params.time * 0.8, params.time * 0.6);
    
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
    
    // 7. Map to color gradient (HDR values in ACEScg)
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
    
    // 9. Output Linear ACEScg
    //
    // REVISED ARCHITECTURE (Sprint 2):
    // Procedural backgrounds are now part of the Unified ACES Pipeline.
    // They must output scene-linear ACEScg values to be composited correctly
    // with PBR materials and other elements.
    //
    // Tone mapping (RRT+ODT) happens at the very end of the pipeline (ToneMapPass).
    
    float3 outputColor;
    
    if (params.gradientColorSpace == 0) {
        // LINEAR MODE: Input is already scene-linear ACEScg
        // Pass through directly.
        
        // Safety: Clamp negatives
        outputColor = max(color, float3(0.0));
        
    } else {
        // DISPLAY MODE: Input is Display-Referred (sRGB/Rec.709 Gamma)
        // Must convert to Scene-Linear ACEScg for the pipeline.
        
        // 1. Clamp to valid display range
        float3 displayColor = clamp(color, 0.0, 1.0);
        
        // 2. Remove Gamma (Rec.709 OETF^-1) -> Linear Rec.709
        float3 linearRec709 = Core::ColorSpace::Rec709ToLinear(displayColor);
        
        // 3. Convert Primaries (Rec.709 -> ACEScg)
        outputColor = Core::ColorSpace::Rec709ToACEScg(linearRec709);
    }
    
    // Output Linear ACEScg
    // Ready for compositing in .rgba16Float pipeline
    output.write(float4(outputColor, 1.0), gid);
}
