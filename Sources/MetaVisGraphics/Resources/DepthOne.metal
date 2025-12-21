#include <metal_stdlib>
using namespace metal;

// Deterministic depth texture generator: writes 1.0 in RGB.
kernel void depth_one(
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    output.write(float4(1.0, 1.0, 1.0, 1.0), gid);
}
