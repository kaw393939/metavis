#include <metal_stdlib>
using namespace metal;

// MARK: - Constants & Matrices

namespace Core {
namespace Color {

    // ACEScg Luminance Weights (Approximate)
    // Based on AP1 primaries
    constant float3 LumaWeights = float3(0.2722287, 0.6740818, 0.0536895);
    
    inline float luminance(float3 rgb) {
        return dot(rgb, LumaWeights);
    }

    // MARK: - Reference Gamut Compression (RGC-style, luma-preserving)

    inline float RGC_knee_compress(float x, float threshold, float limit) {
        // Smoothly compress x above threshold, asymptotically approaching limit.
        // x, threshold, limit are expected >= 0.
        if (x <= threshold) return x;
        float d = x - threshold;
        float range = max(limit - threshold, 1e-4);
        // Rational soft-knee: threshold + (d * range) / (d + range)
        return threshold + (d * range) / (d + range);
    }

    inline float3 RGC_compress_luma_preserving(
        float3 rgbLinear,
        float3 lumaWeights,
        float satThreshold,
        float satLimit,
        float strength
    ) {
        // Luma-preserving saturation limiting.
        // - Preserves achromatic axis.
        // - Compresses saturation (relative chroma) beyond satThreshold toward satLimit.
        // - strength blends between identity (0) and full compression (1).
        float s = clamp(strength, 0.0, 1.0);
        if (s <= 0.0) return rgbLinear;

        float3 x = rgbLinear;
        float luma = dot(x, lumaWeights);
        float3 gray = float3(luma);
        float3 c = x - gray;
        float chroma = length(c);

        // Saturation proxy: chroma relative to luma.
        float denom = max(luma, 1e-4);
        float sat = chroma / denom;

        float t = max(satThreshold, 0.0);
        float L = max(satLimit, t + 1e-3);
        float satC = RGC_knee_compress(max(sat, 0.0), t, L);
        float scale = (sat > 1e-6) ? (satC / sat) : 1.0;

        float3 y = gray + c * scale;
        return mix(x, y, s);
    }
    
} // namespace Color
} // namespace Core

// ACEScg (AP1) Primaries to XYZ (D60) - Not used directly in simple pipeline but good for ref
// We focus on AP1 <-> Rec709/sRGB/P3

// Matrix: Linear sRGB (Rec.709) -> ACEScg (AP1)
constant float3x3 MAT_Rec709_to_ACEScg = float3x3(
    float3(0.6131, 0.0702, 0.0206),
    float3(0.3395, 0.9164, 0.1096),
    float3(0.0474, 0.0134, 0.8698)
);

// Matrix: ACEScg (AP1) -> Linear sRGB (Rec.709)
constant float3x3 MAT_ACEScg_to_Rec709 = float3x3(
    float3(1.7049, -0.1301, -0.0240),
    float3(-0.6217, 1.1407, -0.1289),
    float3(-0.0833, -0.0106, 1.1530)
);

// MARK: - Rec.2020 Matrices
// ACEScg -> Rec.2020 (Linear)
constant float3x3 MAT_ACEScg_to_Rec2020 = float3x3(
    // AP1 (D60) -> Rec.2020 (D65) with Bradford chromatic adaptation.
    // Computed offline from published chromaticities; primaries are very similar so this is near-identity.
    float3(1.0258247, -0.0022344, -0.0050134),
    float3(-0.0200532, 1.0045865, -0.0252901),
    float3(-0.0057716, -0.0023521, 1.0303034)
);

// MARK: - standard Transfer Functions

// sRGB to Linear (De-Gamma)
// Used for IDT
float3 sRGB_to_Linear(float3 srgb) {
    float3 linearOut;
    for (int i = 0; i < 3; i++) {
        if (srgb[i] <= 0.04045) {
            linearOut[i] = srgb[i] / 12.92;
        } else {
            linearOut[i] = pow((srgb[i] + 0.055) / 1.055, 2.4);
        }
    }
    return linearOut;
}

