#include <metal_stdlib>
using namespace metal;

// INLINED FROM Procedural.metal to fix include issues
struct GradientStop {
    float3 color; // ACEScg
    float position;
};

// OPTIMIZED: Branchless binary search gradient lookup
// Eliminates divergent branching for full-screen compute shaders
// For complex gradients (8+ stops), this is significantly faster than linear search
float3 mapToGradient(float t, constant GradientStop* colors, int count, bool loop) {
    if (count == 0) return float3(0.0);
    if (count == 1) return colors[0].color;
    
    t = loop ? fract(t) : saturate(t);
    
    // Branchless binary search to find segment
    // For typical 8-12 stop gradients, this is O(log n) vs O(n)
    int lo = 0;
    int hi = count - 1;
    
    // Unrolled binary search (max 4 iterations for up to 16 stops)
    #pragma unroll
    for (int iter = 0; iter < 4; ++iter) {
        int mid = (lo + hi) >> 1;
        // Branchless select: if t > colors[mid].position, lo = mid, else lo = lo
        lo = select(lo, mid, t > colors[mid].position && mid < count - 1);
        hi = select(hi, mid, t <= colors[mid].position && mid > 0);
        if (hi - lo <= 1) break;
    }
    
    // Ensure we have a valid segment
    int segmentIdx = min(lo, count - 2);
    
    // Interpolate within segment (branchless)
    float pos0 = colors[segmentIdx].position;
    float pos1 = colors[segmentIdx + 1].position;
    float range = pos1 - pos0;
    float localT = (t - pos0) / max(range, 0.0001);
    localT = saturate(localT);
    
    return mix(colors[segmentIdx].color, colors[segmentIdx + 1].color, localT);
}
// END INLINE

#ifndef PROCEDURAL_FRACTALS_METAL
#define PROCEDURAL_FRACTALS_METAL

// MARK: - Fractal Parameters

struct FractalParams {
    // Common parameters
    int maxIterations;
    float escapeRadius;
    int smoothColoring;    // Changed from bool to int
    
    // Julia/Mandelbrot-specific
    float2 c;              // Julia constant or Mandelbrot center
    float zoom;
    float2 center;
    
    // Color mapping
    int colorCount;        // Number of gradient colors (max 8)
    int loopGradient;      // Changed from bool to int
    
    // Animation
    float time;
    
    // Padding for alignment
    float padding;
};

// MARK: - Complex Number Utilities

inline float2 complex_mul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

inline float complex_length_squared(float2 z) {
    return z.x * z.x + z.y * z.y;
}

// MARK: - Kernels

// Julia Set
kernel void fx_fractal_julia(
    texture2d<float, access::write> output [[texture(0)]],
    constant FractalParams& params [[buffer(0)]],
    constant GradientStop* gradient [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float2 resolution = float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) - 0.5 * resolution) / resolution.y;
    
    // Apply camera transform
    float2 z = uv / params.zoom + params.center;
    
    // Animate C if needed (example: circular motion)
    float2 c = params.c;
    if (params.time > 0.0) {
        // Optional: animate c based on time if desired, or keep static
    }
    
    float iteration = 0.0;
    float2 z_curr = z;
    
    for (int i = 0; i < params.maxIterations; ++i) {
        if (complex_length_squared(z_curr) > params.escapeRadius * params.escapeRadius) {
            break;
        }
        z_curr = complex_mul(z_curr, z_curr) + c;
        iteration += 1.0;
    }
    
    // Smooth coloring
    float t = 0.0;
    if (iteration < float(params.maxIterations)) {
        if (params.smoothColoring != 0) {
            float log_zn = log(complex_length_squared(z_curr)) / 2.0;
            float nu = log(log_zn / log(2.0)) / log(2.0);
            iteration = iteration + 1.0 - nu;
        }
        
        // Map iteration to 0-1 range for gradient
        t = iteration * 0.05; // Scale factor for density
    } else {
        t = 0.0; // Interior color (usually black, handled by gradient at 0)
    }
    
    // Map to ACEScg gradient using Shared Core
    // float3 color = mapToGradient(t, gradient, params.colorCount, params.loopGradient != 0);
    
    // DEBUG: Hardcoded gradient to rule out buffer issues
    float3 color = float3(0.0);
    if (t < 0.5) {
        color = mix(float3(0.05, 0.0, 0.15), float3(1.2, 0.4, 0.0), t * 2.0);
    } else {
        color = mix(float3(1.2, 0.4, 0.0), float3(0.0, 0.9, 1.5), (t - 0.5) * 2.0);
    }
    
    // Interior check - force black if inside set and not looping
    if (iteration >= float(params.maxIterations) && params.loopGradient == 0) {
        color = float3(0.0);
    }
    
    output.write(float4(color, 1.0), gid);
}

