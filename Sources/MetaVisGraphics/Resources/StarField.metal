#include <metal_stdlib>
using namespace metal;

static inline uint hash_u32(uint x) {
    x ^= x >> 17;
    x *= 0xed5ad4bbU;
    x ^= x >> 11;
    x *= 0xac4c1b51U;
    x ^= x >> 15;
    x *= 0x31848babU;
    x ^= x >> 14;
    return x;
}

static inline float hash01(uint x) {
    return (float)(hash_u32(x) & 0x00FFFFFFu) / (float)0x01000000u;
}

// Deterministic star field (debug/test pattern): sparse bright points + faint background.
kernel void fx_starfield(
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    uint w = (uint)output.get_width();
    uint h = (uint)output.get_height();

    uint idx = gid.y * w + gid.x;
    float2 uv = (float2(gid) + 0.5) / float2(w, h);

    // Faint background gradient (very subtle).
    float bg = 0.002 + 0.004 * (1.0 - uv.y);

    // Star probability varies slightly with position.
    float p = 0.00045 + 0.00030 * (0.5 + 0.5 * sin(uv.x * 17.0));

    float r0 = hash01(idx * 1664525u + 1013904223u);
    float r1 = hash01(idx * 22695477u + 1u);

    float star = 0.0;
    if (r0 < p) {
        // Brightness distribution: mostly dim, few bright.
        float b = pow(max(1e-6, 1.0 - r1), 6.0);
        star = 0.08 + 0.92 * b;
    }

    float v = bg + star;
    output.write(float4(v, v, v, 1.0), gid);
}
