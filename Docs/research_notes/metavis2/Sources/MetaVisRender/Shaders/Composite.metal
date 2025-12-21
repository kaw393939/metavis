#include <metal_stdlib>
using namespace metal;

// MARK: - Composite Uniforms

/// Parameters for video compositing operations.
struct CompositeUniforms {
    /// Blend mode:
    /// 0 = normal (standard alpha over)
    /// 1 = behindMask (graphics behind subject using mask)
    /// 2 = multiply
    /// 3 = screen
    /// 4 = overlay
    uint blendMode;
    
    /// Threshold for mask-based compositing (0.0-1.0)
    float maskThreshold;
    
    /// Edge softness for mask blending (0.0-0.5)
    float edgeSoftness;
    
    /// Foreground opacity multiplier (0.0-1.0)
    float foregroundOpacity;
    
    /// Background opacity multiplier (0.0-1.0)
    float backgroundOpacity;
    
    /// Padding for alignment
    float3 padding;
};

// MARK: - Helper Functions

/// Linear interpolation
inline float3 lerp3(float3 a, float3 b, float t) {
    return a + (b - a) * t;
}

/// Smooth step for soft edges
inline float softMask(float maskValue, float threshold, float softness) {
    return smoothstep(threshold - softness, threshold + softness, maskValue);
}

/// Standard Porter-Duff "over" compositing: fg over bg
inline float4 alphaOver(float4 fg, float4 bg) {
    float outAlpha = fg.a + bg.a * (1.0 - fg.a);
    
    if (outAlpha > 0.0) {
        float3 outColor = (fg.rgb * fg.a + bg.rgb * bg.a * (1.0 - fg.a)) / outAlpha;
        return float4(outColor, outAlpha);
    }
    
    return float4(0.0);
}

/// Multiply blend: darkens
inline float3 blendMultiply(float3 base, float3 blend) {
    return base * blend;
}

/// Screen blend: lightens
inline float3 blendScreen(float3 base, float3 blend) {
    return 1.0 - (1.0 - base) * (1.0 - blend);
}

/// Overlay blend: combines multiply and screen
inline float3 blendOverlay(float3 base, float3 blend) {
    float3 result;
    result.r = base.r < 0.5 ? 2.0 * base.r * blend.r : 1.0 - 2.0 * (1.0 - base.r) * (1.0 - blend.r);
    result.g = base.g < 0.5 ? 2.0 * base.g * blend.g : 1.0 - 2.0 * (1.0 - base.g) * (1.0 - blend.g);
    result.b = base.b < 0.5 ? 2.0 * base.b * blend.b : 1.0 - 2.0 * (1.0 - base.b) * (1.0 - blend.b);
    return result;
}

/// Darken blend
inline float3 blendDarken(float3 base, float3 blend) {
    return min(base, blend);
}

/// Lighten blend
inline float3 blendLighten(float3 base, float3 blend) {
    return max(base, blend);
}

/// Color Burn blend
inline float3 blendColorBurn(float3 base, float3 blend) {
    return 1.0 - (1.0 - base) / (blend + 0.00001);
}

/// Color Dodge blend
inline float3 blendColorDodge(float3 base, float3 blend) {
    return base / (1.0 - blend + 0.00001);
}

/// Soft Light blend
inline float3 blendSoftLight(float3 base, float3 blend) {
    float3 result;
    // W3C SVG Filter Effects spec formula
    float3 D;
    D.r = (base.r <= 0.25) ? ((16.0 * base.r - 12.0) * base.r + 4.0) * base.r : sqrt(base.r);
    D.g = (base.g <= 0.25) ? ((16.0 * base.g - 12.0) * base.g + 4.0) * base.g : sqrt(base.g);
    D.b = (base.b <= 0.25) ? ((16.0 * base.b - 12.0) * base.b + 4.0) * base.b : sqrt(base.b);
    
    result.r = (blend.r <= 0.5) ? base.r - (1.0 - 2.0 * blend.r) * base.r * (1.0 - base.r) : base.r + (2.0 * blend.r - 1.0) * (D.r - base.r);
    result.g = (blend.g <= 0.5) ? base.g - (1.0 - 2.0 * blend.g) * base.g * (1.0 - base.g) : base.g + (2.0 * blend.g - 1.0) * (D.g - base.g);
    result.b = (blend.b <= 0.5) ? base.b - (1.0 - 2.0 * blend.b) * base.b * (1.0 - base.b) : base.b + (2.0 * blend.b - 1.0) * (D.b - base.b);
    return result;
}

/// Hard Light blend
inline float3 blendHardLight(float3 base, float3 blend) {
    return blendOverlay(blend, base);
}

