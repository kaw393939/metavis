#include <metal_stdlib>
#include "../Core/Procedural.metal"
#include "../Core/ACES.metal"

using namespace metal;
using namespace Procedural;

// MARK: - PBR Material Definition
// Matches Swift PBRMaterialDefinition

struct PBRMaterialParams {
    float3 baseColor;
    float metallic;
    float roughness;
    float specular;
    float specularTint;
    float sheen;
    float sheenTint;
    float clearcoat;
    float clearcoatGloss;
    float ior;
    float transmission;
    
    // Emissive Parameters (V6.4)
    float3 emissiveColor;
    float emissiveIntensity;
    
    // Procedural Map Flags (0=None, 1=Perlin, 2=Worley, etc.)
    int roughnessMapType;
    int normalMapType;
    int metallicMapType;
    int hasBaseColorMap;
    
    // Procedural Map Parameters (Shared for simplicity in Phase 1)
    float mapFrequency;
    float mapStrength;
};

struct Light {
    float3 position;
    float3 color;
    float intensity;
};

// MARK: - Disney Principled BRDF Helper Functions
// Using half precision where visually sufficient for performance

float sqr(float x) { return x * x; }
half sqr_h(half x) { return x * x; }

// Half-precision Schlick Fresnel - sufficient for specular highlights
inline half SchlickFresnel_h(half u) {
    half m = clamp(1.0h - u, 0.0h, 1.0h);
    half m2 = m * m;
    return m2 * m2 * m; // m^5
}

float SchlickFresnel(float u) {
    float m = clamp(1.0 - u, 0.0, 1.0);
    float m2 = m * m;
    return m2 * m2 * m; // m^5
}

float GTR1(float NdotH, float a) {
    if (a >= 1.0) return 1.0 / M_PI_F;
    float a2 = a * a;
    float t = 1.0 + (a2 - 1.0) * NdotH * NdotH;
    return (a2 - 1.0) / (M_PI_F * log(a2) * t);
}

float GTR2(float NdotH, float a) {
    float a2 = a * a;
    float t = 1.0 + (a2 - 1.0) * NdotH * NdotH;
    return a2 / (M_PI_F * t * t);
}

float SmithG_GGX(float NdotV, float alphaG) {
    float a = alphaG * alphaG;
    float b = NdotV * NdotV;
    return 1.0 / (NdotV + sqrt(a + b - a * b));
}

// MARK: - Procedural Sampling

float sampleProceduralMap(int type, float2 uv, float freq) {
    float2 p = uv * freq;
    switch (type) {
        case 1: return perlin(p) * 0.5 + 0.5;
        case 2: return worley(p);
        case 3: return fbm(p, 4, 2.0, 0.5);
        default: return 0.0;
    }
}

// MARK: - PBR Fragment Shader

struct StandardVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float2 uv;
};

struct LightingUniforms {
    Light lights[4];
    int lightCount;
};

fragment float4 fragment_mesh_pbr(
    StandardVertexOut in [[stage_in]],
    constant PBRMaterialParams& mat [[buffer(0)]],
    constant LightingUniforms& lighting [[buffer(1)]],
    constant float3& cameraPos [[buffer(2)]],
    texture2d<float> baseColorMap [[texture(0)]],
    sampler sampler0 [[sampler(0)]]
) {
    float3 N = normalize(in.normal);
    float3 V = normalize(cameraPos - in.worldPos);
    float NdotV = abs(dot(N, V)) + 1e-5;
    
    // Surface Properties
    float3 baseColor = mat.baseColor;
    if (mat.hasBaseColorMap != 0) {
        constexpr sampler s(filter::linear, address::repeat);
        float4 texColor = baseColorMap.sample(s, in.uv);
        baseColor = texColor.rgb;
    }
    
    float roughness = mat.roughness;
    float metallic = mat.metallic;

    
    // Procedural Mapping (Simplified)
    if (mat.roughnessMapType > 0) {
        float noise = sampleProceduralMap(mat.roughnessMapType, in.uv, mat.mapFrequency);
        roughness = mix(roughness, noise, mat.mapStrength);
    }
    roughness = clamp(roughness, 0.001, 1.0);
    
    float3 Lo = float3(0.0);
    
    for (int i = 0; i < lighting.lightCount; ++i) {
        float3 L = normalize(lighting.lights[i].position - in.worldPos);
        float3 H = normalize(V + L);
        float dist = length(lighting.lights[i].position - in.worldPos);
        float atten = 1.0 / (1.0 + 0.1 * dist * dist);
        
        float NdotL = clamp(dot(N, L), 0.0, 1.0);
        float NdotH = clamp(dot(N, H), 0.0, 1.0);
        float LdotH = clamp(dot(L, H), 0.0, 1.0);
        
        if (NdotL > 0.0) {
            // Diffuse
            float Fd90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
            float lightScatter = (1.0 + (Fd90 - 1.0) * SchlickFresnel(NdotL));
            float viewScatter = (1.0 + (Fd90 - 1.0) * SchlickFresnel(NdotV));
            float3 diffuse = baseColor / M_PI_F * lightScatter * viewScatter * (1.0 - metallic);
            
            // Specular
            float alpha = sqr(roughness);
            float Ds = GTR2(NdotH, alpha);
            float FH = SchlickFresnel(LdotH);
            float3 Fs = mix(float3(0.04), baseColor, metallic); // F0
            float3 F = Fs + (1.0 - Fs) * FH;
            float Gs = SmithG_GGX(NdotV, alpha) * SmithG_GGX(NdotL, alpha);
            
            float3 specular = Gs * F * Ds;
            
            Lo += (diffuse + specular) * lighting.lights[i].color * lighting.lights[i].intensity * NdotL * atten;
        }
    }
    
    // Emissive
    float3 emission = mat.emissiveColor * mat.emissiveIntensity;
    // If using texture and high intensity, assume texture contributes to emission
    if (mat.hasBaseColorMap != 0 && mat.emissiveIntensity > 0.0) {
        emission += baseColor * mat.emissiveIntensity;
    }
    
    // Ambient
    float3 ambient = float3(0.03) * baseColor;
    
    return float4(Lo + ambient + emission, 1.0);
}

