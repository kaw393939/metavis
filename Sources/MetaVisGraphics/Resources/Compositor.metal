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

// MARK: - Dip (2-Layer)
// Fade from clipA -> dipColor -> clipB.

kernel void compositor_dip(
    texture2d<float, access::read> clipA [[texture(0)]],
    texture2d<float, access::read> clipB [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float& p [[buffer(0)]],      // 0.0 = all A, 0.5 = dipColor, 1.0 = all B
    constant float4& dipColor [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    float4 colorA = clipA.read(gid);
    float4 colorB = clipB.read(gid);
    float4 c = dipColor;

    float t = clamp(p, 0.0f, 1.0f);
    float4 result;
    if (t < 0.5f) {
        float u = t * 2.0f;
        result = mix(colorA, c, u);
    } else {
        float u = (t - 0.5f) * 2.0f;
        result = mix(c, colorB, u);
    }

    output.write(result, gid);
}

// MARK: - Wipe (2-Layer)
// Reveals clipB over clipA in a direction.
// direction: 0=leftToRight, 1=rightToLeft, 2=topToBottom, 3=bottomToTop

kernel void compositor_wipe(
    texture2d<float, access::read> clipA [[texture(0)]],
    texture2d<float, access::read> clipB [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float& p [[buffer(0)]],
    constant float& direction [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;

    float4 colorA = clipA.read(gid);
    float4 colorB = clipB.read(gid);

    float t = clamp(p, 0.0f, 1.0f);
    int dir = (int)round(direction);

    float w = (float)max((uint)1, output.get_width() - 1);
    float h = (float)max((uint)1, output.get_height() - 1);
    float2 uv = float2((float)gid.x / w, (float)gid.y / h);

    bool showB = false;
    switch (dir) {
        case 0: showB = (uv.x <= t); break;           // left -> right
        case 1: showB = (uv.x >= (1.0f - t)); break;  // right -> left
        case 2: showB = (uv.y <= t); break;           // top -> bottom
        case 3: showB = (uv.y >= (1.0f - t)); break;  // bottom -> top
        default: showB = (uv.x <= t); break;
    }

    output.write(showB ? colorB : colorA, gid);
}
