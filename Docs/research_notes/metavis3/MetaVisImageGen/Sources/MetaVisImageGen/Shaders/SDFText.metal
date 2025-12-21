#include <metal_stdlib>
using namespace metal;

struct TextVertex {
    float3 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct TextUniforms {
    float4x4 projectionMatrix;
    float4 color;
    float4 outlineColor;
    float4 shadowColor;
    float2 screenSize; // Width, Height
    float2 shadowOffset;
    float smoothing;
    float hasMask; // 0.0 = false, 1.0 = true
    float outlineWidth;
    float shadowBlur;
    float hasDepth; // 0.0 = no depth test, 1.0 = depth test enabled
    float depthBias; // Small bias to prevent z-fighting
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float2 shadowUV;
    float depth; // Normalized depth value (0-1, where 0 is near)
};

vertex VertexOut sdf_text_vertex(
    const device TextVertex* vertices [[buffer(0)]],
    constant TextUniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    VertexOut out;
    float4 clipPos = uniforms.projectionMatrix * float4(vertices[vid].position, 1.0);
    out.position = clipPos;
    out.uv = vertices[vid].uv;
    
    // Pass normalized depth to fragment shader for depth comparison
    // NDC depth: In Metal, depth ranges from 0 (near) to 1 (far)
    out.depth = clipPos.z / clipPos.w; // Normalized to [0,1] after perspective divide
    
    return out;
}

fragment float4 sdf_text_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]],
    texture2d<float> mask [[texture(1)]], // Optional mask
    depth2d<float> sceneDepth [[texture(2)]], // Optional scene depth for occlusion
    constant TextUniforms& uniforms [[buffer(1)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear);
    constexpr sampler sMask(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    constexpr sampler sDepth(mag_filter::nearest, min_filter::nearest, address::clamp_to_edge);
    
    // 1. Check Mask (Depth Compositing)
    if (uniforms.hasMask > 0.5) {
        float2 screenUV = in.position.xy / uniforms.screenSize;
        float maskVal = mask.sample(sMask, screenUV).r;
        if (maskVal > 0.1) {
            discard_fragment();
        }
    }
    
    // 2. Depth Occlusion Test
    // If depth texture is bound, compare text depth against scene depth
    if (uniforms.hasDepth > 0.5) {
        float2 screenUV = in.position.xy / uniforms.screenSize;
        float storedDepth = sceneDepth.sample(sDepth, screenUV);
        
        // Text depth (in.depth) vs scene depth (storedDepth)
        // In standard depth buffer: lower depth = closer to camera
        // If text is further (larger depth) than scene, discard it (occluded)
        if (in.depth > storedDepth + uniforms.depthBias) {
            discard_fragment();
        }
    }
    
    // Sample distance field
    float dist = atlas.sample(s, in.uv).r;
    
    // Adaptive Smoothing (Anti-aliasing)
    // fwidth(dist) gives us the rate of change of the distance field per screen pixel.
    // We want the transition to happen over ~1-2 screen pixels.
    // 0.5 is the edge.
    float smoothing = fwidth(dist);
    
    // --- Shadow ---
    // Sample distance field for Shadow using UV offset
    // TODO: Clamp this to glyph bounds to prevent atlas bleeding
    float shadowDist = atlas.sample(s, in.uv + uniforms.shadowOffset).r;
    
    float4 finalColor = float4(0.0);
    
    // 3. Shadow / Glow
    if (uniforms.shadowColor.a > 0.0) {
        // Shadows are naturally softer, so we can use a wider smoothing or the user-provided blur
        float shadowAlpha = smoothstep(0.5 - uniforms.shadowBlur, 0.5 + uniforms.shadowBlur, shadowDist);
        finalColor = mix(finalColor, uniforms.shadowColor, shadowAlpha * uniforms.shadowColor.a);
    }
    
    // 4. Outline
    if (uniforms.outlineWidth > 0.0) {
        // Outline is a band around 0.5.
        float outlineAlpha = smoothstep(0.5 - uniforms.outlineWidth - smoothing, 0.5 - uniforms.outlineWidth + smoothing, dist);
        finalColor = mix(finalColor, uniforms.outlineColor, outlineAlpha * uniforms.outlineColor.a);
    }
    
    // 5. Main Text Body
    float bodyAlpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, dist);
    finalColor = mix(finalColor, uniforms.color, bodyAlpha * uniforms.color.a);
    
    return finalColor;
}
