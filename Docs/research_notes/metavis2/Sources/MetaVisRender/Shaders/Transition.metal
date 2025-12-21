// Transition.metal
// MetaVisRender
//
// Created for Sprint 11: Timeline Editing
// GPU shaders for video transitions between clips

#include <metal_stdlib>
using namespace metal;

// MARK: - Transition Uniforms

/// Uniforms passed to all transition shaders
struct TransitionUniforms {
    float progress;     // 0.0 (from) to 1.0 (to)
    float softness;     // Edge softness (0.0 = hard, 0.1 = soft)
    float holdRatio;    // For dip transitions: ratio of hold time
    int direction;      // 0=left, 1=right, 2=up, 3=down
    float feather;      // Edge feather for iris
};

// MARK: - Helper Functions

/// Applies smooth step easing (Hermite interpolation)
inline float smoothStepEase(float t) {
    return t * t * (3.0 - 2.0 * t);
}

/// Applies Ken Perlin's smoother step
inline float smootherStepEase(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

/// Linear interpolation between two colors
inline float4 lerp4(float4 a, float4 b, float t) {
    return a + (b - a) * t;
}

// MARK: - Crossfade Transition

/// Simple cross dissolve between two clips
kernel void crossfadeTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    
    // Apply smooth step for more pleasing visual blend
    float t = smoothStepEase(uniforms.progress);
    
    float4 result = mix(fromColor, toColor, t);
    outTex.write(result, gid);
}

// MARK: - Dip to Black Transition

/// Fade out to black, hold, then fade in
kernel void dipToBlackTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float progress = uniforms.progress;
    float holdRatio = uniforms.holdRatio;
    
    // Calculate phase boundaries
    float fadeOutEnd = (1.0 - holdRatio) / 2.0;
    float fadeInStart = 1.0 - fadeOutEnd;
    
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    float4 black = float4(0.0, 0.0, 0.0, 1.0);
    
    float4 result;
    
    if (progress < fadeOutEnd) {
        // Phase 1: Fade from → black
        float t = progress / fadeOutEnd;
        t = smoothStepEase(t);
        result = mix(fromColor, black, t);
    } else if (progress > fadeInStart) {
        // Phase 3: Fade black → to
        float t = (progress - fadeInStart) / (1.0 - fadeInStart);
        t = smoothStepEase(t);
        result = mix(black, toColor, t);
    } else {
        // Phase 2: Hold black
        result = black;
    }
    
    outTex.write(result, gid);
}

// MARK: - Dip to White Transition

/// Fade out to white, hold, then fade in
kernel void dipToWhiteTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float progress = uniforms.progress;
    float holdRatio = uniforms.holdRatio;
    
    float fadeOutEnd = (1.0 - holdRatio) / 2.0;
    float fadeInStart = 1.0 - fadeOutEnd;
    
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    float4 white = float4(1.0, 1.0, 1.0, 1.0);
    
    float4 result;
    
    if (progress < fadeOutEnd) {
        float t = smoothStepEase(progress / fadeOutEnd);
        result = mix(fromColor, white, t);
    } else if (progress > fadeInStart) {
        float t = smoothStepEase((progress - fadeInStart) / (1.0 - fadeInStart));
        result = mix(white, toColor, t);
    } else {
        result = white;
    }
    
    outTex.write(result, gid);
}

// MARK: - Wipe Transition

/// Directional wipe between clips
kernel void wipeTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float2 uv = float2(gid) / float2(outTex.get_width(), outTex.get_height());
    float progress = uniforms.progress;
    float softness = max(uniforms.softness, 0.001);  // Prevent division by zero
    
    // Calculate edge position based on direction
    float edge;
    switch (uniforms.direction) {
        case 0:  // Left to right
            edge = uv.x;
            break;
        case 1:  // Right to left
            edge = 1.0 - uv.x;
            break;
        case 2:  // Bottom to top
            edge = 1.0 - uv.y;
            break;
        case 3:  // Top to bottom
            edge = uv.y;
            break;
        default:
            edge = uv.x;
            break;
    }
    
    // Calculate blend factor with soft edge
    float t = smoothstep(progress - softness, progress + softness, edge);
    
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    
    // t = 0 means fully in "to" region, t = 1 means fully in "from" region
    float4 result = mix(toColor, fromColor, t);
    outTex.write(result, gid);
}

// MARK: - Push Transition

