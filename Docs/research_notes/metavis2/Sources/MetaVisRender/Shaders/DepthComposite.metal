#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

struct DepthCompositeUniforms {
    float depthThreshold;
    float edgeSoftness;
    float textDepth;
    uint mode;
    float3 padding;
};

// MARK: - Main Composite Kernel

/// Depth-aware compositing kernel
/// Modes:
///   0 = behindSubject: Text appears behind foreground objects
///   1 = inFrontOfAll: Text always on top
///   2 = depthSorted: Full depth comparison
///   3 = parallax: Depth-based parallax shift
kernel void depthComposite(
    texture2d<float, access::read> video [[texture(0)]],
    texture2d<float, access::read> text [[texture(1)]],
    texture2d<float, access::read> depth [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    constant DepthCompositeUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= video.get_width() || gid.y >= video.get_height()) {
        return;
    }
    
    // Sample inputs
    float4 videoColor = video.read(gid);
    float4 textColor = text.read(gid);
    float sceneDepth = depth.read(gid).r;
    
    float4 result;
    
    // Mode 0: Behind Subject
    // Text is visible where scene depth > text depth (background)
    // Text is hidden where scene depth < text depth (foreground occludes)
    if (uniforms.mode == 0) {
        // Calculate depth difference
        float depthDiff = uniforms.textDepth - sceneDepth;
        
        // Smooth occlusion factor
        // When depthDiff > 0: scene is in front, hide text
        // When depthDiff < 0: scene is behind, show text
        float occlusionFactor = smoothstep(
            -uniforms.edgeSoftness,
            uniforms.edgeSoftness,
            depthDiff
        );
        
        // Text visibility (1 = fully visible, 0 = fully occluded)
        float textVisibility = (1.0 - occlusionFactor) * textColor.a;
        
        // Standard over compositing with depth-modulated alpha
        // result = text * textVisibility + video * (1 - textVisibility)
        result.rgb = textColor.rgb * textVisibility + videoColor.rgb * (1.0 - textVisibility);
        result.a = textVisibility + videoColor.a * (1.0 - textVisibility);
    }
    
    // Mode 1: In Front of All
    // Standard alpha blending, text always on top
    else if (uniforms.mode == 1) {
        result.rgb = textColor.rgb * textColor.a + videoColor.rgb * (1.0 - textColor.a);
        result.a = textColor.a + videoColor.a * (1.0 - textColor.a);
    }
    
    // Mode 2: Depth Sorted
    // Binary depth test
    else if (uniforms.mode == 2) {
        if (sceneDepth < uniforms.textDepth - uniforms.edgeSoftness) {
            // Scene is in front, use video
            result = videoColor;
        } else if (sceneDepth > uniforms.textDepth + uniforms.edgeSoftness) {
            // Scene is behind, blend text over video
            result.rgb = textColor.rgb * textColor.a + videoColor.rgb * (1.0 - textColor.a);
            result.a = textColor.a + videoColor.a * (1.0 - textColor.a);
        } else {
            // Transition zone - smooth blend
            float t = (sceneDepth - (uniforms.textDepth - uniforms.edgeSoftness)) / (2.0 * uniforms.edgeSoftness);
            float textVis = t * textColor.a;
            result.rgb = textColor.rgb * textVis + videoColor.rgb * (1.0 - textVis);
            result.a = textVis + videoColor.a * (1.0 - textVis);
        }
    }
    
    // Mode 3: Parallax
    // Shift text based on depth for 3D parallax effect
    else {
        // Calculate parallax shift based on depth
        float parallaxStrength = 0.02; // 2% of width maximum shift
        float depthOffset = (sceneDepth - 0.5) * 2.0; // -1 to 1
        
        float2 shift = float2(depthOffset * parallaxStrength * float(video.get_width()), 0);
        
        // Sample text at shifted position
        int2 shiftedCoord = int2(
            clamp(float(gid.x) + shift.x, 0.0, float(video.get_width() - 1)),
            int(gid.y)
        );
        float4 shiftedText = text.read(uint2(shiftedCoord));
        
        // Blend
        result.rgb = shiftedText.rgb * shiftedText.a + videoColor.rgb * (1.0 - shiftedText.a);
        result.a = shiftedText.a + videoColor.a * (1.0 - shiftedText.a);
    }
    
    output.write(result, gid);
}

// MARK: - Mask-Based Composite

/// Composite using segmentation mask instead of depth
kernel void maskComposite(
    texture2d<float, access::read> video [[texture(0)]],
    texture2d<float, access::read> text [[texture(1)]],
    texture2d<float, access::read> mask [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    constant DepthCompositeUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= video.get_width() || gid.y >= video.get_height()) {
        return;
    }
    
    float4 videoColor = video.read(gid);
    float4 textColor = text.read(gid);
    float maskValue = mask.read(gid).r;
    
    // Where mask > threshold, subject is present (occlude text)
    // Where mask < threshold, background (show text)
    float subjectPresence = smoothstep(
        uniforms.depthThreshold - uniforms.edgeSoftness,
        uniforms.depthThreshold + uniforms.edgeSoftness,
        maskValue
    );
    
    // Text visibility is inverse of subject presence
    float textVisibility = (1.0 - subjectPresence) * textColor.a;
    
    float4 result;
    result.rgb = textColor.rgb * textVisibility + videoColor.rgb * (1.0 - textVisibility);
    result.a = textVisibility + videoColor.a * (1.0 - textVisibility);
    
    output.write(result, gid);
}

// MARK: - Simple Alpha Blend (Fallback)

kernel void alphaBlend(
    texture2d<float, access::read> background [[texture(0)]],
    texture2d<float, access::read> foreground [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= background.get_width() || gid.y >= background.get_height()) {
        return;
    }
    
    float4 bg = background.read(gid);
    float4 fg = foreground.read(gid);
    
    // Standard Porter-Duff "over" operation
    float4 result;
    result.a = fg.a + bg.a * (1.0 - fg.a);
    
    if (result.a > 0.0) {
        result.rgb = (fg.rgb * fg.a + bg.rgb * bg.a * (1.0 - fg.a)) / result.a;
    } else {
        result.rgb = float3(0.0);
    }
    
    output.write(result, gid);
}
