#include <metal_stdlib>
using namespace metal;

// Vertex structure for nodes (circles)
struct NodeUniforms {
    float2 center;
    float size;
    float4 color;
    float2 screenSize;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

// Vertex shader for nodes
vertex VertexOut node_vertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]],
    constant NodeUniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    
    float2 in_position = vertices[vertexID];
    
    // Scale to screen space
    float2 screenPos = (in_position * uniforms.size) + uniforms.center;
    float2 normalizedPos = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    normalizedPos.y = -normalizedPos.y; // Flip Y
    
    out.position = float4(normalizedPos, 0.0, 1.0);
    out.texCoord = in_position;
    out.color = uniforms.color;
    
    return out;
}

// Fragment shader for nodes (circle with anti-aliasing)
fragment float4 node_fragment(
    VertexOut in [[stage_in]]
) {
    float2 center = float2(0.0, 0.0);
    float dist = length(in.texCoord - center);
    
    // Smooth circle with anti-aliasing
    float alpha = smoothstep(1.0, 0.95, dist);
    
    return float4(in.color.rgb, in.color.a * alpha);
}

// Edge rendering (line)
struct EdgeUniforms {
    float2 start;
    float2 end;
    float thickness;
    float4 color;
    float2 screenSize;
};

vertex VertexOut edge_vertex(
    uint vertexID [[vertex_id]],
    constant EdgeUniforms &uniforms [[buffer(0)]]
) {
    VertexOut out;
    
    // Generate quad for line
    float2 direction = uniforms.end - uniforms.start;
    float2 perpendicular = normalize(float2(-direction.y, direction.x)) * uniforms.thickness;
    
    float2 positions[4] = {
        uniforms.start - perpendicular,
        uniforms.start + perpendicular,
        uniforms.end - perpendicular,
        uniforms.end + perpendicular
    };
    
    float2 screenPos = positions[vertexID];
    float2 normalizedPos = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    normalizedPos.y = -normalizedPos.y;
    
    out.position = float4(normalizedPos, 0.0, 1.0);
    out.texCoord = float2(0.0, 0.0);
    out.color = uniforms.color;
    
    return out;
}

fragment float4 edge_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}

// Simple text rendering with textured quads
struct SimpleTextUniforms {
    float2 position;    // Center position in screen space
    float2 size;        // Texture size in pixels
    float2 screenSize;
    float4 backgroundColor;
    float padding;
};

struct TextVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 backgroundColor;
};

vertex TextVertexOut simple_text_vertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]],
    constant SimpleTextUniforms &uniforms [[buffer(1)]]
) {
    TextVertexOut out;
    
    float2 in_position = vertices[vertexID];
    
    // Calculate quad corners (centered at position)
    float2 offset = (in_position - 0.5) * uniforms.size;
    float2 screenPos = uniforms.position + offset;
    
    float2 normalizedPos = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    normalizedPos.y = -normalizedPos.y; // Flip Y
    
    out.position = float4(normalizedPos, 0.0, 1.0);
    out.texCoord = in_position;
    out.backgroundColor = uniforms.backgroundColor;
    
    return out;
}

fragment float4 simple_text_fragment(
    TextVertexOut in [[stage_in]],
    texture2d<float> textTexture [[texture(0)]]
) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float4 textColor = textTexture.sample(textureSampler, in.texCoord);
    
    // Blend text over background
    return textColor;
}
