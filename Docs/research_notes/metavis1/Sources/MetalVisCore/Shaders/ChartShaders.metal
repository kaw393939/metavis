#include <metal_stdlib>
using namespace metal;

struct RectUniforms {
    float4 rect; // x, y, width, height (normalized 0-1 or screen coords)
    float4 color;
    float2 screenSize;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut rect_vertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]],
    constant RectUniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    
    float2 v = vertices[vertexID]; // -1 to 1
    
    // Convert rect from screen coords to NDC
    // rect.xy is center, rect.zw is size
    
    float2 center = uniforms.rect.xy;
    float2 size = uniforms.rect.zw;
    
    // Scale vertex by half size
    float2 pos = center + v * (size * 0.5);
    
    // Convert to NDC (-1 to 1)
    // Assuming center/size are in pixels
    float2 ndc = (pos / uniforms.screenSize) * 2.0 - 1.0;
    ndc.y = -ndc.y; // Flip Y for Metal
    
    out.position = float4(ndc, 0.0, 1.0);
    out.color = uniforms.color;
    
    return out;
}

fragment float4 rect_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}

struct PieUniforms {
    float2 center;
    float radius;
    float startAngle;
    float endAngle;
    float4 color;
    float2 screenSize;
};

struct PieVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float startAngle;
    float endAngle;
};

vertex PieVertexOut pie_vertex(
    uint vertexID [[vertex_id]],
    constant float2 *vertices [[buffer(0)]],
    constant PieUniforms &uniforms [[buffer(1)]]
) {
    PieVertexOut out;
    
    float2 v = vertices[vertexID]; // -1 to 1
    
    // Scale by radius
    float2 pos = uniforms.center + v * uniforms.radius;
    
    // Convert to NDC
    float2 ndc = (pos / uniforms.screenSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = v; // Keep -1 to 1 for angle calculation
    out.color = uniforms.color;
    out.startAngle = uniforms.startAngle;
    out.endAngle = uniforms.endAngle;
    
    return out;
}

fragment float4 pie_fragment(PieVertexOut in [[stage_in]]) {
    // Calculate angle of current pixel relative to center
    float angle = atan2(in.uv.y, in.uv.x); // -pi to pi
    
    // Normalize angle to 0 to 2pi
    if (angle < 0) {
        angle += 2.0 * M_PI_F;
    }
    
    // Check if inside radius (circle)
    if (length(in.uv) > 1.0) {
        discard_fragment();
    }
    
    // Check if inside angle range
    // Handle wrapping around 0/2pi
    float start = in.startAngle;
    float end = in.endAngle;
    
    // Simple range check (assumes no wrap for now, or pre-normalized)
    if (angle < start || angle > end) {
        discard_fragment();
    }
    
    return in.color;
}