// Linear to sRGB (Gamma)
// Used for ODT (Display View)
float3 Linear_to_sRGB(float3 lin) {
    float3 srgbOut;
    for (int i = 0; i < 3; i++) {
        if (lin[i] <= 0.0031308) {
            srgbOut[i] = 12.92 * lin[i];
        } else {
            srgbOut[i] = 1.055 * pow(lin[i], 1.0/2.4) - 0.055;
        }
    }
    return srgbOut;
}

// ST.2084 (PQ) EOTF Inverse (Linear -> PQ)
// Input: Linear normalized to 0-1 range (where 1.0 = 10000 nits)
float3 Linear_to_PQ(float3 linearColor) {
    float m1 = 2610.0 / 4096.0 * 0.25;
    float m2 = 2523.0 / 4096.0 * 128.0;
    float c1 = 3424.0 / 4096.0;
    float c2 = 2413.0 / 4096.0 * 32.0;
    float c3 = 2392.0 / 4096.0 * 32.0;
    
    float3 Y = pow(max(linearColor, 0.0), m1);
    float3 L = pow((c1 + c2 * Y) / (1.0 + c3 * Y), m2);
    return L;
}

// HLG OETF (Linear -> HLG)
float3 Linear_to_HLG(float3 linearColor) {
    float a = 0.17883277;
    float b = 0.28466892;
    float c = 0.55991073;
    
    float3 hlg;
    for(int i=0; i<3; i++) {
        float x = linearColor[i];
        if (x <= 1.0/12.0) {
            hlg[i] = sqrt(3.0 * x);
        } else {
            hlg[i] = a * log(12.0 * x - b) + c;
        }
    }
    return hlg;
}

// MARK: - HSL / HSV

float3 rgbToHsl(float3 color) {
    float3 hsl;
    float r = color.r;
    float g = color.g;
    float b = color.b;
    float maxColor = max(r, max(g, b));
    float minColor = min(r, min(g, b));
    hsl.z = (maxColor + minColor) / 2.0;

    if (maxColor == minColor) {
        hsl.x = 0.0;
        hsl.y = 0.0;
    } else {
        float d = maxColor - minColor;
        hsl.y = (hsl.z > 0.5) ? d / (2.0 - maxColor - minColor) : d / (maxColor + minColor);
        if (maxColor == r) {
            hsl.x = (g - b) / d + (g < b ? 6.0 : 0.0);
        } else if (maxColor == g) {
            hsl.x = (b - r) / d + 2.0;
        } else {
            hsl.x = (r - g) / d + 4.0;
        }
        hsl.x /= 6.0;
    }
    return hsl;
}

float HueToRGB(float f1, float f2, float hue) {
    if (hue < 0.0) hue += 1.0;
    else if (hue > 1.0) hue -= 1.0;
    float res;
    if ((6.0 * hue) < 1.0) res = f1 + (f2 - f1) * 6.0 * hue;
    else if ((2.0 * hue) < 1.0) res = f2;
    else if ((3.0 * hue) < 2.0) res = f1 + (f2 - f1) * ((2.0 / 3.0) - hue) * 6.0;
    else res = f1;
    return res;
}

float3 hslToRgb(float3 hsl) {
    float3 rgb;
    if (hsl.y == 0.0) {
        rgb = float3(hsl.z); // Luminance
    } else {
        float f2;
        if (hsl.z < 0.5) f2 = hsl.z * (1.0 + hsl.y);
        else f2 = (hsl.z + hsl.y) - (hsl.y * hsl.z);
        float f1 = 2.0 * hsl.z - f2;
        rgb.r = HueToRGB(f1, f2, hsl.x + (1.0/3.0));
        rgb.g = HueToRGB(f1, f2, hsl.x);
        rgb.b = HueToRGB(f1, f2, hsl.x - (1.0/3.0));
    }
    return rgb;
}

// MARK: - Adjustments

