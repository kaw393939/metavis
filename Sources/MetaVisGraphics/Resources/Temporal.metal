#include <metal_stdlib>
using namespace metal;

// MARK: - Temporal Accumulation

// 1. Accumulate
kernel void fx_accumulate(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::read_write> accumTexture [[texture(1)]],
    constant float &weight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= accumTexture.get_width() || gid.y >= accumTexture.get_height()) {
        return;
    }
    
    float4 source = sourceTexture.read(gid); 
    float4 accum = accumTexture.read(gid);
    
    // Simple exponential moving average
    float4 result = mix(accum, source, weight);
    
    accumTexture.write(result, gid);
}

// 2. Resolve
kernel void fx_resolve(
    texture2d<float, access::read> accumTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    destTexture.write(accumTexture.read(gid), gid);
}
