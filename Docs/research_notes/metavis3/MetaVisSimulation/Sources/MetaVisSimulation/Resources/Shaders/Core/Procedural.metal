//
//  Procedural.metal
//  MetaVisRender
//
//  Core procedural noise library for infinite generative content
//  All functions output in ranges suitable for ACES color space
//

#ifndef PROCEDURAL_METAL
#define PROCEDURAL_METAL

#include <metal_stdlib>
using namespace metal;

// MARK: - Hash Functions

/// 2D hash function for noise generation
inline float hash(float2 p) {
    p = fract(p * float2(443.8975, 397.2973));
    p += dot(p.yx, p.xy + 19.19);
    return fract(p.x * p.y);
}

/// 2D hash returning float2
inline float2 hash2(float2 p) {
    p = float2(
        dot(p, float2(127.1, 311.7)),
        dot(p, float2(269.5, 183.3))
    );
    return fract(sin(p) * 43758.5453123);
}

// MARK: - Perlin Noise

/// Perlin gradient noise
/// Domain: R² → Codomain: [-1, 1]
/// Smooth, organic noise with good frequency characteristics
inline float perlin(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // Smoothstep interpolation
    float2 u = f * f * (3.0 - 2.0 * f);
    
    // Four corners of the grid cell
    float2 ga = hash2(i + float2(0.0, 0.0)) * 2.0 - 1.0;
    float2 gb = hash2(i + float2(1.0, 0.0)) * 2.0 - 1.0;
    float2 gc = hash2(i + float2(0.0, 1.0)) * 2.0 - 1.0;
    float2 gd = hash2(i + float2(1.0, 1.0)) * 2.0 - 1.0;
    
    // Gradients
    float va = dot(ga, f - float2(0.0, 0.0));
    float vb = dot(gb, f - float2(1.0, 0.0));
    float vc = dot(gc, f - float2(0.0, 1.0));
    float vd = dot(gd, f - float2(1.0, 1.0));
    
    // Bilinear interpolation
    return mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y);
}

// MARK: - Simplex Noise

/// 2D Simplex noise
/// Domain: R² → Codomain: [-1, 1]
/// Faster than Perlin with fewer directional artifacts
inline float simplex(float2 p) {
    const float4 C = float4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                            0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                            -0.577350269189626, // -1.0 + 2.0 * C.x
                            0.024390243902439); // 1.0 / 41.0
    
    // First corner
    float2 i  = floor(p + dot(p, C.yy));
    float2 x0 = p - i + dot(i, C.xx);
    
    // Other corners
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    
    // Permutations
    i = fmod(i, 289.0);
    float3 p_hash = hash2(i + float2(0.0, i1.y)).xyx;
    float3 p_hash2 = hash2(i + float2(i1.x, 1.0)).xyx;
    
    // Gradients: 41 points uniformly over a unit circle
    float3 m = max(0.5 - float3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m;
    m = m*m;
    
    // Gradients from 7x7 points over a square, mapped onto a circle
    float3 x = 2.0 * fract(p_hash * C.xxx) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    
    // Normalize gradients
    m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);
    
    // Compute final noise value at P
    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;
    return 130.0 * dot(m, g);
}

// MARK: - Worley Noise (Cellular)

/// Worley/Voronoi cellular noise
/// Domain: R² → Codomain: [0, 1]
/// Creates cell-like patterns, distance field
inline float worley(float2 p) {
    float2 i_st = floor(p);
    float2 f_st = fract(p);
    
    float minDist = 1.0;
    
    // Search 3x3 grid of neighboring cells
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 point = hash2(i_st + neighbor);
            
            float2 diff = neighbor + point - f_st;
            float dist = length(diff);
            minDist = min(minDist, dist);
        }
    }
    
    return minDist;
}

// MARK: - Fractal Brownian Motion (FBM)

/// Multi-octave fractal noise
/// Combines multiple octaves of noise for complex detail
/// Domain: R² → Codomain: approximately [-1, 1]
inline float fbm(float2 p, int octaves, float lacunarity, float gain) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float maxValue = 0.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * perlin(p * frequency);
        maxValue += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    
    return value / maxValue;
}

/// FBM with Simplex noise (faster alternative)
inline float fbmSimplex(float2 p, int octaves, float lacunarity, float gain) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    float maxValue = 0.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * simplex(p * frequency);
        maxValue += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    
    return value / maxValue;
}

// MARK: - Domain Operators

/// Rotate coordinate space
inline float2 domainRotate(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(
        c * p.x - s * p.y,
        s * p.x + c * p.y
    );
}

/// Scale coordinate space
inline float2 domainScale(float2 p, float2 scale) {
    return p * scale;
}

/// Domain warp - distort space with another noise field
/// This creates flowing, organic distortions
inline float2 domainWarp(float2 p, float strength, float2 warpField) {
    return p + warpField * strength;
}

// MARK: - Utility Functions

/// Remap value from one range to another
inline float remap(float value, float fromMin, float fromMax, float toMin, float toMax) {
    float t = (value - fromMin) / (fromMax - fromMin);
    return mix(toMin, toMax, clamp(t, 0.0, 1.0));
}

/// Smoothstep function for smooth transitions
inline float smoothstep(float edge0, float edge1, float x) {
    float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

/// Cheap contrast adjustment
inline float contrast(float value, float amount) {
    return clamp((value - 0.5) * amount + 0.5, 0.0, 1.0);
}

// MARK: - Gradient Mapping

/// Gradient stop for color mapping
struct GradientStop {
    float3 color;      // ACEScg color
    float position;    // [0, 1]
};

/// Map scalar field to gradient color
/// Uses binary search for efficient lookup without branch divergence
inline float3 mapToGradient(float value, constant GradientStop* gradient, int count, bool loop) {
    // Wrap value if looping
    if (loop) {
        value = fract(value);
    } else {
        value = clamp(value, 0.0, 1.0);
    }
    
    // Handle edge cases
    if (count == 0) return float3(0.0);
    if (count == 1) return gradient[0].color;
    if (value <= gradient[0].position) return gradient[0].color;
    if (value >= gradient[count-1].position) return gradient[count-1].color;
    
    // Binary search for the segment
    int lo = 0;
    int hi = count - 1;
    
    // Unrolled binary search (max 4 iterations for up to 16 stops)
    for (int iter = 0; iter < 4; ++iter) {
        if (hi - lo <= 1) break;
        
        int mid = (lo + hi) >> 1;
        bool goUp = value > gradient[mid].position && mid < count - 1;
        lo = select(lo, mid, goUp);
        hi = select(hi, mid, !goUp && mid > 0);
    }
    
    // Linear interpolation between stops
    float t = (value - gradient[lo].position) / (gradient[hi].position - gradient[lo].position);
    t = clamp(t, 0.0, 1.0);
    
    return mix(gradient[lo].color, gradient[hi].color, t);
}

#endif // PROCEDURAL_METAL
