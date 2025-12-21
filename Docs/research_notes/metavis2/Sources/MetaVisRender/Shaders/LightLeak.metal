// LightLeak.metal
// MetaVisRender
//
// Sprint 19: Color Management
// Organic light leak and color spill effects
// Operates in Linear ACEScg color space

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// MARK: - Light Leak Parameters
// =============================================================================

/// Light leak settings
struct LightLeakParams {
    float intensity;        // Overall effect strength (0-1)
    float3 tint;            // Color tint in ACEScg (e.g., warm pink/orange)
    float2 position;        // Leak source position (normalized 0-1)
    float size;             // Size/spread of the leak (0-1)
    float softness;         // Edge softness (0-1)
    float angle;            // Rotation angle in radians
    float animation;        // Animation phase (0-1) for subtle movement
    uint mode;              // 0 = additive, 1 = screen, 2 = overlay
};

/// Multi-leak configuration (up to 4 simultaneous leaks)
struct MultiLightLeakParams {
    float globalIntensity;  // Master intensity
    uint numLeaks;          // Number of active leaks (1-4)
    LightLeakParams leaks[4];
};


// =============================================================================
// MARK: - Blend Modes
// =============================================================================

inline float3 blendAdditive(float3 base, float3 leak, float opacity) {
    return base + leak * opacity;
}

inline float3 blendScreen(float3 base, float3 leak, float opacity) {
    float3 result = 1.0 - (1.0 - base) * (1.0 - leak);
    return mix(base, result, opacity);
}

inline float3 blendOverlay(float3 base, float3 leak, float opacity) {
    float3 result;
    result.r = base.r < 0.5 ? 2.0 * base.r * leak.r : 1.0 - 2.0 * (1.0 - base.r) * (1.0 - leak.r);
    result.g = base.g < 0.5 ? 2.0 * base.g * leak.g : 1.0 - 2.0 * (1.0 - base.g) * (1.0 - leak.g);
    result.b = base.b < 0.5 ? 2.0 * base.b * leak.b : 1.0 - 2.0 * (1.0 - base.b) * (1.0 - leak.b);
    return mix(base, result, opacity);
}

inline float3 blendSoftLight(float3 base, float3 leak, float opacity) {
    float3 result;
    result = (1.0 - 2.0 * leak) * base * base + 2.0 * leak * base;
    return mix(base, result, opacity);
}


// =============================================================================
// MARK: - Noise Functions
// =============================================================================

/// Simple hash for procedural variation
inline float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

/// Smooth noise
inline float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);  // Smoothstep
    
    float a = hash(i);
    float b = hash(i + float2(1.0, 0.0));
    float c = hash(i + float2(0.0, 1.0));
    float d = hash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

/// Fractal brownian motion
inline float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}


// =============================================================================
// MARK: - Leak Shape Functions
// =============================================================================

/// Compute single leak contribution
inline float computeLeakShape(
    float2 uv,
    float2 position,
    float size,
    float softness,
    float angle,
    float animation
) {
    // Transform UV relative to leak position
    float2 delta = uv - position;
    
    // Apply rotation
    float c = cos(angle);
    float s = sin(angle);
    float2x2 rot = float2x2(c, -s, s, c);
    delta = rot * delta;
    
    // Add subtle animation wobble
    float wobble = sin(animation * 6.28318) * 0.1;
    delta.x += wobble * 0.05;
    
    // Elliptical falloff (wider horizontally for anamorphic feel)
    float2 scaledDelta = delta / float2(size * 1.5, size);
    float dist = length(scaledDelta);
    
    // Add organic variation with noise
    float noiseVal = fbm(delta * 3.0 + animation, 3) * 0.3;
    dist += noiseVal;
    
    // Soft falloff
    float leak = 1.0 - smoothstep(0.0, 1.0 + softness, dist);
    
    // Add some internal structure
    float structure = fbm(delta * 5.0 - animation * 0.5, 2);
    leak *= 0.7 + structure * 0.3;
    
    return leak;
}


