#include <metal_stdlib>
#include "ColorSpace.metal"

using namespace metal;

/// Signed Distance Field Text Shaders
/// Based on: Metal by Example, Chapter 12 (pages 114-116)
/// 
/// Features:
/// - Infinite scalability without blur
/// - Per-pixel antialiasing with derivatives
/// - Single-channel texture (R8Unorm) for memory efficiency
/// - ACEScg Linear Color Output

// MARK: - Vertex Structures

struct SDFVertexIn {
    float2 position [[attribute(0)]];
    float2 texCoords [[attribute(1)]];
};

struct SDFVertexOut {
    float4 position [[position]];
    float2 texCoords;
    float depth;
};

// MARK: - Vertex Shader

vertex SDFVertexOut sdf_vertex(
    SDFVertexIn in [[stage_in]],
    constant float4x4 &mvpMatrix [[buffer(1)]]
) {
    SDFVertexOut out;
    out.position = mvpMatrix * float4(in.position, 0, 1);
    out.texCoords = in.texCoords;
    out.depth = out.position.w;
    return out;
}

// MARK: - Uniforms

struct SDFUniforms {
    float4 color;           // Text color (RGBA)
    float edgeDistance;     // 0.5 is standard. < 0.5 is bolder, > 0.5 is thinner.
    float edgeSoftness;     // Multiplier for edge width. 1.0 is sharp, > 1.0 is blurry.
    float2 padding1;
    float4 outlineColor;    // Outline color (RGBA)
    float outlineWidth;     // Width of outline in pixels (0.0 = no outline)
    float fadeStart;        // Distance where fade begins (alpha = 1.0)
    float fadeEnd;          // Distance where fade ends (alpha = 0.0)
    float padding2;
};

// MARK: - Helper Functions

// MARK: - Text Rendering Utilities

namespace Text {
namespace SDF {

inline float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

// Subpixel Anti-Aliasing (RGB)
// Samples at 1/3 pixel offsets for each color channel
// Provides 3× horizontal resolution for improved text sharpness
inline float3 computeSubpixelAA(
    texture2d<float> sdfTexture,
    sampler sdfSampler,
    float2 texCoords,
    float edgeDistance,
    float edgeSoftness
) {
    // Calculate per-pixel offset (1/3 pixel for each RGB channel)
    float2 texelSize = 1.0f / float2(sdfTexture.get_width(), sdfTexture.get_height());
    float dx = texelSize.x / 3.0f;
    
    // Sample at offset positions for R, G, B
    float distR = sdfTexture.sample(sdfSampler, texCoords + float2(-dx, 0)).r;
    float distG = sdfTexture.sample(sdfSampler, texCoords).r;
    float distB = sdfTexture.sample(sdfSampler, texCoords + float2(dx, 0)).r;
    
    // Calculate edge width using center sample's derivative
    float distPerPixel = length(float2(dfdx(distG), dfdy(distG)));
    float edgeWidth = 0.7 * distPerPixel * edgeSoftness;
    
    // Apply smoothstep to each channel independently
    float3 aa = smoothstep(
        edgeDistance - edgeWidth,
        edgeDistance + edgeWidth,
        float3(distR, distG, distB)
    );
    
    return aa;
}

// Gamma correction for accurate perceived weight
inline float3 applyGammaCorrection(float3 alpha) {
    return pow(alpha, 1.0/2.2); // sRGB gamma
}

} // namespace SDF
} // namespace Text

// MARK: - Helper Functions (Legacy - use Text::SDF::median)

float median(float r, float g, float b) {
    return Text::SDF::median(r, g, b);
}

// MARK: - Fragment Shader

