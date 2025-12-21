//
//  ColorSpaceConversion.metal
//  MetaVisRender
//
//  Color space conversion kernels for proper video export
//

#include <metal_stdlib>
#include "ACES.metal"
using namespace metal;

// sRGB EOTF (gamma decode: sRGB -> linear)
inline half3 sRGBToLinear(half3 srgb) {
    half3 linear;
    for (int i = 0; i < 3; i++) {
        if (srgb[i] <= 0.04045h) {
            linear[i] = srgb[i] / 12.92h;
        } else {
            linear[i] = powr((srgb[i] + 0.055h) / 1.055h, 2.4h);
        }
    }
    return linear;
}

// sRGB OETF (gamma encode: linear -> sRGB)
inline half3 LinearTosRGB(half3 linear) {
    half3 srgb;
    for (int i = 0; i < 3; i++) {
        if (linear[i] <= 0.0031308h) {
            srgb[i] = linear[i] * 12.92h;
        } else {
            srgb[i] = 1.055h * powr(linear[i], 1.0h/2.4h) - 0.055h;
        }
    }
    return srgb;
}

// BT.709 OETF (gamma encode: linear -> BT.709)
inline half3 LinearToBT709(half3 linear) {
    half3 bt709;
    for (int i = 0; i < 3; i++) {
        if (linear[i] < 0.018h) {
            bt709[i] = 4.5h * linear[i];
        } else {
            bt709[i] = 1.099h * powr(linear[i], 0.45h) - 0.099h;
        }
    }
    return bt709;
}

// BT.709 EOTF (gamma decode: BT.709 -> linear)
inline half3 BT709ToLinear(half3 bt709) {
    half3 linear;
    for (int i = 0; i < 3; i++) {
        if (bt709[i] < 0.081h) {
            linear[i] = bt709[i] / 4.5h;
        } else {
            linear[i] = powr((bt709[i] + 0.099h) / 1.099h, 1.0h/0.45h);
        }
    }
    return linear;
}

/// Prepare linear RGB texture for BT.709 video export
/// Input: rgba16Float in linear RGB space (from rendering)
/// Output: rgba16Float in BT.709 gamma space (ready for YUV conversion)
kernel void prepare_for_bt709_export(
    texture2d<half, access::read> input [[texture(0)]],   // Linear RGB
    texture2d<half, access::write> output [[texture(1)]], // BT.709 gamma
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    half4 linearColor = input.read(gid);
    
    // Apply BT.709 gamma (OETF)
    half3 bt709Color = LinearToBT709(linearColor.rgb);
    
    // Write with original alpha
    output.write(half4(bt709Color, linearColor.a), gid);
}

/// Prepare linear ACEScg texture for BT.709 video export
/// Input: rgba16Float in Linear ACEScg space (from rendering)
/// Output: rgba16Float in Rec.709 gamma space (ready for YUV conversion)
kernel void prepare_for_video_export(
    texture2d<half, access::read> input [[texture(0)]],   // Linear ACEScg (from rendering)
    texture2d<half, access::write> output [[texture(1)]], // Rec.709 Gamma-encoded RGB (for YUV)
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= input.get_width() || gid.y >= input.get_height()) {
        return;
    }
    
    half4 linearColor = input.read(gid);
    
    // Apply ACES RRT+ODT (ACEScg -> Rec.709 SDR)
    // This handles Gamut Mapping + Tone Mapping + OETF (Gamma)
    float3 acescg = float3(linearColor.rgb);
    float3 rec709 = Core::ACES::ACEScg_to_Rec709_SDR(acescg);
    
    // Write with original alpha
    output.write(half4(half3(rec709), linearColor.a), gid);
}
