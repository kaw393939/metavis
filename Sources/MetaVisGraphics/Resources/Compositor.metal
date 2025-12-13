#include <metal_stdlib>
using namespace metal;

// MARK: - Alpha Compositor
// Composites two layers using alpha blending (standard "over" operator)

kernel void compositor_alpha_blend(
    texture2d<float, access::read> layer1 [[texture(0)]],
    texture2d<float, access::read> layer2 [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float& alpha1 [[buffer(0)]],
    constant float& alpha2 [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    float4 color1 = layer1.read(gid);
    float4 color2 = layer2.read(gid);
    
    // Apply clip alpha (for transitions)
    color1.a *= alpha1;
    color2.a *= alpha2;
    
    // Standard "over" operator (un-premultiplied)
    // result = foreground + background * (1 - foreground.alpha)
    // Layer 1 is foreground, layer 2 is background
    float4 result;
    result.rgb = color1.rgb * color1.a + color2.rgb * color2.a * (1.0 - color1.a);
    result.a = color1.a + color2.a * (1.0 - color1.a);
    
    output.write(result, gid);
}

// MARK: - N-Layer Compositor
// Composites multiple layers in order (layer 0 = bottom, layer N = top)

kernel void compositor_multi_layer(
    texture2d_array<float, access::read> layers [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float* alphas [[buffer(0)]],
    constant uint& layerCount [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    // Start with transparent black
    float4 result = float4(0.0);
    
    // Composite layers bottom-to-top
    for (uint i = 0; i < layerCount; i++) {
        float4 layer = layers.read(gid, i);
        float alpha = alphas[i];
        layer.a *= alpha;
        
        // Standard over operator
        result.rgb = result.rgb * (1.0 - layer.a) + layer.rgb * layer.a;
        result.a = result.a * (1.0 - layer.a) + layer.a;
    }
    
    output.write(result, gid);
}

// MARK: - Crossfade (Simple 2-Layer)
// Optimized crossfade between exactly two clips

kernel void compositor_crossfade(
    texture2d<float, access::read> clipA [[texture(0)]],
    texture2d<float, access::read> clipB [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float& t [[buffer(0)]],  // 0.0 = all A, 1.0 = all B
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    float4 colorA = clipA.read(gid);
    float4 colorB = clipB.read(gid);
    
    // Linear interpolation
    float4 result = mix(colorA, colorB, t);
    
    output.write(result, gid);
}
