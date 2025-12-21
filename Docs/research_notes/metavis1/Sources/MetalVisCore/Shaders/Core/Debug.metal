#include <metal_stdlib>
using namespace metal;

// MARK: - Debug Utilities

kernel void fx_debug_blue(
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destTexture.get_width() || gid.y >= destTexture.get_height()) {
        return;
    }
    destTexture.write(float4(0.0, 0.0, 1.0, 1.0), gid);
}
