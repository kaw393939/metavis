#include <metal_stdlib>
using namespace metal;

// Convert RGBA32Float -> BGRA8Unorm with proper channel swizzling
kernel void rgba_to_bgra(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;
    
    float4 rgba = source.read(gid);
    
    // Swizzle: RGBA -> BGRA
    float4 bgra = float4(rgba.b, rgba.g, rgba.r, rgba.a);
    
    dest.write(bgra, gid);
}
