#include <metal_stdlib>
using namespace metal;

// Zone Plate Test Pattern - Temporal Aliasing Detection
// Circular sinusoidal pattern that tests:
// - Spatial frequency response
// - Temporal aliasing (when animated/rotating)
// - Sub-pixel rendering accuracy
//
// Output: Linear ACEScg monochrome (will be gamma-encoded via ODT)

kernel void fx_zone_plate(
    texture2d<float, access::write> output [[texture(1)]],
    constant float& time [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    float width = float(output.get_width());
    float height = float(output.get_height());
    
    // Normalize coordinates to -1..1 with aspect ratio correction
    float2 uv = (float2(gid) / float2(width, height)) * 2.0 - 1.0;
    uv.x *= width / height;
    
    // Optional rotation for temporal aliasing test
    float theta = time * 0.5; // 0.5 rad/s rotation
    float c = cos(theta);
    float s = sin(theta);
    float2 p = float2(
        uv.x * c - uv.y * s,
        uv.x * s + uv.y * c
    );
    
    float r2 = dot(p, p);
    
    // Zone Plate formula: sin(k * r²)
    // "Breathing" frequency variation to test different spatial frequencies
    float k = 50.0 + 40.0 * sin(time * 0.2); // Varies 10-90
    
    // Sinusoidal modulation in range [0, 1]
    // Scene-linear values: 0.0 (black) to 1.0 (white reflectance)
    float val = 0.5 + 0.5 * sin(k * r2);
    
    // Output Linear ACEScg monochrome (R=G=B for neutral)
    // Will be gamma-encoded via ODT for proper display
    output.write(float4(val, val, val, 1.0), gid);
}
