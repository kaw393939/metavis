#include <metal_stdlib>
using namespace metal;

struct QCFingerprintAccum {
    atomic_uint count;
    atomic_uint sumR;
    atomic_uint sumG;
    atomic_uint sumB;
    atomic_ulong sumR2;
    atomic_ulong sumG2;
    atomic_ulong sumB2;
};

// Packed 16-byte result: 6x uint16 (mean/std RGB in [0,1] scaled to 0..65535) + 2x padding.
struct QCFingerprintOut16 {
    ushort meanR;
    ushort meanG;
    ushort meanB;
    ushort stdR;
    ushort stdG;
    ushort stdB;
    ushort _pad0;
    ushort _pad1;
};

struct QCColorStatsAccum {
    atomic_uint count;
    atomic_uint sumR;
    atomic_uint sumG;
    atomic_uint sumB;
};

kernel void qc_fingerprint_accumulate_bgra8(
    texture2d<half, access::sample> src [[texture(0)]],
    device QCFingerprintAccum* out [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    constexpr uint outW = 64;
    constexpr uint outH = 36;

    if (gid.x >= outW || gid.y >= outH) {
        return;
    }

    // Sample the source at output pixel centers, using bilinear filtering.
    // This approximates the CPU CGContext downsample used previously.
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = float2((float(gid.x) + 0.5f) / float(outW), (float(gid.y) + 0.5f) / float(outH));
    half4 c = src.sample(s, uv);

    // Source is typically BGRA; treat channels as (b,g,r,a).
    float r = clamp(float(c.z), 0.0f, 1.0f);
    float g = clamp(float(c.y), 0.0f, 1.0f);
    float b = clamp(float(c.x), 0.0f, 1.0f);

    uint ri = uint(r * 255.0f + 0.5f);
    uint gi = uint(g * 255.0f + 0.5f);
    uint bi = uint(b * 255.0f + 0.5f);

    atomic_fetch_add_explicit(&out->count, 1u, memory_order_relaxed);

    atomic_fetch_add_explicit(&out->sumR, ri, memory_order_relaxed);
    atomic_fetch_add_explicit(&out->sumG, gi, memory_order_relaxed);
    atomic_fetch_add_explicit(&out->sumB, bi, memory_order_relaxed);

    atomic_fetch_add_explicit(&out->sumR2, (ulong(ri) * ulong(ri)), memory_order_relaxed);
    atomic_fetch_add_explicit(&out->sumG2, (ulong(gi) * ulong(gi)), memory_order_relaxed);
    atomic_fetch_add_explicit(&out->sumB2, (ulong(bi) * ulong(bi)), memory_order_relaxed);
}

kernel void qc_fingerprint_finalize_16(
    device QCFingerprintAccum* accum [[buffer(0)]],
    device QCFingerprintOut16* out [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid != 0) return;

    uint count = atomic_load_explicit(&accum->count, memory_order_relaxed);
    float n = float(max(1u, count));

    float sumR = float(atomic_load_explicit(&accum->sumR, memory_order_relaxed));
    float sumG = float(atomic_load_explicit(&accum->sumG, memory_order_relaxed));
    float sumB = float(atomic_load_explicit(&accum->sumB, memory_order_relaxed));

    float sumR2 = float(atomic_load_explicit(&accum->sumR2, memory_order_relaxed));
    float sumG2 = float(atomic_load_explicit(&accum->sumG2, memory_order_relaxed));
    float sumB2 = float(atomic_load_explicit(&accum->sumB2, memory_order_relaxed));

    const float inv255 = 1.0f / 255.0f;
    float meanR = (sumR / n) * inv255;
    float meanG = (sumG / n) * inv255;
    float meanB = (sumB / n) * inv255;

    const float inv255sq = inv255 * inv255;
    float r2 = (sumR2 / n) * inv255sq;
    float g2 = (sumG2 / n) * inv255sq;
    float b2 = (sumB2 / n) * inv255sq;

    float varR = max(0.0f, r2 - (meanR * meanR));
    float varG = max(0.0f, g2 - (meanG * meanG));
    float varB = max(0.0f, b2 - (meanB * meanB));

    float stdR = sqrt(varR);
    float stdG = sqrt(varG);
    float stdB = sqrt(varB);

    auto pack01 = [](float x) -> ushort {
        float v = clamp(x, 0.0f, 1.0f);
        return ushort(v * 65535.0f + 0.5f);
    };

    out->meanR = pack01(meanR);
    out->meanG = pack01(meanG);
    out->meanB = pack01(meanB);
    out->stdR = pack01(stdR);
    out->stdG = pack01(stdG);
    out->stdB = pack01(stdB);
    out->_pad0 = 0;
    out->_pad1 = 0;
}

kernel void qc_colorstats_accumulate_bgra8(
    texture2d<half, access::sample> src [[texture(0)]],
    device QCColorStatsAccum* accum [[buffer(0)]],
    device atomic_uint* histogram [[buffer(1)]],
    constant uint& targetW [[buffer(2)]],
    constant uint& targetH [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= targetW || gid.y >= targetH) {
        return;
    }

    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = float2((float(gid.x) + 0.5f) / float(targetW), (float(gid.y) + 0.5f) / float(targetH));
    half4 c = src.sample(s, uv);

    float r = clamp(float(c.z), 0.0f, 1.0f);
    float g = clamp(float(c.y), 0.0f, 1.0f);
    float b = clamp(float(c.x), 0.0f, 1.0f);

    // Match the CPU path: normalize 0..255 with .toNearestOrAwayFromZero (positive => +0.5 then floor).
    uint ri = uint(r * 255.0f + 0.5f);
    uint gi = uint(g * 255.0f + 0.5f);
    uint bi = uint(b * 255.0f + 0.5f);

    // Rec.709 luma on gamma-coded RGB (matches VideoAnalyzer).
    float y = 0.2126f * r + 0.7152f * g + 0.0722f * b;
    uint yBin = uint(clamp(y, 0.0f, 1.0f) * 255.0f + 0.5f);

    atomic_fetch_add_explicit(&accum->count, 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&accum->sumR, ri, memory_order_relaxed);
    atomic_fetch_add_explicit(&accum->sumG, gi, memory_order_relaxed);
    atomic_fetch_add_explicit(&accum->sumB, bi, memory_order_relaxed);

    atomic_fetch_add_explicit(&histogram[yBin], 1u, memory_order_relaxed);
}