/// Push the from clip off screen while sliding in the to clip
kernel void pushTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float progress = smoothStepEase(uniforms.progress);
    float2 size = float2(outTex.get_width(), outTex.get_height());
    float2 uv = float2(gid) / size;
    
    float2 fromOffset, toOffset;
    
    switch (uniforms.direction) {
        case 0:  // Left (push from right)
            fromOffset = float2(-progress, 0.0);
            toOffset = float2(1.0 - progress, 0.0);
            break;
        case 1:  // Right (push from left)
            fromOffset = float2(progress, 0.0);
            toOffset = float2(-1.0 + progress, 0.0);
            break;
        case 2:  // Up (push from bottom)
            fromOffset = float2(0.0, -progress);
            toOffset = float2(0.0, 1.0 - progress);
            break;
        case 3:  // Down (push from top)
            fromOffset = float2(0.0, progress);
            toOffset = float2(0.0, -1.0 + progress);
            break;
        default:
            fromOffset = float2(0.0);
            toOffset = float2(0.0);
    }
    
    float2 fromUV = uv - fromOffset;
    float2 toUV = uv - toOffset;
    
    float4 result = float4(0.0, 0.0, 0.0, 1.0);
    
    // Sample from "from" texture if in bounds
    if (fromUV.x >= 0.0 && fromUV.x <= 1.0 && fromUV.y >= 0.0 && fromUV.y <= 1.0) {
        uint2 fromGid = uint2(fromUV * size);
        result = fromTex.read(fromGid);
    }
    
    // Sample from "to" texture if in bounds (overwrites if both visible)
    if (toUV.x >= 0.0 && toUV.x <= 1.0 && toUV.y >= 0.0 && toUV.y <= 1.0) {
        uint2 toGid = uint2(toUV * size);
        result = toTex.read(toGid);
    }
    
    outTex.write(result, gid);
}

// MARK: - Slide Transition

/// Slide the to clip over the from clip (from stays stationary)
kernel void slideTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float progress = smoothStepEase(uniforms.progress);
    float2 size = float2(outTex.get_width(), outTex.get_height());
    float2 uv = float2(gid) / size;
    
    float2 toOffset;
    
    switch (uniforms.direction) {
        case 0:  // Slide from right
            toOffset = float2(1.0 - progress, 0.0);
            break;
        case 1:  // Slide from left
            toOffset = float2(-1.0 + progress, 0.0);
            break;
        case 2:  // Slide from bottom
            toOffset = float2(0.0, 1.0 - progress);
            break;
        case 3:  // Slide from top
            toOffset = float2(0.0, -1.0 + progress);
            break;
        default:
            toOffset = float2(0.0);
    }
    
    float2 toUV = uv - toOffset;
    
    // Start with from texture
    float4 result = fromTex.read(gid);
    
    // Overlay to texture where visible
    if (toUV.x >= 0.0 && toUV.x <= 1.0 && toUV.y >= 0.0 && toUV.y <= 1.0) {
        uint2 toGid = uint2(toUV * size);
        result = toTex.read(toGid);
    }
    
    outTex.write(result, gid);
}

// MARK: - Iris Transition

/// Circular iris wipe (opening or closing)
kernel void irisTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float2 size = float2(outTex.get_width(), outTex.get_height());
    float2 uv = float2(gid) / size;
    float2 center = float2(0.5, 0.5);
    
    // Distance from center (normalized to 0-1 range where 1 = corner)
    float dist = length((uv - center) * float2(size.x / size.y, 1.0)) / 0.707;
    
    // Progress determines the iris radius (0 = closed, 1 = fully open)
    float radius = uniforms.progress * 1.5;  // Overshoot to ensure full coverage
    float feather = uniforms.feather;
    
    // Calculate blend factor
    float t = smoothstep(radius - feather, radius + feather, dist);
    
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    
    // Inside iris = to, outside = from
    float4 result = mix(toColor, fromColor, t);
    outTex.write(result, gid);
}

// MARK: - Custom Transition (Placeholder)

/// Placeholder for custom user-defined transitions
kernel void customTransition(
    texture2d<float, access::read> fromTex [[texture(0)]],
    texture2d<float, access::read> toTex [[texture(1)]],
    texture2d<float, access::write> outTex [[texture(2)]],
    constant TransitionUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Default to crossfade behavior
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }
    
    float4 fromColor = fromTex.read(gid);
    float4 toColor = toTex.read(gid);
    
    float4 result = mix(fromColor, toColor, uniforms.progress);
    outTex.write(result, gid);
}
