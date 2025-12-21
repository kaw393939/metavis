#include <metal_stdlib>
#include "ColorSpace.metal"
using namespace metal;

/// Instanced SDF Text Shaders
/// 
/// **Memory Optimization**: 2.4× reduction vs standard rendering
/// - Standard: 96 bytes per glyph (6 vertices × 16 bytes)
/// - Instanced: 40 bytes per glyph (1 instance × 40 bytes)
///
/// **Architecture**:
/// - Shared quad geometry (4 vertices, 6 indices)
/// - Per-instance data: position, scale, UV offset/scale, color
/// - Single draw call for all glyphs
///
/// Reference: Sprint 2 Phase 2 - Instanced Rendering

// MARK: - Vertex Structures

struct SDFInstancedVertexIn {
    float2 position [[attribute(0)]];      // Shared quad position (0-1 range)
    float2 texCoords [[attribute(1)]];     // Shared quad UVs (0-1 range)
    
    // Per-instance attributes
    float2 instancePosition [[attribute(2)]];  // Glyph position (screen space)
    float2 instanceScale [[attribute(3)]];     // Glyph size (width, height)
    float2 instanceUVOffset [[attribute(4)]];  // Atlas UV top-left
    float2 instanceUVScale [[attribute(5)]];   // Atlas UV size
    float4 instanceColor [[attribute(6)]];     // Per-glyph color (RGBA)
};

struct SDFVertexOut {
    float4 position [[position]];
    float2 texCoords;
    float4 color;  // Pass through per-instance color
};

// MARK: - Instanced Vertex Shader

vertex SDFVertexOut sdf_instanced_vertex(
    SDFInstancedVertexIn in [[stage_in]],
    constant float4x4 &mvpMatrix [[buffer(1)]]
) {
    SDFVertexOut out;
    
    // Transform shared quad to glyph position and scale
    // Position: [0,1] → [instancePosition, instancePosition + instanceScale]
    float2 worldPosition = in.instancePosition + (in.position * in.instanceScale);
    
    // Apply MVP matrix to get clip space position
    out.position = mvpMatrix * float4(worldPosition, 0, 1);
    
    // Transform shared quad UVs [0,1] to atlas UVs
    // UV: [0,1] → [instanceUVOffset, instanceUVOffset + instanceUVScale]
    out.texCoords = in.instanceUVOffset + (in.texCoords * in.instanceUVScale);
    
    // Pass through per-instance color
    out.color = in.instanceColor;
    
    return out;
}

// MARK: - Uniforms (same as standard SDF)

struct SDFUniforms {
    float4 color;           // Global text color (can be overridden by instance color)
    float edgeDistance;     // 0.5 is standard
    float edgeSoftness;     // 1.0 is sharp
    float4 outlineColor;    // Outline color
    float outlineWidth;     // Outline width in pixels
};

// MARK: - Fragment Shaders (reuse from SDFText.metal)

/// Standard SDF fragment shader (single-channel)
fragment half4 sdf_instanced_fragment(
    SDFVertexOut in [[stage_in]],
    texture2d<float> sdfTexture [[texture(0)]],
    sampler sdfSampler [[sampler(0)]],
    constant SDFUniforms &uniforms [[buffer(0)]]
) {
    // Sample distance field
    float dist = sdfTexture.sample(sdfSampler, in.texCoords).r;
    
    // Dynamic edge control
    float edgeDistance = uniforms.edgeDistance;
    float distPerPixel = length(float2(dfdx(dist), dfdy(dist)));
    float edgeWidth = 0.7 * distPerPixel * uniforms.edgeSoftness;
    
    // Anti-aliased edge
    float textOpacity = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, dist);
    
    // Handle outline
    if (uniforms.outlineWidth > 0.0) {
        float outlineDistDelta = uniforms.outlineWidth * distPerPixel;
        float outlineEdge = edgeDistance - outlineDistDelta;
        float outlineOpacity = smoothstep(outlineEdge - edgeWidth, outlineEdge + edgeWidth, dist);
        
        // Blend outline and text
        half4 textColor = half4(half3(in.color.rgb), half(in.color.a));  // Use instance color
        half4 outlineColor = half4(half3(uniforms.outlineColor.rgb), half(uniforms.outlineColor.a));
        
        half4 blendedColor = mix(outlineColor, textColor, half(textOpacity));
        return blendedColor * half(outlineOpacity);
    }
    
    // Output premultiplied alpha with ACEScg
    float3 linearColor = Core::ColorSpace::DecodeToACEScg(in.color.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
    return half4(half3(linearColor) * half(textOpacity), half(textOpacity));
}

