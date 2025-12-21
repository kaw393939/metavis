#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct SplitScreenParams {
    float splitPosition;
    float angle;
    float width;
    float _pad;
};

fragment float4 fx_split_screen_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> inputA [[texture(0)]],
    texture2d<float> inputB [[texture(1)]],
    constant SplitScreenParams& params [[buffer(0)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 colorA = inputA.sample(s, in.texCoord);
    float4 colorB = inputB.sample(s, in.texCoord);
    
    float4 finalColor;
    
    // Simple vertical split
    if (in.texCoord.x < params.splitPosition) {
        finalColor = colorA;
    } else {
        finalColor = colorB;
    }
    
    // Draw divider line
    float lineWidth = 0.002;
    if (abs(in.texCoord.x - params.splitPosition) < lineWidth) {
        finalColor = float4(1.0, 1.0, 1.0, 1.0);
    }
    
    return finalColor;
}