// =============================================================================
// MARK: - Main Light Leak Kernel
// =============================================================================

kernel void cs_light_leak(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant LightLeakParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Early out if disabled
    if (params.intensity <= 0.0) {
        outTexture.write(inTexture.read(gid), gid);
        return;
    }
    
    float2 uv = float2(gid) / float2(width, height);
    float4 original = inTexture.read(gid);
    
    // Compute leak shape
    float leakAmount = computeLeakShape(
        uv,
        params.position,
        params.size,
        params.softness,
        params.angle,
        params.animation
    );
    
    // Apply tint in ACEScg
    float3 leakColor = params.tint * leakAmount * params.intensity;
    
    // Apply blend mode
    float3 result;
    switch (params.mode) {
        case 0:  // Additive
            result = blendAdditive(original.rgb, leakColor, 1.0);
            break;
        case 1:  // Screen
            result = blendScreen(original.rgb, leakColor, 1.0);
            break;
        case 2:  // Overlay
            result = blendOverlay(original.rgb, leakColor, 1.0);
            break;
        default:
            result = blendAdditive(original.rgb, leakColor, 1.0);
    }
    
    outTexture.write(float4(result, original.a), gid);
}


// =============================================================================
// MARK: - Multi-Leak Kernel
// =============================================================================

kernel void cs_multi_light_leak(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant MultiLightLeakParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    if (params.globalIntensity <= 0.0 || params.numLeaks == 0) {
        outTexture.write(inTexture.read(gid), gid);
        return;
    }
    
    float2 uv = float2(gid) / float2(width, height);
    float4 original = inTexture.read(gid);
    float3 result = original.rgb;
    
    // Accumulate all leaks
    for (uint i = 0; i < min(params.numLeaks, 4u); i++) {
        LightLeakParams leak = params.leaks[i];
        
        if (leak.intensity <= 0.0) continue;
        
        float leakAmount = computeLeakShape(
            uv,
            leak.position,
            leak.size,
            leak.softness,
            leak.angle,
            leak.animation
        );
        
        float3 leakColor = leak.tint * leakAmount * leak.intensity * params.globalIntensity;
        
        // Apply blend mode
        switch (leak.mode) {
            case 0:
                result = blendAdditive(result, leakColor, 1.0);
                break;
            case 1:
                result = blendScreen(result, leakColor, 1.0);
                break;
            case 2:
                result = blendOverlay(result, leakColor, 1.0);
                break;
            default:
                result = blendAdditive(result, leakColor, 1.0);
        }
    }
    
    outTexture.write(float4(result, original.a), gid);
}


// =============================================================================
// MARK: - Preset Light Leaks
// =============================================================================

/// Film gate light leak (classic warm leak from edge)
kernel void cs_film_gate_leak(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float& intensity [[buffer(0)]],
    constant float& time [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    float2 uv = float2(gid) / float2(width, height);
    float4 original = inTexture.read(gid);
    
    // Create multiple organic leaks from edges
    float leak1 = computeLeakShape(uv, float2(-0.1, 0.3), 0.4, 0.5, 0.2, time);
    float leak2 = computeLeakShape(uv, float2(1.1, 0.7), 0.3, 0.6, -0.3, time * 0.8);
    float leak3 = computeLeakShape(uv, float2(0.5, -0.1), 0.5, 0.4, 1.57, time * 1.2);
    
    // Warm film-like colors in ACEScg
    float3 warmOrange = float3(1.2, 0.4, 0.1);   // Warm orange
    float3 hotPink = float3(1.0, 0.3, 0.5);      // Hot pink
    float3 goldenYellow = float3(1.1, 0.8, 0.2); // Golden yellow
    
    float3 leakColor = leak1 * warmOrange + leak2 * hotPink + leak3 * goldenYellow;
    leakColor *= intensity;
    
    float3 result = blendScreen(original.rgb, leakColor, 1.0);
    
    outTexture.write(float4(result, original.a), gid);
}
