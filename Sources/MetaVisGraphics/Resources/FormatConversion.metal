#include <metal_stdlib>
using namespace metal;

// Convert RGBA32Float -> BGRA8Unorm.
// Note: The destination texture format is BGRA, but Metal texture writes use logical RGBA
// channel semantics and the driver handles storage swizzling. Manually swapping here will
// invert red/blue.
kernel void rgba_to_bgra(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;
    
    float4 rgba = source.read(gid);
    dest.write(rgba, gid);
}
