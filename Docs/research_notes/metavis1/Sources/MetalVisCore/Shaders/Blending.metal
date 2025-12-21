#include <metal_stdlib>
using namespace metal;

#ifndef BLENDING_METAL
#define BLENDING_METAL

namespace Blending {

    // MARK: - Constants
    
    constant int BLEND_OVER = 0;
    constant int BLEND_ADD = 1;
    constant int BLEND_MULTIPLY = 2;
    constant int BLEND_SCREEN = 3;
    constant int BLEND_OVERLAY = 4;
    constant int BLEND_SOFT_LIGHT = 5;
    constant int BLEND_HARD_LIGHT = 6;
    constant int BLEND_LINEAR_DODGE = 7;

    // ACEScg Luma Coefficients (approximate)
    constant float3 ACES_LUMA = float3(0.2722287, 0.6740818, 0.0536895);

    // MARK: - Helpers

    inline float3 Unpremultiply(float3 rgb, float a) {
        return rgb / max(a, 1e-6f);
    }

    inline float3 Repremultiply(float3 rgb, float a) {
        return rgb * a;
    }

    // MARK: - Blend Modes

    // Standard Alpha Over
    // Inputs: Premultiplied
    inline float4 BlendOver(float4 fg, float4 bg) {
        float invFgA = 1.0f - fg.a;
        float a_out = fg.a + bg.a * invFgA;
        float3 rgb_out = fg.rgb + bg.rgb * invFgA;
        return float4(rgb_out, a_out);
    }

    // Additive / Emission
    // Inputs: Premultiplied
    inline float4 BlendAdd(float4 emission, float4 base) {
        float a = clamp(emission.a + base.a, 0.0f, 1.0f);
        float3 rgb = base.rgb + emission.rgb;
        return float4(rgb, a);
    }
    
    // Linear Dodge (Same as Add but usually implies color add, alpha union?)
    // Spec says "BlendLinearDodge". Usually Linear Dodge is just Add.
    inline float4 BlendLinearDodge(float4 top, float4 bottom) {
        return BlendAdd(top, bottom);
    }

    // Multiply
    // Inputs: Premultiplied
    inline float4 BlendMultiply(float4 top, float4 bottom) {
        // 1. Unpremultiply
        float3 top_un = Unpremultiply(top.rgb, top.a);
        float3 bottom_un = Unpremultiply(bottom.rgb, bottom.a);
        
        // 2. Multiply
        float3 res_un = top_un * bottom_un;
        
        // 3. Alpha Union
        float a_out = top.a + bottom.a * (1.0f - top.a);
        
        // 4. Repremultiply
        return float4(Repremultiply(res_un, a_out), a_out);
    }

    // Screen
    // Inputs: Premultiplied
    inline float4 BlendScreen(float4 top, float4 bottom) {
        // 1. Unpremultiply
        float3 top_un = Unpremultiply(top.rgb, top.a);
        float3 bottom_un = Unpremultiply(bottom.rgb, bottom.a);
        
        // 2. Screen: 1 - (1-a)*(1-b)
        float3 res_un = 1.0f - (1.0f - top_un) * (1.0f - bottom_un);
        
        // 3. Alpha Union
        float a_out = top.a + bottom.a * (1.0f - top.a);
        
        // 4. Repremultiply
        return float4(Repremultiply(res_un, a_out), a_out);
    }

    // Overlay
    // Inputs: Premultiplied
    inline float4 BlendOverlay(float4 top, float4 bottom) {
        float3 top_un = Unpremultiply(top.rgb, top.a);
        float3 bottom_un = Unpremultiply(bottom.rgb, bottom.a);
        
        float3 res_un;
        for(int i=0; i<3; i++) {
            if (bottom_un[i] < 0.5f) {
                res_un[i] = 2.0f * top_un[i] * bottom_un[i];
            } else {
                res_un[i] = 1.0f - 2.0f * (1.0f - top_un[i]) * (1.0f - bottom_un[i]);
            }
        }
        
        float a_out = top.a + bottom.a * (1.0f - top.a);
        return float4(Repremultiply(res_un, a_out), a_out);
    }

