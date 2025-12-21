#include <metal_stdlib>
using namespace metal;

struct StandardVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
};

struct StandardVertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 localPos;
    float3 normal;
    float2 uv;
};

struct CameraUniforms {
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 viewProjectionMatrix;
    float3 position;
    float padding;
};

vertex StandardVertexOut vertex_mesh(
    StandardVertexIn in [[stage_in]],
    constant CameraUniforms &camera [[buffer(1)]],
    constant float4x4 &modelMatrix [[buffer(2)]]
) {
    StandardVertexOut out;
    
    float4 worldPos = modelMatrix * float4(in.position, 1.0);
    out.position = camera.viewProjectionMatrix * worldPos;
    out.worldPos = worldPos.xyz;
    out.localPos = in.position;
    out.normal = (modelMatrix * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    
    return out;
}

struct Light {
    float3 position;
    float3 color;
    float intensity;
    float padding;
};

struct LightingUniforms {
    Light lights[4];
    int lightCount;
};

fragment float4 fragment_mesh_standard(
    StandardVertexOut in [[stage_in]],
    constant LightingUniforms &lighting [[buffer(0)]]
) {
    float3 N = normalize(in.normal);
    float3 totalDiffuse = float3(0.0);
    
    for (int i = 0; i < lighting.lightCount; ++i) {
        Light light = lighting.lights[i];
        float3 L = normalize(light.position - in.worldPos);
        float dist = length(light.position - in.worldPos);
        float atten = 1.0 / (1.0 + 0.1 * dist * dist); // Simple quadratic falloff
        
        float NdotL = max(dot(N, L), 0.0);
        totalDiffuse += light.color * light.intensity * NdotL * atten;
    }
    
    // Fallback if no lights
    if (lighting.lightCount == 0) {
        totalDiffuse = float3(0.8, 0.8, 0.8) * max(dot(N, normalize(float3(1.0, 1.0, 1.0))), 0.0);
    }
    
    float3 ambient = float3(0.05, 0.05, 0.05);
    
    return float4(totalDiffuse + ambient, 1.0);
}

// Simple hash for noise
float hash12(float2 p) {
    float3 p3  = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

struct MaterialUniforms {
    float4 color;
    float twinkleStrength;
    float time;
    float2 padding;
};

fragment float4 fragment_mesh_unlit(
    StandardVertexOut in [[stage_in]],
    constant MaterialUniforms &material [[buffer(0)]]
) {
    return material.color;
}

fragment float4 fragment_mesh_textured(
    StandardVertexOut in [[stage_in]],
    constant MaterialUniforms &material [[buffer(0)]],
    texture2d<float> colorTexture [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::repeat);
    float4 texColor = colorTexture.sample(s, in.uv);
    
    float4 finalColor = texColor * material.color;
    if (material.twinkleStrength > 0.0) {
        // Twinkle logic
        // Use local position for stable noise (fixes popping when moving)
        // Snap to a grid in local space to get a unique ID per star
        // Stars are generated with random positions, so this should be unique enough
        float3 starID = floor(in.localPos * 10.0); 
        float noise = hash12(starID.xy + starID.z);
        
        // Animate
        // Slow down twinkle further
        float twinkle = sin(material.time * 0.5 + noise * 20.0) * 0.5 + 0.5;
        
        // Apply twinkle to alpha (for fading) and RGB (for intensity)
        // We want them to disappear and reappear
        finalColor.a *= (0.3 + 0.7 * twinkle);
        finalColor.rgb *= (0.5 + 1.5 * twinkle); // Allow them to get brighter
    }
    
    return finalColor;
}

// MARK: - Utility Shaders

struct QuadVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex QuadVertexOut vertex_fullscreen_triangle(uint vertexID [[vertex_id]]) {
    QuadVertexOut out;
    // Generates a full screen triangle: (-1, -1), (3, -1), (-1, 3)
    // UVs: (0, 1), (2, 1), (0, -1)
    float2 position = float2(float((vertexID << 1) & 2), float(vertexID & 2));
    // Fix: Set Z to 1.0 (Far Plane) to ensure background is behind everything
    out.position = float4(position * float2(2.0, 2.0) + float2(-1.0, -1.0), 1.0, 1.0);
    out.uv = float2(position.x, 1.0 - position.y);
    return out;
}

fragment float4 fragment_texture_passthrough(
    QuadVertexOut in [[stage_in]],
    texture2d<float> texture [[texture(0)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return texture.sample(s, in.uv);
}