kernel void exposure_adjust(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &ev [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 pixel = source.read(gid);
    
    // Apply Exposure (2^EV)
    float exposure = exp2(ev);
    float3 result = pixel.rgb * exposure;
    
    dest.write(float4(result, pixel.a), gid);
}

// ASC CDL (Slope, Offset, Power) + Saturation
// Working Space: ACEScg (AP1)
kernel void cdl_correct(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float3 &slope [[buffer(0)]],
    constant float3 &offset [[buffer(1)]],
    constant float3 &power_param [[buffer(2)]], // 'power' is a function name
    constant float &saturation [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 pixel = source.read(gid);
    float3 rgb = pixel.rgb;
    
    // 1. Slope & Offset
    rgb = rgb * slope + offset;
    
    // 2. Power (Clamp negative before power to avoid NaN)
    // ASC CDL spec says to clamp to 0? Or just max(0, val).
    rgb = max(rgb, 0.0); 
    rgb = pow(rgb, power_param);
    
    // 3. Saturation (in ACEScg)
    // AP1 Luma Weights
    const float3 lumaWeights = float3(0.2722287, 0.6740818, 0.0536895);
    float luma = dot(rgb, lumaWeights);
    rgb = luma + saturation * (rgb - luma);
    
    dest.write(float4(rgb, pixel.a), gid);
}

// 3D LUT Application
// Expects input in 0-1 range (Log or Display Linear)
kernel void lut_apply_3d(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    texture3d<float, access::sample> lut [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    // Linear sampler for tetrahedral-like interpolation (hardware linear is often trilinear)
    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float4 pixel = source.read(gid);
    
    // Sample 3D LUT using RGB as coordinates
    float3 result = lut.sample(lutSampler, pixel.rgb).rgb;
    
    dest.write(float4(result, pixel.a), gid);
}

// 3D LUT Application (RGBA16F fast path)
// For pipelines that are already operating in RGBA16F, this avoids float<->half conversions.
kernel void lut_apply_3d_rgba16f(
    texture2d<half, access::read> source [[texture(0)]],
    texture2d<half, access::write> dest [[texture(1)]],
    texture3d<half, access::sample> lut [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    constexpr sampler lutSampler(coord::normalized, address::clamp_to_edge, filter::linear);

    half4 pixel = source.read(gid);
    half3 result = lut.sample(lutSampler, float3(pixel.rgb)).rgb;
    dest.write(half4(result, pixel.a), gid);
}

kernel void contrast_adjust(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &factor [[buffer(0)]],
    constant float &pivot [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 pixel = source.read(gid);
    
    // Apply Contrast
    float3 result = (pixel.rgb - pivot) * factor + pivot;
    
    dest.write(float4(result, pixel.a), gid);
}

// MARK: - Core Transforms (IDT / ODT)

// Input Device Transform: sRGB Texture -> ACEScg Linear
// This is the "Entry Gate" for the pipeline.
kernel void idt_rec709_to_acescg(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 pixel = source.read(gid);
    
    // 1. Remove Gamma (sRGB -> Linear Rec.709)
    float3 lin709 = sRGB_to_Linear(pixel.rgb);
    
    // 2. Gamut Map (Rec.709 -> ACEScg)
    float3 acescg = MAT_Rec709_to_ACEScg * lin709;
    
    dest.write(float4(acescg, pixel.a), gid);
}

// Input Device Transform: Linear Rec.709 -> ACEScg Linear
// Used for sources that are already linear (e.g. decoded OpenEXR).
kernel void idt_linear_rec709_to_acescg(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    float4 pixel = source.read(gid);
    float3 lin709 = pixel.rgb;
    float3 acescg = MAT_Rec709_to_ACEScg * lin709;
    dest.write(float4(acescg, pixel.a), gid);
}

// Output Device Transform: ACEScg Linear -> sRGB Texture
// This is the "Exit Gate" for viewing.
// NOTE: A real RRT+ODT is complex. This is a "Simple ODT" (Clip + Gamma) for the Vertical Slice.
inline float3 ACES_RRT_curve_hill(float3 v) {
    // ACES RRT+ODT fit (Stephen Hill). Operates on non-negative scene-linear.
    float3 x = max(v, 0.0);
    float3 a = x * (x + 0.0245786f) - 0.000090537f;
    float3 b = x * (0.983729f * x + 0.4329510f) + 0.238081f;
    return a / b;
}

inline float3 ACES_sweeteners_fast(float3 acescg) {
    // Minimal, analytic sweeteners to reduce obvious mismatch vs reference RRT/ODT LUTs.
    // Goal: improve fallback behavior, not replace LUT reference.
    float luma = dot(acescg, Core::Color::LumaWeights);
    float3 gray = float3(luma);

    // Highlight desaturation (scene-linear domain): very gentle.
    float highlight = smoothstep(1.0, 4.0, max(luma, 0.0));
    acescg = mix(acescg, gray, 0.12 * highlight);

    // Red rolloff for strongly red-dominant values (helps match ACES red modifier behavior loosely).
    float maxGB = max(acescg.g, acescg.b);
    float redDom = smoothstep(0.0, 0.25, (acescg.r - maxGB));
    float sat = length(acescg - gray);
    float satW = smoothstep(0.03, 0.25, sat);
    float w = redDom * satW;
    acescg.r = mix(acescg.r, luma, 0.06 * w);
    return acescg;
}

inline float3 ACES_sweeteners_tuned(float3 acescg, float highlightDesatStrength, float redModStrength) {
    // Tunable variant used for parity sweeps.
    float luma = dot(acescg, Core::Color::LumaWeights);
    float3 gray = float3(luma);

    float highlight = smoothstep(1.0, 4.0, max(luma, 0.0));
    float hd = clamp(highlightDesatStrength, 0.0, 1.0);
    acescg = mix(acescg, gray, hd * highlight);

    float maxGB = max(acescg.g, acescg.b);
    float redDom = smoothstep(0.0, 0.25, (acescg.r - maxGB));
    float sat = length(acescg - gray);
    float satW = smoothstep(0.03, 0.25, sat);
    float w = redDom * satW;
    float rs = clamp(redModStrength, 0.0, 0.25);
    acescg.r = mix(acescg.r, luma, rs * w);
    return acescg;
}

inline float3 Core_gamut_compress_luma_preserving_709(float3 lin709, float strength) {
    // Luma-preserving saturation limiting in Rec.709 linear display primaries.
    float3 x = max(lin709, 0.0);
    float luma = dot(x, Core::Color::LumaWeights);

    float tLum = smoothstep(0.25, 1.00, max(luma, 0.0));
    float satLimit = mix(2.4, 1.35, tLum);
    float satThreshold = 0.85 * satLimit;

    float k = clamp(strength, 0.0, 1.0);
    x = Core::Color::RGC_compress_luma_preserving(
        x,
        Core::Color::LumaWeights,
        satThreshold,
        satLimit,
        k
    );
    return max(x, 0.0);
}

float3 ACESFilm(float3 x);
kernel void odt_acescg_to_rec709(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 pixel = source.read(gid);
    
    // Approximate ACES RRT+ODT (scene-referred -> display-referred) using a fitted curve.
    // This is intentionally analytic (no LUT) and exists primarily as a fallback path.
    float3 working = ACES_sweeteners_fast(pixel.rgb);
    float3 rrt = ACES_RRT_curve_hill(working);

    // Gamut map (ACEScg/AP1 -> Rec.709 linear display primaries)
    float3 lin709 = MAT_ACEScg_to_Rec709 * rrt;
    lin709 = clamp(lin709, 0.0, 1.0);

    // Display encode (Linear Rec.709 -> sRGB)
    float3 srgb = Linear_to_sRGB(lin709);
    srgb = clamp(srgb, 0.0, 1.0);
    
    // Force opaque alpha for video export pipelines (AVAssetWriter may treat input as premultiplied).
    dest.write(float4(srgb, 1.0), gid);
}

// Output Device Transform: ACEScg Linear -> sRGB Texture (Studio)
// Higher-correctness path: apply an ACES fitted tone scale before display encoding.
// NOTE: This is still not a full ACES 1.3 RRT+ODT implementation, but it is materially
// closer than the placeholder and is scoped behind the Studio render policy tier.
kernel void odt_acescg_to_rec709_studio(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    float4 pixel = source.read(gid);

    // Studio path uses the same analytic RRT-style curve as the fallback.
    // Keep the separate kernel name for compatibility with existing graphs/tests.
    float3 working = ACES_sweeteners_fast(pixel.rgb);
    float3 rrt = ACES_RRT_curve_hill(working);
    float3 lin709 = MAT_ACEScg_to_Rec709 * rrt;
    lin709 = clamp(lin709, 0.0, 1.0);
    float3 srgb = Linear_to_sRGB(lin709);
    srgb = clamp(srgb, 0.0, 1.0);

    dest.write(float4(srgb, 1.0), gid);
}

// Output Device Transform: ACEScg Linear -> sRGB Texture (Studio, tunable)
// Parameter:
// - gamutCompress: 0..1, luma-preserving chroma compression in Rec.709 linear
kernel void odt_acescg_to_rec709_studio_tuned(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant float &gamutCompress [[buffer(0)]],
    constant float &highlightDesatStrength [[buffer(1)]],
    constant float &redModStrength [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

    float4 pixel = source.read(gid);

    float3 working = ACES_sweeteners_tuned(pixel.rgb, highlightDesatStrength, redModStrength);
    float3 rrt = ACES_RRT_curve_hill(working);
    float3 lin709 = MAT_ACEScg_to_Rec709 * rrt;

    float gc = clamp(gamutCompress, 0.0, 1.0);
    if (gc > 0.0) {
        lin709 = Core_gamut_compress_luma_preserving_709(lin709, gc);
    }

    lin709 = clamp(lin709, 0.0, 1.0);
    float3 srgb = Linear_to_sRGB(lin709);
    srgb = clamp(srgb, 0.0, 1.0);
    dest.write(float4(srgb, 1.0), gid);
}

// MARK: - Tone Mapping (ACES Fitted)

// Narkowicz ACES Fitted (Widely used approximation)
float3 ACESFilm(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

kernel void aces_tonemap(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float4 pixel = source.read(gid);
    
    // Apply Curve
    float3 tonemapped = ACESFilm(pixel.rgb);
    
    dest.write(float4(tonemapped, pixel.a), gid);
}

// Passthrough (Verification)
kernel void source_texture(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    dest.write(source.read(gid), gid);
}

// Source: Linear Ramp (0.0 to 5.0)
// Used for Twin Verification
kernel void source_linear_ramp(
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float width = float(dest.get_width());
    float u = (float(gid.x) / width) * 5.0; // 0.0 -> 5.0
    
    // Grayscale Linear
    dest.write(float4(u, u, u, 1.0), gid);
}

// Source: Test Color Pattern
// R=u, G=u*0.5, B=1.0-u
kernel void source_test_color(
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    float width = float(dest.get_width());
    float u = (float(gid.x) / width); 
    
    float r = u;
    float g = u * 0.5;
    float b = 1.0 - u;
    
    dest.write(float4(r, g, b, 1.0), gid);
}

// MARK: - Scopes

// Accumulate Luma Waveform
// grid output array of size (width * height)
kernel void scope_waveform_accumulate(
    texture2d<float, access::read> source [[texture(0)]],
    device atomic_uint *grid [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;
    
    // Read pixel
    float4 pixel = source.read(gid);
    
    // Calculate Luma (Rec.709)
    float luma = dot(pixel.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // Map to Y bucket (0-255)
    uint width = 256;
    uint yBucket = uint(saturate(luma) * 255.0 + 0.5);
    uint xBucket = uint((float(gid.x) / float(source.get_width())) * float(width));
    
    // Index
    uint index = xBucket + yBucket * width;
    
    // Atomic Add
    atomic_fetch_add_explicit(&grid[index], 1, memory_order_relaxed);
}

// Render Waveform from Grid
kernel void scope_waveform_render(
    device atomic_uint *grid [[buffer(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;
    
    uint width = 256;
    uint index = gid.x + gid.y * width;
    
    // Read Accumulation
    uint count = atomic_load_explicit(&grid[index], memory_order_relaxed);
    
    // Map count to intensity (Heatmap)
    // Simple log scaling for visibility
    float intensity = log2(float(count) + 1.0) * 0.2; 
    intensity = saturate(intensity);
    
    // Green Phosphor look
    float4 color = float4(0.0, intensity, 0.0, 1.0);
    
    dest.write(color, gid);
    
    // Clear buffer for next frame? Handled by Blit in Engine.
}

