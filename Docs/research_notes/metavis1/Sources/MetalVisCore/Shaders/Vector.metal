#include <metal_stdlib>
using namespace metal;

struct VectorVertexIn {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VectorVertexOut {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

struct VectorUniforms {
    int shapeType; // 0 = Rect, 1 = Circle, 2 = RoundedRect
    float softness; // Edge softness
    float cornerRadius;
    float padding;
    float2 dimensions;
};

vertex VectorVertexOut vector_vertex(
    VectorVertexIn in [[stage_in]],
    constant float4x4 &mvpMatrix [[buffer(1)]]
) {
    VectorVertexOut out;
    out.position = mvpMatrix * float4(in.position, 0, 1);
    out.color = in.color;
    out.texCoord = in.texCoord;
    return out;
}

// SDF for a rounded box
// p: position relative to center
// b: half-size (width/2, height/2)
// r: corner radius
float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

fragment float4 vector_fragment(
    VectorVertexOut in [[stage_in]],
    constant VectorUniforms &uniforms [[buffer(0)]]
) {
    if (uniforms.shapeType == 1) {
        // Circle SDF
        // texCoord is 0..1. Center is 0.5, 0.5.
        float2 center = float2(0.5, 0.5);
        float dist = length(in.texCoord - center);
        float radius = 0.5;
        
        // Anti-aliasing
        float delta = fwidth(dist);
        float alpha = smoothstep(radius, radius - delta, dist);
        
        return float4(in.color.rgb, in.color.a * alpha);
    } else if (uniforms.shapeType == 2) {
        // Rounded Rect SDF
        // Convert texCoord (0..1) to pixels relative to center
        float2 p = (in.texCoord - 0.5) * uniforms.dimensions;
        float2 b = uniforms.dimensions * 0.5;
        float r = uniforms.cornerRadius;
        
        float dist = sdRoundedBox(p, b, r);
        
        // Anti-aliasing
        // dist is in pixels. Edge is at 0.
        // Inside is negative, outside is positive.
        float delta = fwidth(dist);
        float edgeWidth = max(delta, uniforms.softness);
        float alpha = 1.0 - smoothstep(-edgeWidth * 0.5, edgeWidth * 0.5, dist);
        
        return float4(in.color.rgb, in.color.a * alpha);
    }
    
    return in.color;
}

// MARK: - Vector Mesh Shader (2.5D Lit)

struct MeshVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct MeshVertexOut {
    float4 position [[position]];
    float3 worldNormal;
    float2 uv;
    float3 worldPosition;
};

struct MeshUniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float3 color;
    float roughness;
    float metallic;
};

vertex MeshVertexOut vector_mesh_vertex(
    MeshVertexIn in [[stage_in]],
    constant MeshUniforms &uniforms [[buffer(1)]]
) {
    MeshVertexOut out;
    
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    out.worldPosition = worldPos.xyz;
    
    // Transform normal to world space (assuming uniform scaling for now)
    // Normal is 3D, model matrix is 4x4.
    out.worldNormal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.uv = in.uv;
    
    return out;
}

fragment float4 vector_mesh_fragment(
    MeshVertexOut in [[stage_in]],
    constant MeshUniforms &uniforms [[buffer(1)]]
) {
    float3 N = normalize(in.worldNormal);
    float3 V = normalize(float3(0, 0, 1)); // View direction (simplified for 2.5D)
    float3 L = normalize(float3(0.5, 0.5, 1.0)); // Directional Light
    
    // Base Color
    float3 albedo = uniforms.color;
    
    // Diffuse (Lambert)
    float NdotL = max(0.0, dot(N, L));
    float3 diffuse = albedo * NdotL;
    
    // Specular (Blinn-Phong)
    float3 H = normalize(L + V);
    float NdotH = max(0.0, dot(N, H));
    float specularPower = (1.0 - uniforms.roughness) * 128.0;
    float specularIntensity = pow(NdotH, specularPower) * uniforms.metallic;
    float3 specular = float3(1.0) * specularIntensity;
    
    // Ambient
    float3 ambient = albedo * 0.2;
    
    float3 finalColor = ambient + diffuse + specular;
    
    return float4(finalColor, 1.0);
}
