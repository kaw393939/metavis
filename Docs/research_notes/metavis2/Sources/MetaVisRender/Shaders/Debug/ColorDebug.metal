#include <metal_stdlib>
using namespace metal;

/// Debug shader: write known RGB values to test channel ordering
kernel void debug_write_rgb(
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Write pure colors to first row
    if (gid.y == 0) {
        if (gid.x == 0) {
            // Pure red
            output.write(float4(1.0, 0.0, 0.0, 1.0), gid);
        } else if (gid.x == 1) {
            // Pure green
            output.write(float4(0.0, 1.0, 0.0, 1.0), gid);
        } else if (gid.x == 2) {
            // Pure blue
            output.write(float4(0.0, 0.0, 1.0, 1.0), gid);
        } else if (gid.x == 3) {
            // White
            output.write(float4(1.0, 1.0, 1.0, 1.0), gid);
        }
    }
}
