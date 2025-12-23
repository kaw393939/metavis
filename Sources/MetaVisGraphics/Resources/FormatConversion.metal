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

// Bilinear resize for float textures.
// Convention: input at texture(0), output at texture(1).
kernel void resize_bilinear_rgba16f(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);

    float2 outSize = float2(dest.get_width(), dest.get_height());
    float2 uv = (float2(gid) + 0.5) / outSize;

    float4 c = source.sample(s, uv);
    dest.write(c, gid);
}

// Bicubic resize (Catmull-Rom) for float textures.
// Convention: input at texture(0), output at texture(1).
static inline float cubicCatmullRom(float x) {
    x = fabs(x);
    if (x < 1.0) {
        return 1.5 * x * x * x - 2.5 * x * x + 1.0;
    }
    if (x < 2.0) {
        return -0.5 * x * x * x + 2.5 * x * x - 4.0 * x + 2.0;
    }
    return 0.0;
}

kernel void resize_bicubic_rgba16f(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    constexpr sampler s(address::clamp_to_edge, filter::nearest, coord::pixel);

    float2 dstSize = float2(dest.get_width(), dest.get_height());
    float2 srcSize = float2(source.get_width(), source.get_height());

    // Map destination pixel center to source pixel space.
    float2 p = (float2(gid) + 0.5) * (srcSize / dstSize) - 0.5;
    float2 ip = floor(p);
    float2 f = p - ip;

    float4 accum = float4(0.0);
    float wsum = 0.0;

    // 4x4 taps.
    for (int j = -1; j <= 2; ++j) {
        float wy = cubicCatmullRom(float(j) - f.y);
        for (int i = -1; i <= 2; ++i) {
            float wx = cubicCatmullRom(float(i) - f.x);
            float w = wx * wy;
            float2 sp = ip + float2(float(i), float(j));
            float4 c = source.sample(s, sp);
            accum += c * w;
            wsum += w;
        }
    }

    if (wsum > 0.000001) {
        accum /= wsum;
    }

    dest.write(accum, gid);
}
