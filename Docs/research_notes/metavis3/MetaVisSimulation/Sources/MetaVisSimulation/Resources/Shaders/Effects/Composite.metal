#include <metal_stdlib>
using namespace metal;

// MARK: - Helper Functions

// Hash for Gradient Noise
float2 hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

// Gradient Noise (Smoother than Value Noise)
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // Quintic Interpolation (Smoother)
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    return mix(mix(dot(hash2(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
                   dot(hash2(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
               mix(dot(hash2(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
                   dot(hash2(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y) + 0.5; // Normalize to 0..1
}

// Rotated FBM (Fractal Brownian Motion)
// Reduces grid artifacts and creates more organic, high-quality fog
float fbm(float2 p) {
    float f = 0.0;
    float2x2 m = float2x2(0.80,  0.60, -0.60,  0.80);
    float amp = 0.5;
    for (int i = 0; i < 6; i++) {
        f += noise(p) * amp;
        p = m * p * 2.02; // Slightly off 2.0 to avoid resonance
        amp *= 0.5;
    }
    return f;
}

// Bicubic Sampling (Catmull-Rom)
// High-quality texture sampling to preserve detail at 4K
float4 sample_bicubic(texture2d<float, access::sample> tex, sampler s, float2 uv) {
    float2 texSize = float2(tex.get_width(), tex.get_height());
    float2 invTexSize = 1.0 / texSize;
    
    float2 pixel = uv * texSize - 0.5;
    float2 f = fract(pixel);
    float2 i = floor(pixel);
    
    // Catmull-Rom weights
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / w12;
    
    float2 texPos0 = (i - 1.0 + 0.5) * invTexSize;
    float2 texPos3 = (i + 2.0 + 0.5) * invTexSize;
    float2 texPos12 = (i + offset12 + 0.5) * invTexSize;
    
    float4 result = float4(0.0);
    
    result += tex.sample(s, float2(texPos12.x, texPos0.y)) * w12.x * w0.y;
    result += tex.sample(s, float2(texPos0.x, texPos12.y)) * w0.x * w12.y;
    result += tex.sample(s, float2(texPos12.x, texPos12.y)) * w12.x * w12.y;
    result += tex.sample(s, float2(texPos3.x, texPos12.y)) * w3.x * w12.y;
    result += tex.sample(s, float2(texPos12.x, texPos3.y)) * w12.x * w3.y;
    
    return result;
}

// ACES Tone Mapping (Cinematic Standard)
float3 ACESFilm(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

// Triangular Dithering
float3 dither(float2 uv) {
    float noiseVal = fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    return (float3(noiseVal) - 0.5) / 255.0;
}

// MARK: - Composite Kernels

// Additive Blend (Linear Light)
kernel void composite_add(
    texture2d<float, access::sample> inputA [[texture(0)]],
    texture2d<float, access::sample> inputB [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    
    float4 colorA = inputA.sample(s, uv);
    float4 colorB = inputB.sample(s, uv);
    
    float3 rgb = colorA.rgb + colorB.rgb;
    float alpha = max(colorA.a, colorB.a);
    
    output.write(float4(rgb, alpha), gid);
}

// Screen Blend
kernel void composite_screen(
    texture2d<float, access::sample> inputA [[texture(0)]],
    texture2d<float, access::sample> inputB [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    
    float4 colorA = inputA.sample(s, uv);
    float4 colorB = inputB.sample(s, uv);
    
    float3 rgb = 1.0 - (1.0 - colorA.rgb) * (1.0 - colorB.rgb);
    float alpha = max(colorA.a, colorB.a);
    
    output.write(float4(rgb, alpha), gid);
}

struct StarData {
    float u;
    float v;
    float mag;
    float r;
    float g;
    float b;
};

struct ConfigData {
    float exposure;
    float saturation;
    float contrast;
    float lift;
    float gamma;
    float gain;
};

float3 applyGrading(float3 color, constant ConfigData& config) {
    // Operate in display-referred space (post-tonemap) for predictable artist controls.
    color = (color + config.lift) * config.gain;

    // Contrast around mid-gray.
    color = (color - 0.5) * config.contrast + 0.5;

    // Saturation via luminance mix.
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(luma), color, config.saturation);

    return saturate(color);
}

// JWST Composite v4 (v46 Data-Driven Hybrid)
kernel void jwst_composite_v4(
    texture2d<float, access::sample> densityMap [[texture(0)]],
    texture2d<float, access::sample> colorMap [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant StarData* stars [[buffer(0)]],
    constant ConfigData& config [[buffer(1)]],
    constant float& time [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::mirrored_repeat, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    
    // Camera / Ray Setup
    float zoom = 1.25 + time * 0.05; // Aggressive initial zoom (1.25) to ensure edges are off-screen
    float2 p = (uv - 0.5) / zoom + 0.5;
    
    // Volumetric Raymarching
    float3 rayOrigin = float3(p, -1.0);
    float3 rayDir = normalize(float3(0.0, 0.0, 1.0)); // Orthographic-ish projection into volume
    
    float3 accumColor = float3(0.0);
    float accumDensity = 0.0;
    
    int steps = 64;
    float stepSize = 0.02;
    
    for (int i = 0; i < steps; i++) {
        float3 pos = rayOrigin + rayDir * float(i) * stepSize;
        
        // Parallax: Scale UVs based on depth (z)
        float depth = pos.z; 
        float parallaxScale = 1.0 + depth * 0.15; // Reduced parallax (0.2 -> 0.15) to minimize edge distortion
        float2 sampleUV = (pos.xy - 0.5) * parallaxScale + 0.5;
        
        // Removed manual bounds check to allow clamp_to_edge to work and prevent clipping artifacts
        // if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0) continue;
        
        float d = densityMap.sample(s, sampleUV).r;
        float3 c = colorMap.sample(s, sampleUV).rgb;
        
        // Noise for volumetric detail
        float noiseVal = fbm(sampleUV * 10.0 + float2(time * 0.01, 0.0));
        d *= (0.8 + 0.4 * noiseVal);
        
        float alpha = d * stepSize * 2.0; // Density factor
        
        accumColor += c * alpha * (1.0 - accumDensity);
        accumDensity += alpha;
        
        if (accumDensity >= 1.0) break;
    }
    
    // Stars (Hybrid: Enhance brightest stars)
    float3 starLayer = float3(0.0);
    float aspect = float(output.get_width()) / float(output.get_height());
    
    for (int i = 0; i < 64; i++) {
        StarData star = stars[i];
        if (star.mag <= 0.001) continue; 
        
        float2 starPos = float2(star.u, star.v);
        float2 pStar = (starPos - 0.5) / zoom + 0.5;
        
        float2 diff = (p - pStar);
        diff.x *= aspect;
        
        float dist = length(diff);
        
        if (dist < 0.05) { 
            // Diffraction Spikes
            float angle = atan2(diff.y, diff.x);
            float spikes = pow(abs(cos(angle * 3.0)), 10.0) * exp(-dist * 20.0);
            float core = exp(-dist * dist * 1000.0);
            
            starLayer += float3(star.r, star.g, star.b) * (core + spikes * 0.5) * star.mag;
        }
    }
    
    accumColor += starLayer;
    
    // Tone Mapping & Grading
    accumColor = ACESFilm(accumColor * config.exposure);
    accumColor = applyGrading(accumColor, config);
    accumColor = pow(accumColor, float3(1.0 / max(config.gamma, 1e-4))); // Gamma correction
    
    output.write(float4(accumColor, 1.0), gid);
}

struct SplitScreenParams {
    float splitPosition;
    float angle;
    float width;
    float _pad;
};

kernel void composite_split_screen(
    texture2d<float, access::sample> inputA [[texture(0)]],
    texture2d<float, access::sample> inputB [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant SplitScreenParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(output.get_width(), output.get_height());
    
    float4 colorA = inputA.sample(s, uv);
    float4 colorB = inputB.sample(s, uv);
    
    float4 finalColor;
    
    if (uv.x < params.splitPosition) {
        finalColor = colorA;
    } else {
        finalColor = colorB;
    }
    
    float lineWidth = params.width;
    if (abs(uv.x - params.splitPosition) < lineWidth) {
        finalColor = float4(1.0, 1.0, 1.0, 1.0);
    }
    
    output.write(finalColor, gid);
}