/// Difference blend
inline float3 blendDifference(float3 base, float3 blend) {
    return abs(base - blend);
}

/// Exclusion blend
inline float3 blendExclusion(float3 base, float3 blend) {
    return base + blend - 2.0 * base * blend;
}

/// Add blend
inline float3 blendAdd(float3 base, float3 blend) {
    return min(base + blend, 1.0);
}

// MARK: - HSL Helper Functions

inline float getLuminance(float3 c) {
    return dot(c, float3(0.3, 0.59, 0.11));
}

inline float3 clipColor(float3 c) {
    float l = getLuminance(c);
    float n = min(min(c.r, c.g), c.b);
    float x = max(max(c.r, c.g), c.b);
    
    if (n < 0.0) c = l + (((c - l) * l) / (l - n));
    if (x > 1.0) c = l + (((c - l) * (1.0 - l)) / (x - l));
    
    return c;
}

inline float3 setLum(float3 c, float l) {
    float d = l - getLuminance(c);
    return clipColor(c + d);
}

inline float sat(float3 c) {
    return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
}

inline float3 setSat(float3 c, float s) {
    float minVal = min(min(c.r, c.g), c.b);
    float maxVal = max(max(c.r, c.g), c.b);
    float midVal = c.r + c.g + c.b - minVal - maxVal;
    
    if (maxVal > minVal) {
        float newMid = ((midVal - minVal) * s) / (maxVal - minVal);
        float newMax = s;
        float newMin = 0.0;
        
        if (c.r == minVal) c.r = newMin;
        else if (c.r == maxVal) c.r = newMax;
        else c.r = newMid;
        
        if (c.g == minVal) c.g = newMin;
        else if (c.g == maxVal) c.g = newMax;
        else c.g = newMid;
        
        if (c.b == minVal) c.b = newMin;
        else if (c.b == maxVal) c.b = newMax;
        else c.b = newMid;
    } else {
        c = float3(0.0);
    }
    return c;
}

/// Hue blend
inline float3 blendHue(float3 base, float3 blend) {
    return setLum(setSat(blend, sat(base)), getLuminance(base));
}

/// Saturation blend
inline float3 blendSaturation(float3 base, float3 blend) {
    return setLum(setSat(base, sat(blend)), getLuminance(base));
}

/// Color blend
inline float3 blendColor(float3 base, float3 blend) {
    return setLum(blend, getLuminance(base));
}

/// Luminosity blend
inline float3 blendLuminosity(float3 base, float3 blend) {
    return setLum(base, getLuminance(blend));
}

// MARK: - Main Composite Kernel

