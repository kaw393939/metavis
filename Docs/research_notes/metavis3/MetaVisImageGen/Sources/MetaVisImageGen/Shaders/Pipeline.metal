#include <metal_stdlib>
using namespace metal;

// --- Tone Mapping ---

// Normalizes [blackPoint, whitePoint] -> [0, 1] and applies basic stretch
kernel void toneMapKernel(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &blackPoint [[buffer(0)]],
    constant float &whitePoint [[buffer(1)]],
    constant float &gamma [[buffer(2)]], 
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    float val = inTexture.read(gid).r;
    
    // Normalize
    // Avoid division by zero
    float range = whitePoint - blackPoint;
    float norm = (range > 1e-6) ? (val - blackPoint) / range : 0.0;
    
    norm = max(0.0, norm); // Clamp bottom
    
    // Stretch (Gamma)
    // float mapped = pow(norm, 1.0/gamma);
    
    // Asinh Stretch (NASA Style)
    // y = asinh(x * stretch) / asinh(stretch)
    // We use gamma as the "stretch" factor here.
    float stretch = gamma; // e.g. 10.0 or 100.0
    float mapped = asinh(norm * stretch) / asinh(stretch);
    
    // Output is still single channel, but we write to R channel of output
    // (or RRR1 if output is RGBA, but intermediate might be R32F)
    outTexture.write(float4(mapped, 0, 0, 1.0), gid);
}

// --- Composition ---

// Adds a layer to the accumulator
// Input is single channel (mapped), Output is RGBA (ACEScg)
kernel void compositeKernel(
    texture2d<float, access::read> layerTexture [[texture(0)]],
    texture2d<float, access::read_write> accumulator [[texture(1)]],
    constant float3 &color [[buffer(0)]], // Tint color (linear)
    constant float &weight [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= accumulator.get_width() || gid.y >= accumulator.get_height()) return;
    
    float val = layerTexture.read(gid).r;
    float4 current = accumulator.read(gid);
    
    // Additive blending
    // We assume accumulator was cleared to (0,0,0,1) or (0,0,0,0) before starting
    float3 contribution = val * weight * color;
    
    accumulator.write(current + float4(contribution, 0.0), gid);
}

// --- ACES Output ---

// Narkowicz ACES approximation (commonly used for real-time)
float3 aces_tonemap(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

kernel void acesOutputKernel(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) return;
    
    float4 val = inTexture.read(gid);
    float3 color = val.rgb;
    
    // Apply ACES Tone Map
    color = aces_tonemap(color);
    
    // Gamma correct for sRGB/Rec.709 display (approx 2.2)
    color = pow(color, float3(1.0/2.2));
    
    outTexture.write(float4(color, 1.0), gid);
}
