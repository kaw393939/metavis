#include <metal_stdlib>
#include "ColorSpace.metal"
#include "Core/ACES.metal"
#include "Core/Color.metal"
#include "Core/Noise.metal"

// Include Atomic Effects
#include "Effects/FilmGrain.metal"
#include "Effects/Vignette.metal"
#include "Effects/ColorGrading.metal"
#include "Effects/Bloom.metal" // For downsample/upsample

using namespace metal;

// MARK: - Post-Processing Pipeline
// Implements the "Superhuman" Filmic Pipeline using the Atomic Shader Library.

// Tone Mapping Operators
enum ToneMapOperator {
    TM_ACES_FULL     = 0,
    TM_ACES_APPROX   = 1,
    TM_REINHARD      = 2,
    TM_UNCHARTED2    = 3,
    TM_LINEAR        = 4
};

// Output Display Transform (ODT) Targets
enum ODTTarget {
    ODT_REC709_SDR   = 0,
    ODT_SRGB_SDR     = 1,
    ODT_P3D65_SDR    = 2,
    ODT_REC2020_PQ   = 3,
    ODT_REC2020_HLG  = 4,
    ODT_LINEAR_SRGB  = 5,
    ODT_LINEAR_ACES  = 6
};

// MARK: - Helper Functions (Legacy/Specific to Uber Shader)

// Reinhard Tone Mapping
inline float3 TonemapReinhard(float3 color) {
    return color / (1.0 + color);
}

// Uncharted 2 Tone Mapping
inline float3 TonemapUncharted2(float3 x) {
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;
    const float W = 11.2;
    
    auto curve = [&](float3 c) {
        return ((c * (A * c + C * B) + D * E) / (c * (A * c + B) + D * F)) - E / F;
    };
    
    return curve(x) / curve(float3(W));
}

