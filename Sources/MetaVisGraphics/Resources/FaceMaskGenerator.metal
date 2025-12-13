#include <metal_stdlib>
using namespace metal;

// Generates a boolean-ish mask based on Face Rects
// Uses soft falloff for blending.

// Rounded Box SDF
float sdRoundedBox(float2 p, float2 b, float4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x  = (p.y > 0.0) ? r.x  : r.y;
    float2 q = abs(p) - b + r.x;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r.x;
}

// Ellipse distance approximation
float sdEllipse(float2 p, float2 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0 * (k0 - 1.0) / k1;
}

kernel void fx_generate_face_mask(
    texture2d<float, access::write> mask [[texture(0)]],
    constant float4* faceRects [[buffer(0)]], // [x, y, w, h] normalized
    constant uint& faceCount [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= mask.get_width() || gid.y >= mask.get_height()) return;
    
    float width = float(mask.get_width());
    float height = float(mask.get_height());
    float2 uv = float2(gid) / float2(width, height);
    
    float maskValue = 0.0;
    
    // Iterate all faces
    // Max faces: 16 (Hard limit for performance in this loop)
    uint count = min(faceCount, 16u);
    
    for (uint i = 0; i < count; i++) {
        float4 rect = faceRects[i];
        
        // Rect Center
        float2 center = float2(rect.x + rect.z * 0.5, rect.y + rect.w * 0.5);
        float2 size = float2(rect.z * 0.5, rect.w * 0.5); // Radii
        
        // Ellipse Shape
        float2 p = uv - center;
        
        // Adjust for aspect ratio of texture?
        // UV space 0-1.
        
        // Simple Ellipse falloff
        // normalized distance
        float2 d = p / size;
        float distSq = dot(d, d);
        
        // Soft edge
        // 1.0 at center, 0.0 at edge
        float faceVal = 1.0 - smoothstep(0.5, 1.5, distSq);
        
        maskValue = max(maskValue, faceVal);
    }
    
    mask.write(float4(maskValue, 0, 0, 1), gid);
}
