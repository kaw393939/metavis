#include <metal_stdlib>
using namespace metal;

#include "ColorSpace.metal"

// MARK: - Input Device Transforms (IDT)

// Kernel to convert sRGB (0-1, Gamma Encoded) to ACEScg (Linear, AP1)
// Uses the Core::ColorSpace definitions for bit-perfect conversion.
kernel void idt_srgb_to_acescg(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float4 inputColor = inputTexture.sample(s, uv);
    
    // 1. Remove sRGB Gamma (EOTF) -> Linear sRGB
    float3 linearSRGB = Core::ColorSpace::SRGBToLinear(inputColor.rgb);
    
    // 2. Convert Primaries: Linear sRGB (Rec.709) -> ACEScg (AP1)
    // We use the matrix defined in ColorSpace.metal
    // Note: ColorSpace.metal might define this as Rec709ToACEScg or similar.
    // Let's check the header. If not explicit, we can chain Rec709->XYZ->ACEScg.
    // Looking at ColorSpace.metal content from previous steps:
    // It has M_Rec709_to_XYZ and M_XYZ_to_ACEScg.
    
    float3 xyz = Core::ColorSpace::M_Rec709_to_XYZ * linearSRGB;
    float3 acescg = Core::ColorSpace::M_XYZ_to_ACEScg * xyz;
    
    outputTexture.write(float4(acescg, inputColor.a), gid);
}

// Kernel to convert Rec.709 Video (Gamma 2.4) to ACEScg
kernel void idt_rec709_to_acescg(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float4 inputColor = inputTexture.sample(s, uv);
    
    // 1. Remove Rec.709 Gamma (EOTF ~2.4)
    float3 linearRec709 = Core::ColorSpace::Rec709ToLinear(inputColor.rgb);
    
    // 2. Convert Primaries
    float3 xyz = Core::ColorSpace::M_Rec709_to_XYZ * linearRec709;
    float3 acescg = Core::ColorSpace::M_XYZ_to_ACEScg * xyz;
    
    outputTexture.write(float4(acescg, inputColor.a), gid);
}

// MARK: - Generic IDT

struct IDTParams {
    int transferFunction;
    int primaries;
    float padding[2];
};

// Generic Kernel to convert Any Input -> ACEScg
// Uses the high-level DecodeToACEScg API from ColorSpace.metal
kernel void idt_generic_to_acescg(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant IDTParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    float4 inputColor = inputTexture.sample(s, uv);
    
    float3 acescg = Core::ColorSpace::DecodeToACEScg(inputColor.rgb, params.transferFunction, params.primaries);
    
    outputTexture.write(float4(acescg, inputColor.a), gid);
}