// Narkowicz ACES Approximation
inline float3 TonemapACESApprox(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// MARK: - Kernels

// Bloom Downsample (Wrapper)
kernel void bloom_downsample(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    constant float &knee [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Check if this is the first pass (thresholding enabled)
    if (threshold > 0.0) {
        // We need to apply prefilter to each tap of the downsample to be correct
        // Unroll the 13-tap filter manually with prefilter
        
        float2 texelSize = 1.0f / float2(inputTexture.get_width(), inputTexture.get_height());
        float x = texelSize.x;
        float y = texelSize.y;
        
        // Helper for tap + prefilter
        auto sample_pre = [&](float2 offset) -> half4 {
            half4 c = half4(inputTexture.sample(s, uv + offset));
            // Hardcoded clampMax of 65504.0 (half float max) or lower to prevent fireflies
            half3 filtered = Effects::Bloom::Prefilter(c.rgb, half(threshold), half(knee), 100.0h);
            return half4(filtered, c.a);
        };
        
        // Center
        half4 e = sample_pre(float2(0, 0));
        
        // Inner box
        half4 a = sample_pre(float2(-2*x, 2*y));
        half4 b = sample_pre(float2( 0,   2*y));
        half4 c = sample_pre(float2( 2*x, 2*y));
        half4 d = sample_pre(float2(-2*x, 0));
        half4 f = sample_pre(float2( 2*x, 0));
        half4 g = sample_pre(float2(-2*x, -2*y));
        half4 h = sample_pre(float2( 0,   -2*y));
        half4 i = sample_pre(float2( 2*x, -2*y));
        
        // Inner diamond
        half4 j = sample_pre(float2(-x, y));
        half4 k = sample_pre(float2( x, y));
        half4 l = sample_pre(float2(-x, -y));
        half4 m = sample_pre(float2( x, -y));
        
        half4 downsample = (a+c+g+i)*0.03125h + (b+d+f+h)*0.0625h + (e+j+k+l+m)*0.125h;
        outputTexture.write(float4(downsample), gid);
        
    } else {
        // Standard downsample (subsequent passes)
        half4 result = Effects::Bloom::Downsample(inputTexture, s, uv);
        outputTexture.write(float4(result), gid);
    }
}

// Bloom Upsample (Wrapper)
kernel void bloom_upsample(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::read_write> outputTexture [[texture(1)]],
    constant float &filterRadius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    half4 upsampled = Effects::Bloom::Upsample(inputTexture, s, uv, filterRadius);
    float4 existing = outputTexture.read(gid);
    
    // Additive blend
    outputTexture.write(existing + float4(upsampled), gid);
}

// Final Composite Uber-Kernel
kernel void final_composite(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    texture3d<float, access::sample> lutTexture [[texture(2)]],
    texture2d<float, access::sample> bloomTexture [[texture(3)]],
    constant float &vignetteIntensity [[buffer(0)]],
    constant float &vignetteSmoothness [[buffer(1)]], // Legacy param, mapped to intensity/falloff
    constant float &filmGrainStrength [[buffer(2)]],
    constant float &lutIntensity [[buffer(3)]],
    constant bool &hasLUT [[buffer(4)]],
    constant float &time [[buffer(5)]],
    constant float &letterboxRatio [[buffer(6)]],
    constant float &exposure [[buffer(7)]],
    constant uint &tonemapOperator [[buffer(8)]],
    constant float &saturation [[buffer(9)]],
    constant float &contrast [[buffer(10)]],
    constant uint &odt [[buffer(11)]],
    constant uint &debugFlag [[buffer(12)]],
    constant uint &validationMode [[buffer(13)]],
    constant float &bloomStrength [[buffer(14)]],
    constant bool &hasBloom [[buffer(15)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    // 0. Input (Linear ACEScg)
    float4 color = inputTexture.read(gid);
    
    // SAFETY: Check for NaNs in input to prevent catastrophic failure
    if (isnan(color.r) || isnan(color.g) || isnan(color.b)) {
        // Output safe black (or debug magenta if debugFlag is set)
        if (debugFlag == 1) {
            outputTexture.write(float4(1.0, 0.0, 1.0, 1.0), gid);
        } else {
            outputTexture.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        }
        return;
    }

    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // Validation Mode: Bypass creative effects
    bool isValidation = (validationMode == 1); 
    
    // 1. Bloom (Linear Additive) - Pre-Exposure
    if (!isValidation && hasBloom) {
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 bloom = bloomTexture.sample(s, uv);
        color.rgb += bloom.rgb * bloomStrength;
    }
    
    // 2. Exposure (Linear)
    color.rgb *= exposure;
    
    // 3. Grading (Linear ACEScg)
    if (!isValidation) {
        // Saturation
        if (saturation != 1.0) {
            float luma = Core::Color::luminance(color.rgb);
            color.rgb = mix(float3(luma), color.rgb, saturation);
        }
        
        // Contrast
        if (contrast != 1.0) {
            color.rgb = (color.rgb - 0.5) * contrast + 0.5;
        }
        
        // Vignette (Physical)
        if (vignetteIntensity > 0.0) {
            // Map legacy params to physical params
            // Assume 35mm sensor (36mm width) and 50mm lens as baseline
            float sensorWidth = 36.0;
            float focalLength = 50.0; 
            float aspect = float(outputTexture.get_width()) / float(outputTexture.get_height());
            
            // Use legacy intensity as the mix factor
            color.rgb = Effects::Vignette::Apply(color.rgb, uv, aspect, sensorWidth, focalLength, vignetteIntensity, vignetteSmoothness, 1.0);
        }
        
        // Film Grain
        if (filmGrainStrength > 0.0) {
            // Use pixel coords for noise seed
            float2 noiseUV = float2(gid);
            color.rgb = Effects::FilmGrain::Apply(color.rgb, noiseUV, time, filmGrainStrength, 1.0, 1.0);
            
            // SAFETY: Ensure no negative values before ACES RRT
            // Negative values cause purple/magenta artifacts in ACES
            color.rgb = max(color.rgb, float3(0.0));
        }
        
        // LUT
        if (hasLUT) {
            color.rgb = Effects::ColorGrading::ApplyLUT(color.rgb, lutTexture, lutIntensity);
        }
    }
    
    // 4. Tonemapping & ODT
    float3 finalColor = color.rgb;
    
    if (tonemapOperator == TM_ACES_FULL) {
        // ACES 1.3 RRT+ODT
        switch (odt) {
            case ODT_REC709_SDR:  finalColor = Core::ACES::ACEScg_to_Rec709_SDR(finalColor); break;
            case ODT_SRGB_SDR:    
                finalColor = Core::ACES::ACEScg_to_Rec709_SDR(finalColor);
                finalColor = ColorSpace::Rec709ToLinear(finalColor);
                finalColor = ColorSpace::LinearToSRGB(finalColor);
                break;
            case ODT_P3D65_SDR:   finalColor = Core::ACES::ACEScg_to_P3D65_SDR(finalColor); break;
            case ODT_REC2020_PQ:  finalColor = Core::ACES::ACEScg_to_Rec2020_PQ(finalColor, 1000.0); break;
            case ODT_REC2020_HLG: 
                finalColor = ColorSpace::xyz_to_rgb(ColorSpace::acescg_to_xyz(finalColor), ColorSpace::PRIM_REC2020);
                finalColor = ColorSpace::LinearToHLG(finalColor);
                break;
            case ODT_LINEAR_SRGB: finalColor = ColorSpace::ACEScgToSRGB(finalColor); break;
            case ODT_LINEAR_ACES: break;
            default:              finalColor = Core::ACES::ACEScg_to_Rec709_SDR(finalColor); break;
        }
    } else {
        // Non-ACES Tonemappers
        switch (tonemapOperator) {
            case TM_ACES_APPROX: finalColor = TonemapACESApprox(finalColor); break;
            case TM_REINHARD:    finalColor = TonemapReinhard(finalColor); break;
            case TM_UNCHARTED2:  finalColor = TonemapUncharted2(finalColor); break;
            case TM_LINEAR:      break;
        }
        
        // Gamut Transform & OETF
        int primaries = ColorSpace::PRIM_REC709;
        int transfer = ColorSpace::TF_REC709;
        
        switch (odt) {
            case ODT_REC709_SDR:  primaries = ColorSpace::PRIM_REC709; transfer = ColorSpace::TF_REC709; break;
            case ODT_SRGB_SDR:    primaries = ColorSpace::PRIM_SRGB;   transfer = ColorSpace::TF_SRGB; break;
            case ODT_P3D65_SDR:   primaries = ColorSpace::PRIM_P3D65;  transfer = ColorSpace::TF_SRGB; break;
            case ODT_REC2020_PQ:  primaries = ColorSpace::PRIM_REC2020; transfer = ColorSpace::TF_PQ; break;
            case ODT_LINEAR_SRGB: primaries = ColorSpace::PRIM_SRGB;   transfer = ColorSpace::TF_LINEAR; break;
            case ODT_LINEAR_ACES: primaries = ColorSpace::PRIM_ACESCG; transfer = ColorSpace::TF_LINEAR; break;
        }
        
        finalColor = ColorSpace::EncodeFromACEScg(finalColor, primaries, transfer);
    }
    
    // 5. Letterbox
    if (letterboxRatio > 0.0) {
        float currentAspect = float(outputTexture.get_width()) / float(outputTexture.get_height());
        float2 size = float2(1.0);
        if (letterboxRatio > currentAspect) size.y = currentAspect / letterboxRatio;
        else size.x = letterboxRatio / currentAspect;
        
        float2 min = 0.5 - size * 0.5;
        float2 max = 0.5 + size * 0.5;
        float2 val = step(min, uv) * step(uv, max);
        finalColor *= (val.x * val.y);
    }
    
    outputTexture.write(float4(finalColor, color.a), gid);
}

// Composite overlay
kernel void composite_overlay(
    texture2d<float, access::read> baseTexture [[texture(0)]],
    texture2d<float, access::sample> overlayTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    float4 base = baseTexture.read(gid);
    
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 overlay = overlayTexture.sample(s, uv);
    
    // REMOVED: Double linearization fix. Input is now .rgba16Float (Linear)
    // overlay.rgb = ColorSpace::SRGBToLinear(overlay.rgb);
    
    float3 outRGB = overlay.rgb + base.rgb * (1.0 - overlay.a);
    float outA = overlay.a + base.a * (1.0 - overlay.a);
    
    outputTexture.write(float4(outRGB, outA), gid);
}
