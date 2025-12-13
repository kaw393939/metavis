#include <metal_stdlib>
#include "Procedural.metal"
#include "Noise.metal"

using namespace metal;
using namespace Procedural;

// =============================================================================
// VOLUMETRIC NEBULA RAYMARCHER
// =============================================================================

// MARK: - Uniform Structures

struct VolumetricNebulaParams {
    // Camera (each float3 + padding = 16 bytes)
    float3 cameraPosition;
    float _pad0;
    float3 cameraForward;
    float _pad1;
    float3 cameraUp;
    float _pad2;
    float3 cameraRight;
    float _pad3;
    float fov;
    float aspectRatio;
    float _pad4[2]; // Align to 16 bytes
    
    // Volume Bounds (AABB)
    float3 volumeMin;
    float _pad5;
    float3 volumeMax;
    float _pad6;
    
    // Density Field
    float baseFrequency;
    int octaves;
    float lacunarity;
    float gain;
    float densityScale;
    float densityOffset;
    float _pad7[2]; // Align to 16 bytes
    
    // Animation
    float time;
    float _pad8[3]; // Align to 16 bytes
    float3 windVelocity;
    float _pad9;
    
    // Lighting
    float3 lightDirection;
    float _pad10;
    float3 lightColor;
    float ambientIntensity;
    
    // Scattering
    float scatteringCoeff;   // σ_s
    float absorptionCoeff;   // σ_a (extinction = σ_s + σ_a)
    float phaseG;            // Henyey-Greenstein asymmetry (-1 to 1)
    float _pad11;
    
    // Quality
    int maxSteps;
    int shadowSteps;
    float stepSize;
    float _pad12;
    
    // Color
    float3 emissionColorWarm;  // Hot regions (high density)
    float _pad13;
    float3 emissionColorCool;  // Cool regions (low density)
    float _pad14;
    float emissionIntensity;
    float hdrScale;
    float _pad15[2]; // Final alignment
};

struct GradientStop3D {
    float3 color;
    float position;
};

// MARK: - Ray-Box Intersection

// Returns (tNear, tFar) or (-1, -1) if no hit
float2 intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax) {
    float3 invDir = 1.0 / rayDir;
    float3 t0 = (boxMin - rayOrigin) * invDir;
    float3 t1 = (boxMax - rayOrigin) * invDir;
    
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    
    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);
    
    if (tNear > tFar || tFar < 0.0) {
        return float2(-1.0);
    }
    
    return float2(max(tNear, 0.0), tFar);
}

// MARK: - Density Field

// Helper: Smooth blob falloff
float blobDensity(float3 pos, float3 center, float radius) {
    float d = length(pos - center) / radius;
    if (d > 1.0) return 0.0;
    // Smooth falloff
    float t = 1.0 - d;
    return t * t * (3.0 - 2.0 * t); // smoothstep-like
}

// Sample the nebula density at a world-space position
float sampleDensity(float3 pos, constant VolumetricNebulaParams& params) {
    float3 volumeCenter = (params.volumeMin + params.volumeMax) * 0.5;
    float3 volumeSize = params.volumeMax - params.volumeMin;
    
    // Apply wind animation
    float3 animatedPos = pos + params.windVelocity * params.time;
    
    // === ASYMMETRIC MULTI-CLOUD NEBULA ===
    
    float totalDensity = 0.0;
    
    // Cloud 1: Upper-right, large
    {
        float3 center = volumeCenter + float3(3.5, 2.5, -2.0);
        float radius = 3.0;
        float d = blobDensity(animatedPos, center, radius);
        totalDensity += d * 1.0;
    }
    
    // Cloud 2: Lower-left, medium  
    {
        float3 center = volumeCenter + float3(-4.0, -3.0, 1.0);
        float radius = 2.5;
        float d = blobDensity(animatedPos, center, radius);
        totalDensity += d * 0.9;
    }
    
    // Cloud 3: Upper-left, small bright core
    {
        float3 center = volumeCenter + float3(-2.5, 3.5, -1.0);
        float radius = 1.8;
        float d = blobDensity(animatedPos, center, radius);
        totalDensity += d * 1.2; // Brighter
    }
    
    // Cloud 4: Center-right, wispy
    {
        float3 center = volumeCenter + float3(5.0, -0.5, 2.0);
        float radius = 2.2;
        float d = blobDensity(animatedPos, center, radius);
        totalDensity += d * 0.7;
    }
    
    // Cloud 5: Far bottom, faint large
    {
        float3 center = volumeCenter + float3(0.0, -5.5, -3.0);
        float radius = 3.5;
        float d = blobDensity(animatedPos, center, radius);
        totalDensity += d * 0.5;
    }
    
    // Add subtle noise detail only where there's already density
    if (totalDensity > 0.01) {
        float3 p = animatedPos * params.baseFrequency;
        float noise = perlin(p.xy + float2(p.z * 0.3, 0.0));
        totalDensity *= (0.8 + 0.4 * noise); // ±20% variation
    }
    
    return totalDensity * params.densityScale;
}

// MARK: - Phase Function

