#include <metal_stdlib>
#include "ColorSpace.metal"

using namespace metal;

// Enhanced Edge Rendering with Cubic Bezier Curves
// Renders edges in Scene Linear ACEScg space.
// Input colors are assumed to be sRGB and are converted to ACEScg.

struct BezierEdgeUniforms {
    float2 p0;          // Start point
    float2 p1;          // First control point
    float2 p2;          // Second control point
    float2 p3;          // End point
    float thickness;
    float4 color;       // sRGB color
    float2 screenSize;
    float flowProgress; // Animation progress 0-1 for flow effect
    float highlightIntensity; // 0-1 for highlighting
    float4 highlightColor;    // sRGB color
    uint segments;      // Number of line segments to approximate curve (default 32)
};

struct BezierVertexOut {
    float4 position [[position]];
    float2 texCoord;    // For gradient/flow effects
    float4 color;
    float distToEdge;   // Distance to edge center for anti-aliasing
};

// Cubic Bezier curve evaluation
float2 evaluate_bezier(float t, float2 p0, float2 p1, float2 p2, float2 p3) {
    float t2 = t * t;
    float t3 = t2 * t;
    float mt = 1.0 - t;
    float mt2 = mt * mt;
    float mt3 = mt2 * mt;
    
    return mt3 * p0 + 3.0 * mt2 * t * p1 + 3.0 * mt * t2 * p2 + t3 * p3;
}

// Bezier tangent (derivative)
float2 bezier_tangent(float t, float2 p0, float2 p1, float2 p2, float2 p3) {
    float t2 = t * t;
    float mt = 1.0 - t;
    float mt2 = mt * mt;
    
    return 3.0 * mt2 * (p1 - p0) + 6.0 * mt * t * (p2 - p1) + 3.0 * t2 * (p3 - p2);
}