// MARK: - PBR Kernel

kernel void fx_pbr_material(
    texture2d<float, access::write> output [[texture(0)]],
    constant PBRMaterialParams& mat [[buffer(0)]],
    constant Light* lights [[buffer(1)]],
    constant int& lightCount [[buffer(2)]],
    constant float3& cameraPos [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float2 resolution = float2(output.get_width(), output.get_height());
    float2 uv = float2(gid) / resolution;
    
    // 1. Surface Properties (Procedural Modification)
    float roughness = mat.roughness;
    if (mat.roughnessMapType > 0) {
        float noise = sampleProceduralMap(mat.roughnessMapType, uv, mat.mapFrequency);
        roughness = mix(roughness, noise, mat.mapStrength);
    }
    roughness = clamp(roughness, 0.001, 1.0);
    
    float metallic = mat.metallic;
    if (mat.metallicMapType > 0) {
        float noise = sampleProceduralMap(mat.metallicMapType, uv, mat.mapFrequency);
        metallic = mix(metallic, step(0.5, noise), mat.mapStrength); // Metallic is usually binary
    }
    
    // Normal Perturbation (Bump Mapping)
    float3 N = float3(0.0, 0.0, 1.0); // Default normal (flat)
    // TODO: Implement proper normal mapping from noise derivatives
    
    // 2. Lighting Calculation (Simplified Disney)
    // Assume a sphere at center for visualization
    float2 p = (float2(gid) - 0.5 * resolution) / resolution.y;
    float r = length(p);
    if (r > 0.5) {
        output.write(float4(0.0, 0.0, 0.0, 0.0), gid); // Background
        return;
    }
    
    // Sphere Geometry
    float z = sqrt(0.25 - r * r);
    float3 pos = float3(p.x, p.y, z);
    N = normalize(pos); // Object space normal
    
    float3 V = normalize(cameraPos - pos);
    float NdotV = abs(dot(N, V)) + 1e-5;
    
    float3 Lo = float3(0.0);
    
    for (int i = 0; i < lightCount; ++i) {
        float3 L = normalize(lights[i].position - pos);
        float3 H = normalize(V + L);
        
        float NdotL = clamp(dot(N, L), 0.0, 1.0);
        float NdotH = clamp(dot(N, H), 0.0, 1.0);
        float LdotH = clamp(dot(L, H), 0.0, 1.0);
        
        if (NdotL > 0.0) {
            // Diffuse
            float Fd90 = 0.5 + 2.0 * roughness * LdotH * LdotH;
            float lightScatter = (1.0 + (Fd90 - 1.0) * SchlickFresnel(NdotL));
            float viewScatter = (1.0 + (Fd90 - 1.0) * SchlickFresnel(NdotV));
            float3 diffuse = mat.baseColor / M_PI_F * lightScatter * viewScatter * (1.0 - metallic);
            
            // Specular
            float alpha = sqr(roughness);
            float Ds = GTR2(NdotH, alpha);
            float FH = SchlickFresnel(LdotH);
            float3 Fs = mix(float3(0.04), mat.baseColor, metallic); // F0
            float3 F = Fs + (1.0 - Fs) * FH;
            float Gs = SmithG_GGX(NdotV, alpha) * SmithG_GGX(NdotL, alpha);
            
            float3 specular = Gs * F * Ds;
            
            Lo += (diffuse + specular) * lights[i].color * lights[i].intensity * NdotL;
        }
    }
    
    // Tone mapping is done in post, output linear ACEScg
    output.write(float4(Lo, 1.0), gid);
}
