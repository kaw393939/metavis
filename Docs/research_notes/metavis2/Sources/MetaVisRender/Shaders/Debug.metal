#include <metal_stdlib>
#include "Core/ACES.metal"

using namespace metal;

// Simple compute kernel to verify ACES compilation and linking
kernel void debug_verify_aces(
    device float4* input [[buffer(0)]],
    device float4* output [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    float3 color = input[id].rgb;
    
    // Exercise the ACES path
    float3 sdr = Core::ACES::ACEScg_to_Rec709_SDR(color);
    
    output[id] = float4(sdr, 1.0);
}
