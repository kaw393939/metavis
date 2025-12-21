#include <metal_stdlib>
#include "Core/ACES.metal"
#include "Shaders/ColorSpace.metal"

using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Simple full-screen quad vertex shader
vertex VertexOut display_vertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}

// ODT Fragment Shader
// Converts ACEScg (Linear) -> Display Space (e.g. Rec.709 Gamma 2.4)
fragment float4 display_fragment(VertexOut in [[stage_in]],
                                 texture2d<float> inputTexture [[texture(0)]],
                                 constant int &displayMode [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = inputTexture.sample(s, in.texCoord);
    
    float3 outputColor = color.rgb;
    
    // Apply ODT based on display mode
    // 0: Rec.709 (SDR)
    // 1: P3-D65 (SDR)
    // 2: Rec.2020 (PQ HDR) - TODO
    // 3: Linear (Debug)
    
    switch (displayMode) {
        case 0: // Rec.709
            outputColor = Core::ACES::ACEScg_to_Rec709_SDR(outputColor);
            break;
        case 1: // P3-D65
            // Note: Core::ACES needs to expose P3 ODT or we map manually
            // For now, we'll use the Rec.709 RRT and convert gamut if needed, 
            // but ACES RRT usually outputs to a standard space.
            // Let's check Core/ACES.metal again for P3 support.
            // Assuming ACEScg_to_P3D65_SDR exists or we implement it.
            // If not, fallback to Rec.709 for safety.
             outputColor = Core::ACES::ACEScg_to_Rec709_SDR(outputColor); 
            break;
        case 3: // Linear (Pass-through / Debug)
            break;
        default:
            outputColor = Core::ACES::ACEScg_to_Rec709_SDR(outputColor);
            break;
    }
    
    // DEBUG: Force RED output to verify pipeline
    // return float4(1.0, 0.0, 0.0, 1.0);
    return float4(outputColor, color.a);
}
