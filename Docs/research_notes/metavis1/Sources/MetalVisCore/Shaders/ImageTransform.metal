#include <metal_stdlib>
#include "ColorSpace.metal"
using namespace metal;

// Helper for NaN detection
bool hasNaN(float3 color) {
    return isnan(color.r) || isnan(color.g) || isnan(color.b) || isinf(color.r) || isinf(color.g) || isinf(color.b);
}

float3 safeColor(float3 color) {
    if (hasNaN(color)) {
        return float3(1.0, 0.0, 0.0); // RED for NaN
    }
    return color;
}

/// Transform parameters for image animation
struct TransformParams {
    float2 translation;      // 0
    float2 scale;            // 8
    float2 anchor;           // 16
    float2 shadowOffset;     // 24
    
    float4 borderColor;      // 32
    float4 shadowColor;      // 48
    
    float rotation;          // 64
    float opacity;           // 68
    float borderWidth;       // 72
    float shadowRadius;      // 76
    float shadowOpacity;     // 80
    
    float time;              // 84
    float shimmerSpeed;      // 88
    float shimmerIntensity;  // 92
    float shimmerWidth;      // 96
    
    uint inputColorSpace;    // 100
    uint inputTransferFunction; // 104
    float hdrScalingFactor;  // 108
    float padding;           // 112 -> 116 bytes
};

/// Sample texture with trilinear filtering for Ken Burns quality (MBE Chapter 7)
/// Trilinear = linear between texels + linear between mip levels (MBE page 64)
float4 sampleTexture(texture2d<float, access::sample> texture, float2 uv) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        mip_filter::linear,     // Enable trilinear filtering for smooth zoom
        address::clamp_to_edge
    );
    return texture.sample(textureSampler, uv);
}

