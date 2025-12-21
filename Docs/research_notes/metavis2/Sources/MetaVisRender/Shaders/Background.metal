//
//  Background.metal
//  MetaVisRender
//
//  Background rendering shaders
//

#include <metal_stdlib>
#include "Core/ACES.metal"
using namespace metal;

// MARK: - Background Types

/// Solid color background parameters
struct SolidBackgroundParams {
    float3 color;  // ACEScg color
    float padding;
};

/// Gradient background parameters
struct GradientBackgroundParams {
    float3 color1;      // Start color (ACEScg)
    float angle;        // Gradient angle in radians
    float3 color2;      // End color (ACEScg)
    int colorCount;     // Number of color stops (2-16)
};

/// Starfield background parameters
struct StarfieldParams {
    float3 baseColor;   // Background color
    int seed;           // Random seed
    float3 starColor;   // Star tint color
    float density;      // Stars per screen (0-1)
    float brightness;   // Star brightness multiplier
    float twinkleSpeed; // Animation speed
    float time;         // Current time
    float padding;      // Alignment
};

// MARK: - Solid Background

kernel void fx_solid_background(
    constant SolidBackgroundParams& params [[buffer(0)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Output Linear ACEScg (Unified Pipeline)
    // Assumes params.color is scene-linear ACEScg
    output.write(float4(params.color, 1.0), gid);
}

// MARK: - Gradient Background

// Hash function for gradient stops
inline float hash_gradient(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

// Interpolate between gradient stops
inline float3 interpolate_gradient(
    float t,
    device float4* gradientStops,
    int stopCount
) {
    // Clamp t to [0, 1]
    t = clamp(t, 0.0f, 1.0f);
    
    // Binary search for the correct stop pair
    int left = 0;
    int right = stopCount - 1;
    
    while (right - left > 1) {
        int mid = (left + right) / 2;
        float midPos = gradientStops[mid].w;
        if (t < midPos) {
            right = mid;
        } else {
            left = mid;
        }
    }
    
    // Interpolate between stops
    float3 color1 = gradientStops[left].xyz;
    float pos1 = gradientStops[left].w;
    float3 color2 = gradientStops[right].xyz;
    float pos2 = gradientStops[right].w;
    
    float localT = (t - pos1) / (pos2 - pos1 + 1e-6);
    return mix(color1, color2, localT);
}

kernel void fx_gradient_background(
    constant GradientBackgroundParams& params [[buffer(0)]],
    device float4* gradientStops [[buffer(1)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Convert to normalized coordinates
    float2 uv = float2(gid) / float2(output.get_width(), output.get_height());
    
    // Apply rotation
    float cosAngle = cos(params.angle);
    float sinAngle = sin(params.angle);
    float2 dir = float2(cosAngle, sinAngle);
    
    // Calculate gradient position
    float t = dot(uv - 0.5, dir) + 0.5;
    
    // Sample gradient
    float3 color = interpolate_gradient(t, gradientStops, params.colorCount);
    
    // Output Linear ACEScg (Unified Pipeline)
    // Assumes gradient colors are scene-linear ACEScg
    output.write(float4(color, 1.0), gid);
}

// MARK: - Starfield Background

// Hash function for star positions
inline float2 hash2_star(uint2 p) {
    uint n = p.x * 374761393U + p.y * 668265263U;
    n = (n ^ (n >> 13U)) * 1274126177U;
    return float2(n & 0xffffffffU, (n >> 16U) & 0xffffffffU) / 4294967296.0;
}

// Hash for star brightness
inline float hash_star(uint2 p) {
    uint n = p.x * 374761393U + p.y * 668265263U;
    n = (n ^ (n >> 13U)) * 1274126177U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

kernel void fx_starfield_background(
    constant StarfieldParams& params [[buffer(0)]],
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Start with base color
    float3 color = params.baseColor;
    
    // Grid-based star placement
    uint2 cellSize = uint2(32, 32);  // 32x32 pixel cells
    uint2 cellCoord = gid / cellSize;
    uint2 cellLocal = gid % cellSize;
    
    // Seed for this cell
    uint2 cellSeed = cellCoord + uint2(params.seed);
    
    // Determine if this cell has a star
    float starChance = hash_star(cellSeed);
    if (starChance < params.density) {
        // Position of star within cell
        float2 starPos = hash2_star(cellSeed) * float2(cellSize);
        float2 toStar = float2(cellLocal) - starPos;
        float dist = length(toStar);
        
        // Star size (0.5 - 2.0 pixels)
        float starSize = 0.5 + 1.5 * hash_star(cellSeed + uint2(1, 0));
        
        // Star brightness (with twinkle)
        float baseBrightness = hash_star(cellSeed + uint2(0, 1));
        float twinkle = 0.5 + 0.5 * sin(params.time * params.twinkleSpeed + baseBrightness * 6.28318);
        float brightness = baseBrightness * twinkle * params.brightness;
        
        // Soft falloff
        if (dist < starSize * 2.0) {
            float falloff = 1.0 - smoothstep(0.0, starSize * 2.0, dist);
            color += params.starColor * brightness * falloff;
        }
    }
    
    // Output Linear ACEScg (Unified Pipeline)
    // Assumes colors are scene-linear ACEScg
    output.write(float4(color, 1.0), gid);
}

// MARK: - Procedural Background (from FieldKernels.metal)

// This kernel is defined in FieldKernels.metal
// Included here for reference:
// kernel void fx_procedural_field(...)
