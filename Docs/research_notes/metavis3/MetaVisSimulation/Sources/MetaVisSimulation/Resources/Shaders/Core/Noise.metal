#include <metal_stdlib>
using namespace metal;

#ifndef CORE_NOISE_METAL
#define CORE_NOISE_METAL

namespace Core {
namespace Noise {

    // Simple high-frequency noise generator
    inline float hash12(float2 p) {
        float3 p3  = fract(float3(p.xyx) * .1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    // Interleaved Gradient Noise
    inline float interleavedGradientNoise(float2 uv) {
        float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
        return fract(magic.z * fract(dot(uv, magic.xy)));
    }

    // Helper functions for Simplex Noise
    inline float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    inline float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
    inline float3 permute(float3 x) { return mod289(((x*34.0)+1.0)*x); }

    // Simplex Noise 2D
    inline float simplex(float2 v) {
        const float4 C = float4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                                0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                                -0.577350269189626, // -1.0 + 2.0 * C.x
                                0.024390243902439); // 1.0 / 41.0
        // First corner
        float2 i  = floor(v + dot(v, C.yy) );
        float2 x0 = v -   i + dot(i, C.xx);

        // Other corners
        float2 i1;
        i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
        float4 x12 = x0.xyxy + C.xxzz;
        x12.xy -= i1;

        // Permutations
        i = mod289(i); // Avoid truncation effects in permutation
        float3 p = permute( permute( i.y + float3(0.0, i1.y, 1.0 ))
            + i.x + float3(0.0, i1.x, 1.0 ));

        float3 m = max(0.5 - float3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
        m = m*m ;
        m = m*m ;

        // Gradients: 41 points uniformly over a line, mapped onto a diamond.
        // The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)

        float3 x = 2.0 * fract(p * C.www) - 1.0;
        float3 h = abs(x) - 0.5;
        float3 ox = floor(x + 0.5);
        float3 a0 = x - ox;

        // Normalise gradients implicitly by scaling m
        // Approximation of: m *= inversesqrt( a0*a0 + h*h );
        m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );

        // Compute final noise value at P
        float3 g;
        g.x  = a0.x  * x0.x  + h.x  * x0.y;
        g.yz = a0.yz * x12.xz + h.yz * x12.yw;
        return 130.0 * dot(m, g);
    }

} // namespace Noise
} // namespace Core

#endif // CORE_NOISE_METAL
