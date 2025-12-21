#include <metal_stdlib>
using namespace metal;

// Passthrough for mask sources (e.g. r8Unorm segmentation masks).
// Writes into the engine's standard float destination texture.
kernel void source_person_mask(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    dest.write(source.read(gid), gid);
}