/// Composites foreground (graphics) over background (video) with optional mask.
///
/// When a mask is provided, the foreground can be placed "behind" the subject
/// (areas where mask > threshold show video, areas where mask < threshold blend graphics).
///
/// Textures:
///   0: background (video frame) - BGRA8
///   1: foreground (rendered graphics) - BGRA8
///   2: mask (person/subject mask, optional) - R8 or BGRA8
///   3: output - BGRA8
kernel void composite(
    texture2d<float, access::read> background [[texture(0)]],
    texture2d<float, access::read> foreground [[texture(1)]],
    texture2d<float, access::read> mask [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    constant CompositeUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Sample textures
    float4 bg = background.read(gid);
    float4 fg = foreground.read(gid);
    
    // Apply opacity modifiers
    bg.a *= uniforms.backgroundOpacity;
    fg.a *= uniforms.foregroundOpacity;
    
    float4 result;
    
    // Mode 0: Normal alpha blending
    if (uniforms.blendMode == 0) {
        result = alphaOver(fg, bg);
    }
    
    // Mode 1: Behind mask (graphics behind subject)
    else if (uniforms.blendMode == 1) {
        // Sample mask (using red channel)
        float maskValue = mask.read(gid).r;
        
        // Calculate subject presence with soft edges
        float subjectPresence = softMask(maskValue, uniforms.maskThreshold, uniforms.edgeSoftness);
        
        // Where subject is present (mask > threshold): show video
        // Where no subject (mask < threshold): blend graphics over video
        float fgVisibility = (1.0 - subjectPresence) * fg.a;
        
        result.rgb = fg.rgb * fgVisibility + bg.rgb * (1.0 - fgVisibility);
        result.a = fgVisibility + bg.a * (1.0 - fgVisibility);
    }
    
    // Mode 2: Multiply blend
    else if (uniforms.blendMode == 2) {
        float3 blended = blendMultiply(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 3: Screen blend
    else if (uniforms.blendMode == 3) {
        float3 blended = blendScreen(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 4: Overlay blend
    else if (uniforms.blendMode == 4) {
        float3 blended = blendOverlay(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 5: Darken
    else if (uniforms.blendMode == 5) {
        float3 blended = blendDarken(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 6: Lighten
    else if (uniforms.blendMode == 6) {
        float3 blended = blendLighten(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 7: Color Burn
    else if (uniforms.blendMode == 7) {
        float3 blended = blendColorBurn(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 8: Color Dodge
    else if (uniforms.blendMode == 8) {
        float3 blended = blendColorDodge(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 9: Soft Light
    else if (uniforms.blendMode == 9) {
        float3 blended = blendSoftLight(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 10: Hard Light
    else if (uniforms.blendMode == 10) {
        float3 blended = blendHardLight(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 11: Difference
    else if (uniforms.blendMode == 11) {
        float3 blended = blendDifference(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 12: Exclusion
    else if (uniforms.blendMode == 12) {
        float3 blended = blendExclusion(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 13: Hue
    else if (uniforms.blendMode == 13) {
        float3 blended = blendHue(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 14: Saturation
    else if (uniforms.blendMode == 14) {
        float3 blended = blendSaturation(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 15: Color
    else if (uniforms.blendMode == 15) {
        float3 blended = blendColor(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 16: Luminosity
    else if (uniforms.blendMode == 16) {
        float3 blended = blendLuminosity(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    // Mode 17: Add
    else if (uniforms.blendMode == 17) {
        float3 blended = blendAdd(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    }
    
    else {
        // Fallback to normal
        result = alphaOver(fg, bg);
    }
    
    output.write(result, gid);
}

// MARK: - Composite Without Mask

/// Simplified compositing without mask (always foreground over background).
kernel void compositeSimple(
    texture2d<float, access::read> background [[texture(0)]],
    texture2d<float, access::read> foreground [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant CompositeUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float4 bg = background.read(gid);
    float4 fg = foreground.read(gid);
    
    fg.a *= uniforms.foregroundOpacity;
    bg.a *= uniforms.backgroundOpacity;
    
    float4 result;
    
    if (uniforms.blendMode == 0) {
        result = alphaOver(fg, bg);
    } else if (uniforms.blendMode == 2) {
        float3 blended = blendMultiply(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    } else if (uniforms.blendMode == 3) {
        float3 blended = blendScreen(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    } else if (uniforms.blendMode == 4) {
        float3 blended = blendOverlay(bg.rgb, fg.rgb);
        result.rgb = mix(bg.rgb, blended, fg.a);
        result.a = bg.a;
    } else {
        result = alphaOver(fg, bg);
    }
    
    output.write(result, gid);
}

// MARK: - Copy Video Frame

/// Simple copy from video to output (for frames without graphics).
kernel void copyFrame(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float4 color = input.read(gid);
    output.write(color, gid);
}

// MARK: - Resize/Scale Kernel

/// Bilinear resize for matching texture sizes.
kernel void resizeTexture(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    sampler textureSampler [[sampler(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    // Calculate normalized coordinates
    float2 uv = float2(gid) / float2(output.get_width(), output.get_height());
    
    // Sample with bilinear filtering
    float4 color = input.sample(textureSampler, uv);
    
    output.write(color, gid);
}

// MARK: - Premultiply Alpha

/// Premultiplies RGB by alpha for correct blending.
kernel void premultiplyAlpha(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float4 color = input.read(gid);
    color.rgb *= color.a;
    output.write(color, gid);
}

/// Unpremultiplies alpha from RGB.
kernel void unpremultiplyAlpha(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float4 color = input.read(gid);
    
    if (color.a > 0.0) {
        color.rgb /= color.a;
    }
    
    output.write(color, gid);
}

// MARK: - Transform

struct TransformUniforms {
    float3x3 transformMatrix;
};

kernel void transform(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant TransformUniforms &uniforms [[buffer(0)]],
    sampler s [[sampler(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float width = float(output.get_width());
    float height = float(output.get_height());
    
    // Normalized coordinates (0..1)
    float2 uv = float2(gid) / float2(width, height);
    
    // Convert to centered coordinates (-0.5..0.5)
    float3 pos = float3(uv.x - 0.5, uv.y - 0.5, 1.0);
    
    // Apply inverse transform
    float3 srcPos = uniforms.transformMatrix * pos;
    
    // Convert back to UV (0..1)
    float2 srcUV = float2(srcPos.x + 0.5, srcPos.y + 0.5);
    
    // Sample with bounds check for transparency
    float4 color = float4(0.0);
    if (srcUV.x >= 0.0 && srcUV.x <= 1.0 && srcUV.y >= 0.0 && srcUV.y <= 1.0) {
        color = input.sample(s, srcUV);
    }
    
    output.write(color, gid);
}