/// SDF for a rectangle of size 1x1 centered at 0.5, 0.5
float sdBox(float2 p, float2 b) {
    float2 d = abs(p - 0.5) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

/// Apply 2D affine transformation to image
kernel void transform_image(
    texture2d<float, access::sample> sourceTexture [[texture(0)]], // Changed to sample for filtering
    texture2d<float, access::write> destinationTexture [[texture(1)]],
    constant TransformParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check bounds
    if (gid.x >= destinationTexture.get_width() || gid.y >= destinationTexture.get_height()) {
        return;
    }
    
    float2 destSize = float2(destinationTexture.get_width(), destinationTexture.get_height());
    float2 sourceSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    
    // Convert pixel position to normalized coordinates (0-1)
    float2 destUV = float2(gid) / destSize;
    
    // Apply anchor point offset (transform around anchor)
    float2 centered = destUV - params.anchor;
    
    // Apply rotation
    float cosTheta = cos(params.rotation);
    float sinTheta = sin(params.rotation);
    float2 rotated = float2(
        centered.x * cosTheta - centered.y * sinTheta,
        centered.x * sinTheta + centered.y * cosTheta
    );
    
    // Apply scale
    float2 scaled = rotated / params.scale;
    
    // Remove anchor offset
    float2 transformed = scaled + params.anchor;
    
    // Apply translation (convert from pixel space to UV space)
    transformed += params.translation / destSize;
    
    // --- Rendering ---
    
    float4 finalColor = float4(0.0);
    
    // 1. Shadow
    if (params.shadowOpacity > 0.0) {
        // Shadow is offset from the image
        // In inverse transform, we subtract the offset
        // But wait, if we move image by +10, transformed UV decreases.
        // If we want shadow at +10 relative to image, we should look at UV corresponding to -10 relative to image.
        // So shadowUV = transformed - offset / sourceSize?
        // Let's verify:
        // Pixel P is at image center. transformed = 0.5.
        // Pixel Q is at image center + offset. transformed = 0.5 - offset/destSize (due to translation).
        // We want Q to be shadow center.
        // So at Q, we want shadowUV to be 0.5.
        // shadowUV = transformed + offset/sourceSize?
        // No, let's stick to the logic:
        // The shadow is a rectangle at (0.5, 0.5) in a coordinate system shifted by shadowOffset.
        // If shadowOffset is (10, 10) pixels, the shadow rect is at (0.5, 0.5) + (10, 10)/sourceSize.
        // So we check distance of transformed to (0.5 + offset).
        
        float2 shadowCenter = float2(0.5) + params.shadowOffset / sourceSize;
        float2 d = abs(transformed - shadowCenter) - 0.5;
        float2 pixelDist = d * sourceSize;
        float distPx = length(max(pixelDist, 0.0)) + min(max(pixelDist.x, pixelDist.y), 0.0);
        
        // Soft shadow
        float shadowFactor = 1.0 - smoothstep(0.0, params.shadowRadius, distPx);
        // Inside rect, distPx <= 0, factor = 1.
        // Outside, fades out.
        
        finalColor = params.shadowColor * shadowFactor * params.shadowOpacity;
    }
    
    // 2. Image & Border
    // Distance to image rect (0,0)-(1,1)
    float2 d = abs(transformed - 0.5) - 0.5;
    float2 pixelDist = d * sourceSize;
    float distPx = length(max(pixelDist, 0.0)) + min(max(pixelDist.x, pixelDist.y), 0.0);
    
    if (distPx <= 0.0) {
        // Inside image rect
        float4 layerColor;
        
        if (distPx > -params.borderWidth) {
            // Border
            layerColor = params.borderColor;
        } else {
            // Image
            // Sample source texture
            // Note: transformed is in UV space [0,1]
            layerColor = sampleTexture(sourceTexture, transformed);
            
            // --- Color Space Conversion ---
            // Use the single source of truth
            int tf = ColorSpace::TF_LINEAR;
            if (params.inputTransferFunction == 1) tf = ColorSpace::TF_SRGB;
            else if (params.inputTransferFunction == 2) tf = ColorSpace::TF_REC709;
            else if (params.inputTransferFunction == 3) tf = ColorSpace::TF_PQ;
            else if (params.inputTransferFunction == 4) tf = ColorSpace::TF_HLG;
            else if (params.inputTransferFunction == 5) tf = ColorSpace::TF_APPLE_LOG;
            
            int prim = ColorSpace::PRIM_SRGB;
            if (params.inputColorSpace == 0) prim = ColorSpace::PRIM_SRGB;
            else if (params.inputColorSpace == 1) prim = ColorSpace::PRIM_REC709;
            else if (params.inputColorSpace == 2) prim = ColorSpace::PRIM_REC2020;
            else if (params.inputColorSpace == 3) prim = ColorSpace::PRIM_P3D65;
            
            float3 acescgColor = ColorSpace::DecodeToACEScg(layerColor.rgb, tf, prim);
            
            // Apply HDR Scaling if needed (e.g. exposure compensation for HDR inputs)
            if (params.inputTransferFunction == 3 || params.inputTransferFunction == 4) {
                 acescgColor *= params.hdrScalingFactor;
            }
            
            // NaN Check
            acescgColor = safeColor(acescgColor);
            
            layerColor.rgb = acescgColor;
            
            layerColor.a *= params.opacity;
            layerColor.rgb *= layerColor.a; // Premultiply Alpha
            
            // Apply Shimmer
            if (params.shimmerIntensity > 0.0) {
                // Calculate shimmer position based on time
                float shimmerPos = fract(params.time * params.shimmerSpeed);
                
                // Calculate distance from shimmer line (diagonal)
                // x + y = const defines a diagonal line
                // We want the line to move from -width to 1+width
                // Normalized coord sum: destUV.x + destUV.y ranges from 0 to 2
                // Let's use just x for simplicity or a slanted line
                
                // Slanted line: x - y + offset
                // Let's use a simple vertical bar moving across for now, or slanted
                float coord = destUV.x + destUV.y * 0.5; // Slanted
                float shimmerCenter = shimmerPos * 2.5 - 0.5; // Move from -0.5 to 2.0
                
                float dist = abs(coord - shimmerCenter);
                float shimmer = smoothstep(params.shimmerWidth, 0.0, dist);
                
                // Add brightness
                layerColor.rgb += shimmer * params.shimmerIntensity * layerColor.a;
            }
        }
        
        // Blend over shadow
        // Standard alpha blending: src + dst * (1 - src.a)
        finalColor = layerColor + finalColor * (1.0 - layerColor.a);
    }
    
    destinationTexture.write(finalColor, gid);
}


/// High-quality Lanczos3 resampling (for quality layer)
float lanczos3(float x) {
    if (x == 0.0) return 1.0;
    if (abs(x) >= 3.0) return 0.0;
    
    float pi_x = M_PI_F * x;
    return (3.0 * sin(pi_x) * sin(pi_x / 3.0)) / (pi_x * pi_x);
}

kernel void transform_image_lanczos3(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destinationTexture [[texture(1)]],
    constant TransformParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check bounds
    if (gid.x >= destinationTexture.get_width() || gid.y >= destinationTexture.get_height()) {
        return;
    }
    
    float2 destSize = float2(destinationTexture.get_width(), destinationTexture.get_height());
    float2 sourceSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    
    // Convert pixel position to normalized coordinates
    float2 destUV = float2(gid) / destSize;
    
    // Apply transformations (same as basic version)
    float2 centered = destUV - params.anchor;
    
    float cosTheta = cos(params.rotation);
    float sinTheta = sin(params.rotation);
    float2 rotated = float2(
        centered.x * cosTheta - centered.y * sinTheta,
        centered.x * sinTheta + centered.y * cosTheta
    );
    
    float2 scaled = rotated / params.scale;
    float2 transformed = scaled + params.anchor;
    transformed += params.translation / destSize;
    
    // --- Rendering ---
    
    float4 finalColor = float4(0.0);
    
    // 1. Shadow
    if (params.shadowOpacity > 0.0) {
        float2 shadowCenter = float2(0.5) + params.shadowOffset / sourceSize;
        float2 d = abs(transformed - shadowCenter) - 0.5;
        float2 pixelDist = d * sourceSize;
        float distPx = length(max(pixelDist, 0.0)) + min(max(pixelDist.x, pixelDist.y), 0.0);
        
        float shadowFactor = 1.0 - smoothstep(0.0, params.shadowRadius, distPx);
        finalColor = params.shadowColor * shadowFactor * params.shadowOpacity;
    }
    
    // 2. Image & Border
    float2 d = abs(transformed - 0.5) - 0.5;
    float2 pixelDist = d * sourceSize;
    float distPx = length(max(pixelDist, 0.0)) + min(max(pixelDist.x, pixelDist.y), 0.0);
    
    if (distPx <= 0.0) {
        float4 layerColor;
        
        if (distPx > -params.borderWidth) {
            // Border
            layerColor = params.borderColor;
        } else {
            // Image (Lanczos3)
            float2 sourcePos = transformed * sourceSize;
            int2 basePos = int2(floor(sourcePos));
            float2 frac = sourcePos - float2(basePos);
            
            float4 accumulator = float4(0.0);
            float weightSum = 0.0;
            
            // 6x6 Lanczos3 kernel
            for (int dy = -2; dy <= 3; dy++) {
                for (int dx = -2; dx <= 3; dx++) {
                    int2 samplePos = basePos + int2(dx, dy);
                    
                    // Clamp to texture bounds
                    samplePos = clamp(samplePos, int2(0), int2(sourceSize) - int2(1));
                    
                    float wx = lanczos3(float(dx) - frac.x);
                    float wy = lanczos3(float(dy) - frac.y);
                    float weight = wx * wy;
                    
                    float4 sample = sourceTexture.read(uint2(samplePos));
                    accumulator += sample * weight;
                    weightSum += weight;
                }
            }
            
            layerColor = accumulator / weightSum;
            
            // --- Color Space Conversion ---
            // Use the single source of truth
            int tf = ColorSpace::TF_LINEAR;
            if (params.inputTransferFunction == 1) tf = ColorSpace::TF_SRGB;
            else if (params.inputTransferFunction == 2) tf = ColorSpace::TF_REC709;
            else if (params.inputTransferFunction == 3) tf = ColorSpace::TF_PQ;
            else if (params.inputTransferFunction == 4) tf = ColorSpace::TF_HLG;
            else if (params.inputTransferFunction == 5) tf = ColorSpace::TF_APPLE_LOG;
            
            int prim = ColorSpace::PRIM_SRGB;
            if (params.inputColorSpace == 0) prim = ColorSpace::PRIM_SRGB;
            else if (params.inputColorSpace == 1) prim = ColorSpace::PRIM_REC709;
            else if (params.inputColorSpace == 2) prim = ColorSpace::PRIM_REC2020;
            else if (params.inputColorSpace == 3) prim = ColorSpace::PRIM_P3D65;
            
            float3 acescgColor = ColorSpace::DecodeToACEScg(layerColor.rgb, tf, prim);
            
            // Apply HDR Scaling if needed (e.g. exposure compensation for HDR inputs)
            if (params.inputTransferFunction == 3 || params.inputTransferFunction == 4) {
                 acescgColor *= params.hdrScalingFactor;
            }
            
            // NaN Check
            acescgColor = safeColor(acescgColor);
            
            layerColor.rgb = acescgColor;
            
            layerColor.a *= params.opacity;
            layerColor.rgb *= layerColor.a; // Premultiply Alpha
            
            // Apply Shimmer
            if (params.shimmerIntensity > 0.0) {
                float shimmerPos = fract(params.time * params.shimmerSpeed);
                float coord = destUV.x + destUV.y * 0.5;
                float shimmerCenter = shimmerPos * 2.5 - 0.5;
                
                float dist = abs(coord - shimmerCenter);
                float shimmer = smoothstep(params.shimmerWidth, 0.0, dist);
                
                layerColor.rgb += shimmer * params.shimmerIntensity * layerColor.a;
            }
        }
        
        // Blend over shadow
        finalColor = layerColor + finalColor * (1.0 - layerColor.a);
    }
    
    destinationTexture.write(finalColor, gid);
}

/// Motion blur accumulation (for quality layer)
kernel void accumulate_motion_blur(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture2d<float, access::read> accumulatorTexture [[texture(1)]],
    texture2d<float, access::write> destinationTexture [[texture(2)]],
    constant float& weight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destinationTexture.get_width() || gid.y >= destinationTexture.get_height()) {
        return;
    }
    
    float4 source = sourceTexture.read(gid);
    float4 accumulator = accumulatorTexture.read(gid);
    
    // Weighted accumulation for motion blur
    float4 result = accumulator + source * weight;
    
    destinationTexture.write(result, gid);
}

// Convert Linear Float16 to sRGB 8-bit (or just sRGB encoded float)
kernel void linear_to_srgb(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    float4 color = inputTexture.read(gid);
    
    // Convert Linear -> sRGB
    // We can use ColorSpace::LinearToSRGB from ColorSpace.metal
    color.rgb = ColorSpace::LinearToSRGB(color.rgb);
    
    outputTexture.write(color, gid);
}