    // Soft Light (SVG)
    // Inputs: Premultiplied
    inline float4 BlendSoftLight(float4 top, float4 bottom) {
        float3 top_un = Unpremultiply(top.rgb, top.a);
        float3 bottom_un = Unpremultiply(bottom.rgb, bottom.a);
        
        // Formula from spec: (1 - 2*bottom) * top^2 + 2 * bottom * top
        float3 res_un = (1.0f - 2.0f * bottom_un) * top_un * top_un + 2.0f * bottom_un * top_un;
        
        float a_out = top.a + bottom.a * (1.0f - top.a);
        return float4(Repremultiply(res_un, a_out), a_out);
    }

    // Hard Light
    // Inputs: Premultiplied
    inline float4 BlendHardLight(float4 top, float4 bottom) {
        // Hard Light is Overlay with inputs swapped
        return BlendOverlay(bottom, top);
    }

    // Luma Mix (Film Grain)
    inline float4 BlendLumaMixACES(float4 a, float4 b, float weight) {
        float Y_a = dot(a.rgb, ACES_LUMA);
        float Y_b = dot(b.rgb, ACES_LUMA);
        float Y_mix = mix(Y_a, Y_b, weight);
        float3 c = b.rgb * (Y_mix / max(Y_b, 1e-4f));
        return float4(c, b.a); // Usually preserves base alpha
    }

    // Unified Entry Point
    inline float4 CompositeLayer(float4 layerColor, float4 belowColor, int mode) {
        switch (mode) {
            case BLEND_OVER: return BlendOver(layerColor, belowColor);
            case BLEND_ADD: return BlendAdd(layerColor, belowColor);
            case BLEND_MULTIPLY: return BlendMultiply(layerColor, belowColor);
            case BLEND_SCREEN: return BlendScreen(layerColor, belowColor);
            case BLEND_OVERLAY: return BlendOverlay(layerColor, belowColor);
            case BLEND_SOFT_LIGHT: return BlendSoftLight(layerColor, belowColor);
            case BLEND_HARD_LIGHT: return BlendHardLight(layerColor, belowColor);
            case BLEND_LINEAR_DODGE: return BlendLinearDodge(layerColor, belowColor);
            default: return BlendOver(layerColor, belowColor);
        }
    }

} // namespace Blending

// MARK: - Kernels

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Passthrough (used for additive composite)
fragment float4 fragment_add(
    VertexOut in [[stage_in]],
    texture2d<float> inputTexture [[texture(0)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    return inputTexture.sample(s, in.uv);
}

// Alpha-Over composite: Composites foreground over the background using premultiplied alpha.
// Input texture(0) = foreground (pre-multiplied RGBA)
// Framebuffer = background (via blend state or read attachment)
// Note: This is a simple passthrough; actual blending is configured via MTLRenderPipelineState
// blend descriptors. For true over blending without blend state, use fragment_over_blend.
fragment float4 fragment_over(
    VertexOut in [[stage_in]],
    texture2d<float> foregroundTexture [[texture(0)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 fg = foregroundTexture.sample(s, in.uv);
    // Return premultiplied foreground. The blend state will handle:
    // C_out = C_fg + C_bg * (1 - α_fg)
    return fg;
}

// Two-texture alpha-over composite (when reading both textures explicitly)
fragment float4 fragment_over_blend(
    VertexOut in [[stage_in]],
    texture2d<float> foregroundTexture [[texture(0)]],
    texture2d<float> backgroundTexture [[texture(1)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 fg = foregroundTexture.sample(s, in.uv);
    float4 bg = backgroundTexture.sample(s, in.uv);
    
    // Pre-multiplied alpha compositing: C_out = C_fg + C_bg * (1 - α_fg)
    float3 composited = fg.rgb + bg.rgb * (1.0 - fg.a);
    return float4(composited, 1.0);
}

kernel void blend_normal(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::read_write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    float4 s = source.read(gid);
    float4 d = dest.read(gid);
    
    float4 result = Blending::BlendOver(s, d);
    
    dest.write(result, gid);
}

kernel void blend_screen(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::read_write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    float4 s = source.read(gid);
    float4 d = dest.read(gid);
    
    float4 result = Blending::BlendScreen(s, d);
    
    dest.write(result, gid);
}

#endif // BLENDING_METAL
