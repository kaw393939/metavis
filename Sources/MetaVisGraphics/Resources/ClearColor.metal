#include <metal_stdlib>
using namespace metal;

// Simple solid fill used for empty timelines or missing sources.
kernel void clear_color(
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    output.write(float4(0.0, 0.0, 0.0, 1.0), gid);
}
