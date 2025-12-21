#include <metal_stdlib>
using namespace metal;

struct LogoVertexIn {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct LogoVertexOut {
    float4 position [[position]];
    float2 uv;
    float2 localPos;
};

struct LogoUniforms {
    float4x4 viewProjectionMatrix;
    float4 color; // ACEScg color
    float time;
    int flameMode; // 0: none, 1: torch, 2: pureFlame
    float curveStrength;
    float columnWidthRatio;
    float flameIntensity;
    float flameSharpness;
    int enableGlow;
    int enableHeatDistortion;
    int isFlame; // 0: Left, 1: Right, 2: Center
    int layoutMode; // 0: flameOnBlack, 1: flameOnCard
    float aspectRatio;
    int padding; // Pad to 128 bytes
};

vertex LogoVertexOut metavis_logo_vertex(
    LogoVertexIn in [[stage_in]],
    constant LogoUniforms &uniforms [[buffer(1)]]
) {
    LogoVertexOut out;
    
    // Position is already in local space, just apply MVP
    out.position = uniforms.viewProjectionMatrix * float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    out.localPos = in.position;
    
    return out;
}

// Simple Hash
float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Simple Noise
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float res = mix(mix(hash(i + float2(0, 0)), hash(i + float2(1, 0)), f.x),
                    mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
    return res;
}

// FBM
float fbm(float2 p) {
    float f = 0.0;
    f += 0.5000 * noise(p); p = p * 2.02;
    f += 0.2500 * noise(p); p = p * 2.03;
    f += 0.1250 * noise(p);
    return f;
}

// Cubic Bezier Function
float2 bezier(float t, float2 p0, float2 p1, float2 p2, float2 p3) {
    float omt = 1.0 - t;
    float omt2 = omt * omt;
    float omt3 = omt2 * omt;
    float t2 = t * t;
    float t3 = t2 * t;
    return p0 * omt3 + p1 * (3.0 * omt2 * t) + p2 * (3.0 * omt * t2) + p3 * t3;
}

// Derivative of Cubic Bezier
float2 bezierDerivative(float t, float2 p0, float2 p1, float2 p2, float2 p3) {
    float omt = 1.0 - t;
    float omt2 = omt * omt;
    float t2 = t * t;
    return (p1 - p0) * (3.0 * omt2) + (p2 - p1) * (6.0 * omt * t) + (p3 - p2) * (3.0 * t2);
}

// Planck's Law Blackbody Radiation (Approximation)
// Input: Temperature in Kelvin (1000K - 12000K)
// Output: Linear RGB Radiance
float3 blackbody(float temp) {
    // Planckian Locus approximation for Linear RGB
    float3 color = float3(1.0, 1.0, 1.0);
    
    // Red
    if (temp < 6600.0) {
        color.r = 1.0;
    } else {
        color.r = pow(temp / 6600.0, -0.5); // Falloff
    }
    
    // Green
    if (temp < 1000.0) {
        color.g = 0.0;
    } else if (temp < 6600.0) {
        color.g = 0.3 + 0.7 * log(temp/1000.0) / log(6.6); 
    } else {
        color.g = 1.0;
    }
    
    // Blue
    if (temp < 2000.0) {
        color.b = 0.0;
    } else {
        color.b = log(temp/2000.0) / log(6.0);
        if (color.b > 1.0) color.b = 1.0;
    }
    
    // Stefan-Boltzmann Law (Intensity ~ T^4)
    // We scale it down to be manageable for HDR rendering
    // T=1000 -> 0.01
    // T=4000 -> 1.0
    // T=8000 -> 16.0
    float intensity = pow(temp / 4000.0, 4.0); 
    
    return color * intensity;
}

fragment float4 metavis_logo_fragment(
    LogoVertexOut in [[stage_in]],
    constant LogoUniforms &uniforms [[buffer(1)]]
) {
    float4 baseColor = uniforms.color;
    float alpha = 1.0;
    
    // Flame Engine v2.0 (S-Curve Corrected)
    if (uniforms.flameMode > 0) {
        float time = uniforms.time;
        
        if (uniforms.isFlame == 2) { // Center Flame
            // 1. S-Curve Math (Bézier)
            // Control Points (Normalized to 0-1 UV space)
            // P0 = (0.5, 1.0) (Top)
            // P1 = (0.35, 0.7)
            // P2 = (0.65, 0.3)
            // P3 = (0.5, 0.0) (Bottom)
            
            float2 p0 = float2(0.5, 1.0);
            float2 p1 = float2(0.35, 0.7);
            float2 p2 = float2(0.65, 0.3);
            float2 p3 = float2(0.5, 0.0);
            
            // Apply curve strength to control points
            float strength = uniforms.curveStrength;
            // Adjust x of p1 and p2 based on strength relative to 0.5
            // Default strength 1.0 matches the spec points
            // If strength is 0, it should be a straight line (x=0.5)
            p1.x = 0.5 + (p1.x - 0.5) * strength;
            p2.x = 0.5 + (p2.x - 0.5) * strength;

            // --- GEOMETRY UPGRADE: Aspect Ratio Correction ---
            // Transform to Screen Space for Isotropic Distance
            float aspect = uniforms.aspectRatio;
            if (aspect < 0.1) aspect = 1.77; // Safety fallback
            
            float2 p0_s = p0; p0_s.x *= aspect;
            float2 p1_s = p1; p1_s.x *= aspect;
            float2 p2_s = p2; p2_s.x *= aspect;
            float2 p3_s = p3; p3_s.x *= aspect;
            
            float2 uv_s = in.uv;
            uv_s.x *= aspect;

            // Newton's method to find closest t
            // Initial guess: 1.0 - uv.y (since P0 is at top, and we assume uv.y=1 is top)
            float t_curve = 1.0 - in.uv.y; 
            
            // Iterations
            for(int i=0; i<3; i++) {
                float2 pos = bezier(t_curve, p0_s, p1_s, p2_s, p3_s);
                float2 tan = bezierDerivative(t_curve, p0_s, p1_s, p2_s, p3_s);
                float2 diff = pos - uv_s;
                // Avoid division by zero
                float dotTan = dot(tan, tan);
                if (dotTan > 0.0001) {
                    float d = dot(diff, tan) / dotTan;
                    t_curve -= d;
                    t_curve = clamp(t_curve, 0.0, 1.0);
                }
            }
            
            float2 closestPoint = bezier(t_curve, p0_s, p1_s, p2_s, p3_s);
            float dist = distance(uv_s, closestPoint);
            
            // u_prime is t (longitudinal)
            float u_prime = t_curve;
            
            // v_prime is normalized distance (radial)
            // Curve thickness = 0.12
            float thickness = 0.12;
            float v_prime = dist / thickness;
            
            // 2. Domain Warp (Applied to Straightened UVs)
            // V2 Spec: Spline -> Warp -> Intensity
            // We warp the coordinate space used for the SDF lookup
            
            float2 warpUV = float2(u_prime, v_prime);
            
            // Time flows upwards
            float t = time;
            
            // Warp Noise (Low Frequency)
            float w1 = noise(warpUV * float2(3.0, 2.0) + float2(0, t * -1.0));
            float w2 = noise(warpUV * float2(6.0, 4.0) + float2(0, t * -2.0)) * 0.5;
            float warp = (w1 + w2) * 0.1; // Strength of warp
            
            // Apply warp to u_prime (horizontal displacement)
            float u_warped = u_prime + warp;
            
            // 3. Flame Intensity Field (Volumetric)
            // Spec: F(u, v) = H(u) * R(v)
            
            // Radial Profile: R(v) = exp(-k * v^2)
            // Use warped v for organic feel
            float v_warped = v_prime + warp * 0.5; 
            float k_r = 4.0;
            float radial = exp(-k_r * v_warped * v_warped);
            
            // Longitudinal Profile: H(u)
            // Candle profile: zero at very top/bottom, full in middle
            float longitudinal = smoothstep(0.0, 0.1, u_prime) * (1.0 - smoothstep(0.9, 1.0, u_prime));
            
            // Shaping: Wider at bottom, narrow at top (Visual tweak)
            float widthProfile = mix(0.2, 1.0, smoothstep(0.1, 0.9, u_prime));
            
            // Base Intensity
            float intensity = radial * longitudinal * widthProfile;
            
            // Detail Noise (High Frequency, added to intensity)
            float n1 = noise(warpUV * float2(10.0, 8.0) + float2(0, t * -3.0));
            float detail = n1 * 0.1;
            
            intensity += detail;
            
            // Sharpness
            float alphaMask = smoothstep(0.0, 0.1, intensity);
            
            // 4. Blackbody Radiation (PHYSICS UPGRADE)
            // Heat based on intensity
            float heat = smoothstep(0.0, 1.0, intensity * uniforms.flameIntensity);
            
            // Map Heat (0..1) to Temperature (1000K .. 8000K)
            // We use a non-linear mapping to get more detail in the "fire" range
            float temp = 1000.0 + pow(heat, 1.5) * 7000.0;
            
            // Get Radiance from Planck's Law
            float3 finalColor = blackbody(temp);
            
            // Apply Alpha
            alpha = alphaMask;
            
            // Premultiplied Alpha
            baseColor.rgb = finalColor * alpha;
            baseColor.a = alpha;
            
        } else {
            // Side Shapes (Left/Right)
            // For V2, we hide them to focus on the pure flame
            alpha = 0.0;
            baseColor = float4(0.0);
        }
    }
    
    return baseColor;
}
