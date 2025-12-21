#include <metal_stdlib>
#include "ColorSpace.metal"

using namespace metal;

// IDT Types matching Swift enum
constant uint IDT_SRGB_TO_ACESCG = 0;
constant uint IDT_REC709_TO_ACESCG = 1;
constant uint IDT_APPLELOG_TO_ACESCG = 2;
constant uint IDT_P3D65_TO_ACESCG = 3;
constant uint IDT_PASSTHROUGH = 4;

struct IDTUniforms {
    uint idtType;
};

/// Input Device Transform Kernel
/// Normalizes any input media to Linear ACEScg (AP1)
kernel void apply_idt(
    texture2d<float, access::read> sourceTexture [[texture(0)]],
    texture2d<float, access::write> destTexture [[texture(1)]],
    constant IDTUniforms& uniforms [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= sourceTexture.get_width() || gid.y >= sourceTexture.get_height()) {
        return;
    }
    
    float4 inputColor = sourceTexture.read(gid);
    float3 linearColor = inputColor.rgb;
    float3 acescgColor = linearColor;
    
    switch (uniforms.idtType) {
        case IDT_SRGB_TO_ACESCG:
            // sRGB -> Linear -> ACEScg
            acescgColor = ColorSpace::SRGBToACEScg(ColorSpace::SRGBToLinear(inputColor.rgb));
            break;
            
        case IDT_REC709_TO_ACESCG:
            // Rec.709 -> Linear -> ACEScg
            acescgColor = ColorSpace::Rec709ToACEScg(ColorSpace::Rec709ToLinear(inputColor.rgb));
            break;
            
        case IDT_APPLELOG_TO_ACESCG:
            // Apple Log -> Linear Rec.2020 -> ACEScg
            acescgColor = ColorSpace::Rec2020ToACEScg(ColorSpace::AppleLogToLinear(inputColor.rgb));
            break;
            
        case IDT_P3D65_TO_ACESCG:
            // P3-D65 (sRGB Gamma) -> Linear P3 -> ACEScg
            acescgColor = ColorSpace::P3D65ToACEScg(ColorSpace::SRGBToLinear(inputColor.rgb));
            break;
            
        case IDT_PASSTHROUGH:
        default:
            acescgColor = inputColor.rgb;
            break;
    }
    
    // Write Linear ACEScg
    destTexture.write(float4(acescgColor, inputColor.a), gid);
}