// Mandelbrot Set
kernel void fx_fractal_mandelbrot(
    texture2d<float, access::write> output [[texture(0)]],
    constant FractalParams& params [[buffer(0)]],
    constant GradientStop* gradient [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float2 resolution = float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) - 0.5 * resolution) / resolution.y;
    
    // Apply camera transform
    float2 c = uv / params.zoom + params.center;
    float2 z = float2(0.0);
    
    float iteration = 0.0;
    
    for (int i = 0; i < params.maxIterations; ++i) {
        if (complex_length_squared(z) > params.escapeRadius * params.escapeRadius) {
            break;
        }
        z = complex_mul(z, z) + c;
        iteration += 1.0;
    }
    
    // Smooth coloring
    float t = 0.0;
    if (iteration < float(params.maxIterations)) {
        if (params.smoothColoring != 0) {
            float log_zn = log(complex_length_squared(z)) / 2.0;
            float nu = log(log_zn / log(2.0)) / log(2.0);
            iteration = iteration + 1.0 - nu;
        }
        t = iteration * 0.05;
    }
    
    float3 color = mapToGradient(t, gradient, params.colorCount, params.loopGradient != 0);
    
    if (iteration >= float(params.maxIterations) && params.loopGradient == 0) {
        color = float3(0.0);
    }
    
    output.write(float4(color, 1.0), gid);
}

// Burning Ship
kernel void fx_fractal_burning_ship(
    texture2d<float, access::write> output [[texture(0)]],
    constant FractalParams& params [[buffer(0)]],
    constant GradientStop* gradient [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float2 resolution = float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) - 0.5 * resolution) / resolution.y;
    
    float2 c = uv / params.zoom + params.center;
    // Flip Y for Burning Ship convention
    c.y = -c.y;
    
    float2 z = float2(0.0);
    float iteration = 0.0;
    
    for (int i = 0; i < params.maxIterations; ++i) {
        if (complex_length_squared(z) > params.escapeRadius * params.escapeRadius) {
            break;
        }
        
        // |Re(z)| + i|Im(z)|
        float2 z_abs = abs(z);
        z = complex_mul(z_abs, z_abs) + c;
        iteration += 1.0;
    }
    
    float t = 0.0;
    if (iteration < float(params.maxIterations)) {
        // Smooth coloring approximation for Burning Ship (less accurate due to abs)
        if (params.smoothColoring != 0) {
            float log_zn = log(complex_length_squared(z)) / 2.0;
            float nu = log(log_zn / log(2.0)) / log(2.0);
            iteration = iteration + 1.0 - nu;
        }
        t = iteration * 0.05;
    }
    
    float3 color = mapToGradient(t, gradient, params.colorCount, params.loopGradient != 0);
    
    if (iteration >= float(params.maxIterations) && params.loopGradient == 0) {
        color = float3(0.0);
    }
    
    output.write(float4(color, 1.0), gid);
}

#endif // PROCEDURAL_FRACTALS_METAL
