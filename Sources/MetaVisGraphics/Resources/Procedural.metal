#include <metal_stdlib>
using namespace metal;

#ifndef CORE_PROCEDURAL_METAL
#define CORE_PROCEDURAL_METAL

// MARK: - Field Calculus Core
// Version: 2.0.0
// Philosophy: One Math, Infinite Worlds.

namespace Procedural {

    // MARK: - 1. Scalar Field Generators

    // Hash (White Noise)
    inline float hash12(float2 p) {
        float3 p3  = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    inline float2 hash22(float2 p) {
        float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.xx + p3.yz) * p3.zy);
    }

    // Perlin Noise (Gradient Noise)
    inline float2 perlin_gradient(float2 p) {
        float angle = hash12(p) * 2.0 * M_PI_F;
        return float2(cos(angle), sin(angle));
    }

    inline float perlin_fade(float t) {
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
    }

    float perlin(float2 p, float lod = 0.0) {
        float2 i = floor(p);
        float2 f = fract(p);
        
        float2 g00 = perlin_gradient(i + float2(0.0, 0.0));
        float2 g10 = perlin_gradient(i + float2(1.0, 0.0));
        float2 g01 = perlin_gradient(i + float2(0.0, 1.0));
        float2 g11 = perlin_gradient(i + float2(1.0, 1.0));
        
        float2 d00 = f - float2(0.0, 0.0);
        float2 d10 = f - float2(1.0, 0.0);
        float2 d01 = f - float2(0.0, 1.0);
        float2 d11 = f - float2(1.0, 1.0);
        
        float n00 = dot(g00, d00);
        float n10 = dot(g10, d10);
        float n01 = dot(g01, d01);
        float n11 = dot(g11, d11);
        
        float2 u = float2(perlin_fade(f.x), perlin_fade(f.y));
        
        float nx0 = mix(n00, n10, u.x);
        float nx1 = mix(n01, n11, u.x);
        float n = mix(nx0, nx1, u.y);
        
        return n; // Range [-1, 1]
    }

    // Simplex Noise
    float simplex(float2 p, float lod = 0.0) {
        const float F2 = 0.366025403;
        const float G2 = 0.211324865;
        
        float s = (p.x + p.y) * F2;
        float2 i = floor(p + s);
        float t = (i.x + i.y) * G2;
        float2 p0 = i - t;
        float2 x0 = p - p0;
        
        float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
        
        float2 x1 = x0 - i1 + G2;
        float2 x2 = x0 - 1.0 + 2.0 * G2;
        
        float n = 0.0;
        
        float t0 = 0.5 - dot(x0, x0);
        if (t0 > 0.0) {
            t0 *= t0;
            float2 g0 = hash22(i) * 2.0 - 1.0;
            n += t0 * t0 * dot(g0, x0);
        }
        
        float t1 = 0.5 - dot(x1, x1);
        if (t1 > 0.0) {
            t1 *= t1;
            float2 g1 = hash22(i + i1) * 2.0 - 1.0;
            n += t1 * t1 * dot(g1, x1);
        }
        
        float t2 = 0.5 - dot(x2, x2);
        if (t2 > 0.0) {
            t2 *= t2;
            float2 g2 = hash22(i + 1.0) * 2.0 - 1.0;
            n += t2 * t2 * dot(g2, x2);
        }
        
        return n * 70.0; // Range [-1, 1]
    }

    // Fractal Brownian Motion (FBM)
    float fbm(float2 p, int octaves, float lacunarity, float gain, float lod = 0.0) {
        float value = 0.0;
        float amplitude = 1.0;
        float frequency = 1.0;
        float maxValue = 0.0;
        
        for (int i = 0; i < octaves; i++) {
            value += simplex(p * frequency) * amplitude;
            maxValue += amplitude;
            frequency *= lacunarity;
            amplitude *= gain;
        }
        
        return value / maxValue;
    }

    // MARK: - 3. Field Operators

    struct GradientStop {
        float3 color; // ACEScg
        float position;
    };

    // OPTIMIZED: Branchless gradient lookup with binary search
    float3 mapToGradient(float t, constant GradientStop* colors, int count, bool loop) {
        if (count == 0) return float3(0.0);
        if (count == 1) return colors[0].color;
        
        t = loop ? fract(t) : saturate(t);
        
        // Branchless binary search for segment
        int lo = 0;
        int hi = count - 1;
        
        for (int iter = 0; iter < 4; ++iter) {
            int mid = (lo + hi) >> 1;
            lo = select(lo, mid, t > colors[mid].position && mid < count - 1);
            hi = select(hi, mid, t <= colors[mid].position && mid > 0);
            if (hi - lo <= 1) break;
        }
        
        int segmentIdx = min(lo, count - 2);
        
        // Branchless interpolation
        float pos0 = colors[segmentIdx].position;
        float pos1 = colors[segmentIdx + 1].position;
        float localT = saturate((t - pos0) / max(pos1 - pos0, 0.0001));
        
        return mix(colors[segmentIdx].color, colors[segmentIdx + 1].color, localT);
    }
}

#endif // CORE_PROCEDURAL_METAL
