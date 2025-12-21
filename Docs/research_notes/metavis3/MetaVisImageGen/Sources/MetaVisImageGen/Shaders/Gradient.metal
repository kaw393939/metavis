#include <metal_stdlib>
using namespace metal;

kernel void gradient_generator(
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float width = float(output.get_width());
    float height = float(output.get_height());
    
    float u = float(gid.x) / width;
    float v = float(gid.y) / height;
    
    // Simple horizontal gradient (Red to Blue)
    float3 color = float3(u, 0.0, 1.0 - u);
    
    // Vertical gradient overlay (Green)
    color.g = v;
    
    output.write(float4(color, 1.0), gid);
}
