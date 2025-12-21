// TestShaders.metal
// MetaVis Render Tests
//
// Simple test shaders for validating the shader test framework

#include <metal_stdlib>
#include "Core/ACES.metal"
using namespace metal;

// Simple passthrough shader for framework testing
kernel void test_passthrough(
    texture2d<half, access::read> input [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    half4 color = input.read(gid);
    output.write(color, gid);
}

// Real ACES pipeline test shader (uses ACES.metal functions)
// Input: ACEScg scene-linear
// Output: Rec.709 display-encoded (sRGB/gamma)
kernel void test_aces_pipeline(
    texture2d<half, access::read> input [[texture(0)]],
    texture2d<half, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    half4 inputColor = input.read(gid);
    
    // Convert half to float for ACES processing
    float3 acescg = float3(inputColor.rgb);
    
    // Apply full ACES RRT + Rec.709 ODT pipeline
    float3 rec709 = Core::ACES::ACEScg_to_Rec709_SDR(acescg);
    
    // Write back as half
    output.write(half4(half3(rec709), inputColor.a), gid);
}

// Solid color shader for testing
kernel void test_solid_color(
    texture2d<half, access::write> output [[texture(0)]],
    constant float3 *color [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    half3 c = half3(color[0]);
    output.write(half4(c, 1.0h), gid);
}

// Gradient shader for testing
kernel void test_gradient(
    texture2d<half, access::write> output [[texture(0)]],
    constant float3 *colors [[buffer(0)]],  // [0] = start, [1] = end
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float t = float(gid.x) / float(output.get_width() - 1);
    float3 startColor = colors[0];
    float3 endColor = colors[1];
    
    float3 color = mix(startColor, endColor, t);
    output.write(half4(half3(color), 1.0h), gid);
}