// Generate vertices for curved edge (tessellated)
kernel void generate_bezier_edge_vertices(
    constant BezierEdgeUniforms &uniforms [[buffer(0)]],
    device float4 *positions [[buffer(1)]],
    device float2 *texCoords [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    uint segments = uniforms.segments;
    uint vertexIndex = id;
    
    if (vertexIndex >= (segments + 1) * 2) {
        return;
    }
    
    uint segmentIdx = vertexIndex / 2;
    uint side = vertexIndex % 2;
    
    float t = float(segmentIdx) / float(segments);
    float2 pos = evaluate_bezier(t, uniforms.p0, uniforms.p1, uniforms.p2, uniforms.p3);
    float2 tangent = normalize(bezier_tangent(t, uniforms.p0, uniforms.p1, uniforms.p2, uniforms.p3));
    float2 normal = float2(-tangent.y, tangent.x);
    
    float offset = (side == 0 ? -1.0 : 1.0) * uniforms.thickness * 0.5;
    float2 vertexPos = pos + normal * offset;
    
    // Convert to normalized device coordinates
    float2 normalizedPos = (vertexPos / uniforms.screenSize) * 2.0 - 1.0;
    normalizedPos.y = -normalizedPos.y;
    
    positions[vertexIndex] = float4(normalizedPos, 0.0, 1.0);
    texCoords[vertexIndex] = float2(t, float(side));
}

// Simple vertex shader for pre-generated Bezier edges
vertex BezierVertexOut bezier_edge_vertex(
    uint vertexID [[vertex_id]],
    constant float4 *positions [[buffer(0)]],
    constant float2 *texCoords [[buffer(1)]],
    constant BezierEdgeUniforms &uniforms [[buffer(2)]]
) {
    BezierVertexOut out;
    
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    
    // Convert sRGB inputs to ACEScg Linear
    float3 linearColor = ColorSpace::DecodeToACEScg(uniforms.color.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
    out.color = float4(linearColor, uniforms.color.a);
    
    out.distToEdge = abs(texCoords[vertexID].y - 0.5) * 2.0; // 0 at center, 1 at edges
    
    return out;
}

// Fragment shader with flow animation and highlighting
fragment float4 bezier_edge_fragment(
    BezierVertexOut in [[stage_in]],
    constant BezierEdgeUniforms &uniforms [[buffer(0)]]
) {
    // Anti-aliasing at edges
    float edgeAlpha = 1.0 - smoothstep(0.8, 1.0, in.distToEdge);
    
    // Flow effect (animated gradient)
    float flowMask = 0.0;
    if (uniforms.flowProgress > 0.0) {
        float flowPos = in.texCoord.x - uniforms.flowProgress;
        flowMask = exp(-50.0 * flowPos * flowPos); // Gaussian pulse
    }
    
    // Highlight effect
    float4 finalColor = in.color;
    if (uniforms.highlightIntensity > 0.0) {
        float3 highlightLinear = ColorSpace::DecodeToACEScg(uniforms.highlightColor.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
        finalColor.rgb = mix(in.color.rgb, highlightLinear, uniforms.highlightIntensity * 0.5);
    }
    
    // Add flow glow
    if (flowMask > 0.01) {
        float3 highlightLinear = ColorSpace::DecodeToACEScg(uniforms.highlightColor.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
        finalColor.rgb += highlightLinear * flowMask * 2.0;
    }
    
    return float4(finalColor.rgb, finalColor.a * edgeAlpha);
}

// Straight edge with arrow head
struct ArrowEdgeUniforms {
    float2 start;
    float2 end;
    float thickness;
    float4 color;
    float2 screenSize;
    float arrowSize; // Size of arrow head
};

vertex BezierVertexOut arrow_edge_vertex(
    uint vertexID [[vertex_id]],
    constant ArrowEdgeUniforms &uniforms [[buffer(0)]]
) {
    BezierVertexOut out;
    
    float2 direction = normalize(uniforms.end - uniforms.start);
    float2 perpendicular = float2(-direction.y, direction.x);
    
    // Generate line + arrow head geometry
    // Vertices: 0-3 = line shaft, 4-6 = arrow head triangle
    float2 positions[7];
    float2 texCoords[7];
    
    // Line shaft
    positions[0] = uniforms.start - perpendicular * uniforms.thickness * 0.5;
    positions[1] = uniforms.start + perpendicular * uniforms.thickness * 0.5;
    positions[2] = uniforms.end - perpendicular * uniforms.thickness * 0.5;
    positions[3] = uniforms.end + perpendicular * uniforms.thickness * 0.5;
    
    texCoords[0] = float2(0.0, 0.0);
    texCoords[1] = float2(0.0, 1.0);
    texCoords[2] = float2(1.0, 0.0);
    texCoords[3] = float2(1.0, 1.0);
    
    // Arrow head triangle
    float arrowBase = uniforms.arrowSize * 0.5;
    positions[4] = uniforms.end;
    positions[5] = uniforms.end - direction * uniforms.arrowSize + perpendicular * arrowBase;
    positions[6] = uniforms.end - direction * uniforms.arrowSize - perpendicular * arrowBase;
    
    texCoords[4] = float2(1.0, 0.5);
    texCoords[5] = float2(0.8, 0.0);
    texCoords[6] = float2(0.8, 1.0);
    
    // Select vertex
    float2 screenPos = positions[vertexID];
    float2 normalizedPos = (screenPos / uniforms.screenSize) * 2.0 - 1.0;
    normalizedPos.y = -normalizedPos.y;
    
    out.position = float4(normalizedPos, 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    
    // Convert sRGB -> ACEScg
    float3 linearColor = ColorSpace::DecodeToACEScg(uniforms.color.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
    out.color = float4(linearColor, uniforms.color.a);
    
    out.distToEdge = 0.0;
    
    return out;
}

// Dashed edge shader
struct DashedEdgeUniforms {
    float2 start;
    float2 end;
    float thickness;
    float4 color;
    float2 screenSize;
    float dashLength;  // Length of each dash
    float gapLength;   // Length of gaps
};

fragment float4 dashed_edge_fragment(
    BezierVertexOut in [[stage_in]],
    constant DashedEdgeUniforms &uniforms [[buffer(0)]]
) {
    // Calculate dash pattern
    float totalLength = uniforms.dashLength + uniforms.gapLength;
    float position = fmod(in.texCoord.x * 100.0, totalLength); // Scale for visibility
    
    float dashAlpha = step(position, uniforms.dashLength);
    
    // Anti-aliasing
    float edgeAlpha = 1.0 - smoothstep(0.8, 1.0, in.distToEdge);
    
    return float4(in.color.rgb, in.color.a * edgeAlpha * dashAlpha);
}
