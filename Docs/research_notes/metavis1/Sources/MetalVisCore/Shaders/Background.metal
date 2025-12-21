#include <metal_stdlib>
using namespace metal;

#ifndef BACKGROUND_METAL
#define BACKGROUND_METAL

namespace Background {

    // MARK: - Core Functions

    // Solid Color Background
    // Input: Linear ACEScg Color, Alpha
    // Output: Premultiplied ACEScg
    inline float4 BackgroundSolidACES(float3 acesColor, float alpha) {
        float a = clamp(alpha, 0.0f, 1.0f);
        float3 rgb = max(acesColor, 0.0f); // No negative radiance
        return float4(rgb * a, a);
    }

    // Gradient Background
    // Input: Top/Bottom Linear ACEScg Colors, UV, Alpha
    // Output: Premultiplied ACEScg
    inline float4 BackgroundGradientACES(float3 topColor, float3 bottomColor, float2 uv, float alpha) {
        float t = clamp(uv.y, 0.0f, 1.0f);
        // Linear interpolation in ACEScg space
        float3 rgb = mix(bottomColor, topColor, t);
        float a = clamp(alpha, 0.0f, 1.0f);
        return float4(rgb * a, a);
    }

    // Texture Background
    // Input: Texture (assumed ACEScg), Sampler, UV, Alpha
    // Output: Premultiplied ACEScg
    inline float4 BackgroundTextureACES(texture2d<float> tex, sampler s, float2 uv, float alpha) {
        float4 sample = tex.sample(s, uv);
        
        // Assume texture sample is straight alpha (common for assets)
        // Convert to premultiplied: rgb * a
        // Then apply global alpha
        
        float3 rgb = sample.rgb;
        float a = sample.a;
        float premA = clamp(a * alpha, 0.0f, 1.0f);
        
        // Note: If texture is already premultiplied, this double-multiplies.
        // But per spec "Convert straight alpha sample to premultiplied output"
        return float4(rgb * premA, premA);
    }

    // Starfield Background
    // Input: UV, Density
    // Output: Premultiplied ACEScg
    inline float4 BackgroundStarfieldACES(float2 uv, float density, float alpha) {
        // Simple procedural stars
        // Hash function based on UV
        float2 p = uv * density;
        float2 i = floor(p);
        float2 f = fract(p);
        
        // Random value for this cell
        float n = fract(sin(dot(i, float2(12.9898, 78.233))) * 43758.5453);
        
        // Star core
        // Threshold adjusted for visibility (0.98 = 2% density)
        float star = step(0.98, n); 
        
        // Vary brightness
        float brightness = fract(n * 13.0);
        
        float3 color = float3(star * brightness);
        
        // Apply alpha
        return float4(color * alpha, alpha); // Stars are additive usually, but here we treat as solid background layer
    }

} // namespace Background

// MARK: - Shaders

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct BackgroundUniforms {
    float4 colorTop;
    float4 colorBottom;
    float starDensity; // Added
};

vertex VertexOut vertex_background_quad(uint vertexID [[vertex_id]]) {
    VertexOut out;
    
    // Generate a full-screen quad from 6 vertices (2 triangles)
    // 0, 1, 2 -> Tri 1
    // 3, 4, 5 -> Tri 2
    float2 positions[6] = {
        float2(-1.0, -1.0), // 0: BL
        float2( 1.0, -1.0), // 1: BR
        float2(-1.0,  1.0), // 2: TL
        float2(-1.0,  1.0), // 3: TL
        float2( 1.0, -1.0), // 4: BR
        float2( 1.0,  1.0)  // 5: TR
    };
    
    float2 pos = positions[vertexID];
    out.position = float4(pos, 1.0, 1.0);  // Z=1.0 (far plane), consistent with fullscreen triangle

    
    // UV coordinates (0,0 at top-left)
    // (-1, 1) -> (0, 0)
    // (1, -1) -> (1, 1)
    out.uv = pos * float2(0.5, -0.5) + 0.5;
    
    return out;
}

fragment float4 fragment_background_gradient(
    VertexOut in [[stage_in]],
    constant BackgroundUniforms &uniforms [[buffer(0)]]
) {
    // Use the Background namespace
    // Assume uniforms.colorTop/Bottom are linear ACEScg
    
    return Background::BackgroundGradientACES(
        uniforms.colorTop.rgb,
        uniforms.colorBottom.rgb,
        in.uv,
        1.0 // Default alpha 1.0
    );
}

fragment float4 fragment_background_starfield(
    VertexOut in [[stage_in]],
    constant BackgroundUniforms &uniforms [[buffer(0)]]
) {
    return Background::BackgroundStarfieldACES(
        in.uv,
        uniforms.starDensity,
        1.0
    );
}

#endif // BACKGROUND_METAL