fragment half4 sdf_fragment(
    SDFVertexOut in [[stage_in]],
    texture2d<float> sdfTexture [[texture(0)]],
    sampler sdfSampler [[sampler(0)]],
    constant SDFUniforms &uniforms [[buffer(0)]]
) {
    // Calculate fade alpha
    float fadeAlpha = 1.0;
    if (uniforms.fadeEnd > uniforms.fadeStart) {
        fadeAlpha = smoothstep(uniforms.fadeEnd, uniforms.fadeStart, in.depth);
    }

    // Subpixel anti-aliasing (RGB)
    float3 textAlpha = Text::SDF::computeSubpixelAA(
        sdfTexture,
        sdfSampler,
        in.texCoords,
        uniforms.edgeDistance,
        uniforms.edgeSoftness
    );
    
    // Apply fade
    textAlpha *= fadeAlpha;
    
    // Handle outline (uses grayscale AA for outline)
    if (uniforms.outlineWidth > 0.0) {
        float dist = sdfTexture.sample(sdfSampler, in.texCoords).r;
        float distPerPixel = length(float2(dfdx(dist), dfdy(dist)));
        float edgeWidth = 0.7 * distPerPixel * uniforms.edgeSoftness;
        
        float outlineDistDelta = uniforms.outlineWidth * distPerPixel;
        float outlineEdge = uniforms.edgeDistance - outlineDistDelta;
        float outlineOpacity = smoothstep(outlineEdge - edgeWidth, outlineEdge + edgeWidth, dist);
        
        // Apply fade to outline
        outlineOpacity *= fadeAlpha;
        
        float3 linearColor = Core::ColorSpace::DecodeToACEScg(uniforms.color.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
        float3 linearOutline = Core::ColorSpace::DecodeToACEScg(uniforms.outlineColor.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
        
        half3 textColor = half3(linearColor) * half3(textAlpha); // RGB subpixel
        half3 outlineColor = half3(linearOutline) * half(outlineOpacity);
        
        // Mix outline and text
        half3 blendedColor = mix(outlineColor, textColor, half3(textAlpha));
        
        return half4(blendedColor, half(outlineOpacity));
    }
    
    // Output with subpixel AA
    float3 linearColor = Core::ColorSpace::DecodeToACEScg(uniforms.color.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
    
    // Gamma correction for perceived weight accuracy
    float3 gammaAlpha = Text::SDF::applyGammaCorrection(textAlpha);
    
    return half4(half3(linearColor) * half3(gammaAlpha), half(dot(gammaAlpha, float3(1.0/3.0))));
}

fragment half4 msdf_fragment(
    SDFVertexOut in [[stage_in]],
    texture2d<float> msdfTexture [[texture(0)]],
    sampler sdfSampler [[sampler(0)]],
    constant SDFUniforms &uniforms [[buffer(0)]]
) {
    // Calculate fade alpha
    float fadeAlpha = 1.0;
    if (uniforms.fadeEnd > uniforms.fadeStart) {
        fadeAlpha = smoothstep(uniforms.fadeEnd, uniforms.fadeStart, in.depth);
    }

    // Sample MSDF texture (RGB)
    float4 sample = msdfTexture.sample(sdfSampler, in.texCoords);
    
    // Compute signed distance from median of RGB channels
    float dist = median(sample.r, sample.g, sample.b);
    
    // Dynamic weight control
    float edgeDistance = uniforms.edgeDistance;
    
    // Dynamic softness/blur control
    // dfdx/dfdy gives us the rate of change of the distance field relative to screen pixels.
    float distPerPixel = length(float2(dfdx(dist), dfdy(dist)));
    float edgeWidth = 0.7 * distPerPixel * uniforms.edgeSoftness;
    
    // Smoothstep provides the anti-aliased edge
    float textOpacity = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, dist);
    
    // Apply fade
    textOpacity *= fadeAlpha;
    
    // Handle outline
    if (uniforms.outlineWidth > 0.0) {
        // Convert pixel width to distance units
        float outlineDistDelta = uniforms.outlineWidth * distPerPixel;
        float outlineEdge = edgeDistance - outlineDistDelta;
        
        // Calculate outline opacity
        float outlineOpacity = smoothstep(outlineEdge - edgeWidth, outlineEdge + edgeWidth, dist);
        
        // Apply fade to outline
        outlineOpacity *= fadeAlpha;
        
        // Blend outline and text
        float3 linearColor = ColorSpace::DecodeToACEScg(uniforms.color.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
        float3 linearOutline = ColorSpace::DecodeToACEScg(uniforms.outlineColor.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
        
        half4 textColor = half4(half3(linearColor), half(uniforms.color.a));
        half4 outlineColor = half4(half3(linearOutline), half(uniforms.outlineColor.a));
        
        // Mix outline and text (text on top)
        half4 blendedColor = mix(outlineColor, textColor, half(textOpacity));
        
        // Final alpha is determined by the outline shape
        return blendedColor * half(outlineOpacity);
    }
    
    // Output Premultiplied Alpha with ACEScg color workflow
    float3 linearColor = Core::ColorSpace::DecodeToACEScg(uniforms.color.rgb, Core::ColorSpace::TF_SRGB, Core::ColorSpace::PRIM_SRGB);
    return half4(half3(linearColor) * half(textOpacity), half(textOpacity));
}

fragment half4 mtsdf_fragment(
    SDFVertexOut in [[stage_in]],
    texture2d<float> mtsdfTexture [[texture(0)]],
    sampler sdfSampler [[sampler(0)]],
    constant SDFUniforms &uniforms [[buffer(0)]]
) {
    // Calculate fade alpha
    float fadeAlpha = 1.0;
    if (uniforms.fadeEnd > uniforms.fadeStart) {
        fadeAlpha = smoothstep(uniforms.fadeEnd, uniforms.fadeStart, in.depth);
    }

    // Sample MTSDF texture (RGBA)
    // R,G,B = MSDF (Sharp Corners)
    // A = True SDF (Accurate Distance)
    float4 sample = mtsdfTexture.sample(sdfSampler, in.texCoords);
    
    // 1. Shape Distance (Sharp Corners) -> Median(R,G,B)
    float shapeDist = median(sample.r, sample.g, sample.b);
    
    // 2. True Distance (Accurate Outlines) -> Alpha
    float trueDist = sample.a;
    
    // Dynamic weight control
    float edgeDistance = uniforms.edgeDistance;
    
    // Anti-aliasing width (Shape)
    float distPerPixel = length(float2(dfdx(shapeDist), dfdy(shapeDist)));
    float edgeWidth = 0.7 * distPerPixel * uniforms.edgeSoftness;
    
    // Main Text Opacity (Use Shape Distance for sharp corners)
    float textOpacity = smoothstep(edgeDistance - edgeWidth, edgeDistance + edgeWidth, shapeDist);
    
    // Apply fade
    textOpacity *= fadeAlpha;
    
    // Handle outline
    if (uniforms.outlineWidth > 0.0) {
        // Use TRUE distance for outline to avoid artifacts
        float trueDistPerPixel = length(float2(dfdx(trueDist), dfdy(trueDist)));
        float outlineDistDelta = uniforms.outlineWidth * trueDistPerPixel;
        float outlineEdge = edgeDistance - outlineDistDelta;
        
        // Calculate outline opacity using TRUE distance
        // Note: We use the same edge softness logic
        float outlineEdgeWidth = 0.7 * trueDistPerPixel * uniforms.edgeSoftness;
        float outlineOpacity = smoothstep(outlineEdge - outlineEdgeWidth, outlineEdge + outlineEdgeWidth, trueDist);
        
        // Apply fade to outline
        outlineOpacity *= fadeAlpha;
        
        // Blend outline and text
        float3 linearColor = ColorSpace::DecodeToACEScg(uniforms.color.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
        float3 linearOutline = ColorSpace::DecodeToACEScg(uniforms.outlineColor.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
        
        half4 textColor = half4(half3(linearColor), half(uniforms.color.a));
        half4 outlineColor = half4(half3(linearOutline), half(uniforms.outlineColor.a));
        
        // Mix outline and text (text on top)
        half4 blendedColor = mix(outlineColor, textColor, half(textOpacity));
        
        return blendedColor * half(outlineOpacity);
    }
    
    float3 linearColor = ColorSpace::DecodeToACEScg(uniforms.color.rgb, ColorSpace::TF_SRGB, ColorSpace::PRIM_SRGB);
    return half4(half3(linearColor) * half(textOpacity), half(textOpacity));
}

// MARK: - Compute Kernel for Text Layout

kernel void sdf_text_layout(
    texture2d<float, access::read> sdfAtlas [[texture(0)]],
    texture2d<half, access::write> outputTexture [[texture(1)]],
    constant float2 *positions [[buffer(0)]],
    constant float2 *texCoords [[buffer(1)]],
    constant float4 &textColor [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check bounds
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    // Background is transparent
    half4 color = half4(0, 0, 0, 0);
    
    // TODO: Sample from SDF atlas at current pixel
    // This would involve looking up which glyph covers this pixel
    // and sampling from the corresponding atlas region
    
    outputTexture.write(color, gid);
}