// MARK: - Helper Functions

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

/// MSDF fragment shader (multi-channel)
fragment half4 msdf_instanced_fragment(
    SDFVertexOut in [[stage_in]],
    texture2d<float> msdfTexture [[texture(0)]],
    sampler sdfSampler [[sampler(0)]],
    constant SDFUniforms &uniforms [[buffer(0)]]
) {
    // Sample MSDF (RGB)
    float4 sample = msdfTexture.sample(sdfSampler, in.texCoords);
    float dist = median(sample.r, sample.g, sample.b);
    
    // Dynamic edge control
    float edgeDistance = uniforms.edgeDistance;
    float distPerPixel = length(float2(dfdx(dist), dfdy(dist)));
    float edgeWidth = 0.7 * distPerPixel * uniforms.edgeSoftness;
    
    // Anti-aliased edge
    float textOpacity = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, dist);
    
    // Handle outline
    if (uniforms.outlineWidth > 0.0) {
        float outlineDistDelta = uniforms.outlineWidth * distPerPixel;
        float outlineEdge = edgeDistance - outlineDistDelta;
        float outlineOpacity = smoothstep(outlineEdge - edgeWidth, outlineEdge + edgeWidth, dist);
        
        half4 textColor = half4(half3(in.color.rgb), half(in.color.a));
        half4 outlineColor = half4(half3(uniforms.outlineColor.rgb), half(uniforms.outlineColor.a));
        
        half4 blendedColor = mix(outlineColor, textColor, half(textOpacity));
        return blendedColor * half(outlineOpacity);
    }
    
    float3 linearColor = Core::ColorSpace::DecodeToACEScg(in.color.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
    return half4(half3(linearColor) * half(textOpacity), half(textOpacity));
}

/// MTSDF fragment shader (multi-channel true SDF)
fragment half4 mtsdf_instanced_fragment(
    SDFVertexOut in [[stage_in]],
    texture2d<float> mtsdfTexture [[texture(0)]],
    sampler sdfSampler [[sampler(0)]],
    constant SDFUniforms &uniforms [[buffer(0)]]
) {
    // Sample MTSDF (RGBA: R,G,B=MSDF, A=True SDF)
    float4 sample = mtsdfTexture.sample(sdfSampler, in.texCoords);
    
    // Shape distance (sharp corners)
    float shapeDist = median(sample.r, sample.g, sample.b);
    
    // True distance (accurate outlines)
    float trueDist = sample.a;
    
    // Dynamic edge control
    float edgeDistance = uniforms.edgeDistance;
    
    // Anti-aliasing width (shape)
    float distPerPixel = length(float2(dfdx(shapeDist), dfdy(shapeDist)));
    float edgeWidth = 0.7 * distPerPixel * uniforms.edgeSoftness;
    
    // Text opacity (sharp corners)
    float textOpacity = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, shapeDist);
    
    // Handle outline
    if (uniforms.outlineWidth > 0.0) {
        // Use true distance for outline
        float trueDistPerPixel = length(float2(dfdx(trueDist), dfdy(trueDist)));
        float outlineDistDelta = uniforms.outlineWidth * trueDistPerPixel;
        float outlineEdge = edgeDistance - outlineDistDelta;
        float outlineEdgeWidth = 0.7 * trueDistPerPixel * uniforms.edgeSoftness;
        float outlineOpacity = smoothstep(outlineEdge - outlineEdgeWidth, outlineEdge + outlineEdgeWidth, trueDist);
        
        half4 textColor = half4(half3(in.color.rgb), half(in.color.a));
        half4 outlineColor = half4(half3(uniforms.outlineColor.rgb), half(uniforms.outlineColor.a));
        
        half4 blendedColor = mix(outlineColor, textColor, half(textOpacity));
        return blendedColor * half(outlineOpacity);
    }
    
    float3 linearColor = Core::ColorSpace::DecodeToACEScg(in.color.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
    return half4(half3(linearColor) * half(textOpacity), half(textOpacity));
}
