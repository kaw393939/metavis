#include <metal_stdlib>
using namespace metal;

#ifndef EFFECTS_TEMPORAL_METAL
#define EFFECTS_TEMPORAL_METAL

// MARK: - Temporal Accumulation

// 1. Accumulate (Add weighted current frame to accumulation buffer)
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
    
    accumTexture.write(accum + source * weight, gid);
}

// 2. Resolve (Divide by total weight and output)
kernel void fx_resolve(
    texture2d<float, access::read> accumTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant float &totalWeight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    
    float4 accum = accumTexture.read(gid);
    float4 average = accum / totalWeight;
    
    destTexture.write(average, gid);
}

#endif // EFFECTS_TEMPORAL_METAL