// Henyey-Greenstein phase function for anisotropic scattering
float phaseHG(float cosTheta, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * M_PI_F * pow(denom, 1.5));
}

// MARK: - Shadow Ray

// Compute transmittance along shadow ray to light
float shadowTransmittance(float3 pos, constant VolumetricNebulaParams& params) {
    float3 lightDir = normalize(-params.lightDirection);
    
    // March towards light
    float shadowOpticalDepth = 0.0;
    float shadowStep = params.stepSize * 2.0; // Coarser for performance
    
    for (int i = 0; i < params.shadowSteps; i++) {
        float3 shadowPos = pos + lightDir * shadowStep * float(i + 1);
        
        // Check bounds
        float3 uvw = (shadowPos - params.volumeMin) / (params.volumeMax - params.volumeMin);
        if (any(uvw < 0.0) || any(uvw > 1.0)) break;
        
        float density = sampleDensity(shadowPos, params);
        shadowOpticalDepth += density * (params.scatteringCoeff + params.absorptionCoeff) * shadowStep;
    }
    
    return exp(-shadowOpticalDepth);
}

// MARK: - Main Raymarching Kernel

kernel void fx_volumetric_nebula(
    texture2d<float, access::read> depthTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant VolumetricNebulaParams& params [[buffer(0)]],
    constant GradientStop3D* colorGradient [[buffer(1)]],
    constant int& gradientCount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(outputTexture.get_width(), outputTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / resolution;
    float2 ndc = uv * 2.0 - 1.0;
    
    // Generate camera ray
    float tanHalfFov = tan(params.fov * 0.5 * M_PI_F / 180.0);
    float3 rayDir = normalize(
        params.cameraForward +
        params.cameraRight * ndc.x * tanHalfFov * params.aspectRatio +
        params.cameraUp * ndc.y * tanHalfFov
    );
    
    // Read scene depth for early termination
    float sceneDepth = depthTexture.read(gid).r;
    float maxDist = sceneDepth < 1.0 ? sceneDepth * 100.0 : 1e10; // Convert to world units
    
    // Intersect volume AABB
    float2 tHit = intersectAABB(params.cameraPosition, rayDir, params.volumeMin, params.volumeMax);
    
    if (tHit.x < 0.0) {
        // No hit - output transparent
        outputTexture.write(float4(0.0), gid);
        return;
    }
    
    // Clamp to scene depth
    tHit.y = min(tHit.y, maxDist);
    
    // Jitter start position to reduce banding
    float jitter = Core::Noise::interleavedGradientNoise(float2(gid));
    float t = tHit.x + jitter * params.stepSize;
    
    // Accumulation
    float3 accumulatedColor = float3(0.0);
    float transmittance = 1.0;
    
    float3 lightDir = normalize(-params.lightDirection);
    
    // Raymarch through volume
    for (int step = 0; step < params.maxSteps && t < tHit.y && transmittance > 0.01; step++) {
        float3 pos = params.cameraPosition + rayDir * t;
        
        float density = sampleDensity(pos, params);
        
        if (density > 0.001) {
            // Extinction coefficient
            float extinction = (params.scatteringCoeff + params.absorptionCoeff) * density;
            
            // Compute in-scattering
            float shadowT = shadowTransmittance(pos, params);
            
            // Phase function
            float cosTheta = dot(rayDir, lightDir);
            float phase = phaseHG(cosTheta, params.phaseG);
            
            // In-scattered light
            float3 inScatter = params.lightColor * shadowT * phase * params.scatteringCoeff * density;
            
            // Emission (self-illumination for nebula gas)
            float emissionT = saturate(density / params.densityScale);
            float3 emissionColor = mix(params.emissionColorCool, params.emissionColorWarm, emissionT);
            float3 emission = emissionColor * params.emissionIntensity * density;
            
            // Ambient contribution
            float3 ambient = params.lightColor * params.ambientIntensity * density;
            
            // Integrate
            float stepTransmittance = exp(-extinction * params.stepSize);
            float3 luminance = (inScatter + emission + ambient);
            
            // Energy-conserving integration
            float3 integScatter = luminance * (1.0 - stepTransmittance) * params.hdrScale;
            accumulatedColor += transmittance * integScatter;
            
            transmittance *= stepTransmittance;
        }
        
        t += params.stepSize;
    }
    
    // Output with alpha = 1 - transmittance
    float alpha = 1.0 - transmittance;
    
    outputTexture.write(float4(accumulatedColor, alpha), gid);
}

// MARK: - Composite Kernel

// Composite volumetric result over scene
kernel void fx_volumetric_composite(
    texture2d<float, access::read> sceneTexture [[texture(0)]],
    texture2d<float, access::read> volumetricTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 scene = sceneTexture.read(gid);
    float4 volumetric = volumetricTexture.read(gid);
    
    // Pre-multiplied alpha compositing
    // C_out = C_vol + C_scene * (1 - α_vol)
    float3 composited = volumetric.rgb + scene.rgb * (1.0 - volumetric.a);
    
    outputTexture.write(float4(composited, 1.0), gid);
}
