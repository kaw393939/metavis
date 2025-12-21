#include <metal_stdlib>
using namespace metal;

#include "ColorSpace.metal"

// MARK: - FITS Scientific IDT

struct FITSParams {
    float exposure; // Exposure compensation (EV)
    float blackPoint; // Data value to map to 0
    float whitePoint; // Data value to map to 1 (before stretch)
    float stretch; // Asinh stretch factor (softness)
    float4 falseColor; // Color to map the single channel to (e.g. Red for F1800W)
};

// Hyperbolic Sine Stretch (Asinh)
// Standard in astronomical imaging to compress dynamic range
// y = asinh(x * stretch) / asinh(stretch)
inline float asinh_stretch(float x, float stretch) {
    // asinh(x) = log(x + sqrt(x*x + 1))
    float num = log(x * stretch + sqrt(x * stretch * x * stretch + 1.0));
    float den = log(stretch + sqrt(stretch * stretch + 1.0));
    return num / den;
}

kernel void idt_fits_to_acescg(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant FITSParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // 1. Sample Raw Data (R32Float)
    // Note: FITSImporter uploads to R32Float, so we sample .r
    float rawValue = inputTexture.sample(s, uv).r;
    
    // 2. Handle NaN / Inf (Saturation)
    // Map saturated pixels to Pure White (1.0) instead of Black
    if (isnan(rawValue) || isinf(rawValue)) {
        outputTexture.write(float4(100.0, 100.0, 100.0, 1.0), gid); // Super-white for bloom
        return;
    }
    
    // 2b. Handle "Black Cores" (Saturated pixels mapped to 0)
    // If value is 0 but neighbors are bright, it's a saturated core.
    if (rawValue == 0.0) {
        float w = outputTexture.get_width();
        float h = outputTexture.get_height();
        
        float n1 = inputTexture.sample(s, uv + float2(1.0/w, 0)).r;
        float n2 = inputTexture.sample(s, uv - float2(1.0/w, 0)).r;
        float n3 = inputTexture.sample(s, uv + float2(0, 1.0/h)).r;
        float n4 = inputTexture.sample(s, uv - float2(0, 1.0/h)).r;
        
        float avg = (n1 + n2 + n3 + n4) / 4.0;
        
        // Threshold: If neighbors are bright (e.g. > 10% of white point), assume saturation
        if (avg > params.whitePoint * 0.1) {
             outputTexture.write(float4(100.0, 100.0, 100.0, 1.0), gid);
             return;
        }
    }
    
    // 3. Normalize (Black/White Point)
    float norm = (rawValue - params.blackPoint) / (params.whitePoint - params.blackPoint);
    norm = max(0.0f, norm);
    
    // 4. Apply Exposure (Linear Scale)
    norm *= pow(2.0f, params.exposure);
    
    // 5. Apply Asinh Stretch
    // This brings up the faint details while keeping stars from clipping too early
    float stretched = asinh_stretch(norm, params.stretch);
    
    // 6. Map to False Color (Linear ACEScg)
    // The false color is defined in ACEScg space.
    // We multiply the intensity by the color.
    float3 acescg = stretched * params.falseColor.rgb;
    
    outputTexture.write(float4(acescg, 1.0), gid);
}

// MARK: - Sanity Check Kernels

kernel void idt_sanity_constant(
    texture2d<float, access::write> outTex [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    outTex.write(float4(0.5, 0.5, 0.5, 1.0), gid);
}

kernel void idt_copy_norm(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant FITSParams &params           [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;

    float v = inTex.read(gid).r; 
    float vNorm = v / max(params.whitePoint, 1.0); 
    vNorm = clamp(vNorm, 0.0, 8.0);

    // direct visualization: 0..1 clamp
    float mapped = clamp(vNorm, 0.0, 1.0);

    outTex.write(float4(mapped, mapped, mapped, 1.0), gid);
}

// MARK: - Debug Copy Kernel

kernel void jwstIDTDebugCopy(
    texture2d<float, access::read>  inTex  [[texture(0)]],
    texture2d<float, access::write> outTex [[texture(1)]],
    constant FITSParams& params              [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }

    // 1:1 sampling, no scaling
    float v = inTex.read(gid).r;

    // Minimal normalization: optional, but keep simple
    float n = v / max(params.whitePoint, 1.0);  // e.g. 200/300/500
    n = max(n, 0.0);
    
    // Clamp for debug safety
    n = clamp(n, 0.0, 1.0);

    float3 rgb = n * params.falseColor.rgb;

    outTex.write(float4(rgb, 1.0), gid);
}

// MARK: - Constant Fill Debug Kernel

kernel void jwstIDTDebugConstant(
    texture2d<float, access::write> outTex [[texture(0)]],
    constant FITSParams& params             [[buffer(0)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) {
        return;
    }

    // HARDCODED DEBUG COLOR
    // Ignore params completely to rule out zero-init issues
    float3 rgb = float3(0.25, 0.5, 0.75); 

    outTex.write(float4(rgb, 1.0), gid);
}

// MARK: - Data Debug Kernel (Raw Visualization)

kernel void jwstIDTDebugData(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant FITSParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) return;
    
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 uv = (float2(gid) + 0.5) / float2(outputTexture.get_width(), outputTexture.get_height());
    
    // 1. Sample Raw Data (R32Float)
    float rawValue = inputTexture.sample(s, uv).r;
    
    // 2. Normalize using White Point
    // We use the whitePoint passed in params (e.g. 200, 300, 500)
    float norm = rawValue / params.whitePoint;
    
    // 3. Clamp/Scale for Debug (0-1 range)
    // Scaling by 1/10.0 as requested to bring values into visible range if they are large
    float debugVal = clamp(norm / 10.0, 0.0, 1.0);
    
    // 4. Write to Output (Grayscale)
    outputTexture.write(float4(debugVal, debugVal, debugVal, 1.0), gid);
}
