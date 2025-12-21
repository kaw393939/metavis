// SpectralDispersion.metal
// MetaVisRender
//
// Sprint 19: Color Management
// Physically-based spectral dispersion (prismatic light splitting)
// Operates in Linear ACEScg color space

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// MARK: - Spectral Dispersion
// =============================================================================

/// Spectral dispersion settings
struct SpectralDispersionParams {
    float intensity;        // Overall effect strength (0-1)
    float spread;           // How far wavelengths separate (in pixels at 1080p)
    float2 center;          // Optical center (normalized 0-1, default 0.5, 0.5)
    float falloff;          // Radial falloff exponent (1 = linear, 2 = quadratic)
    float angle;            // Dispersion angle in radians (0 = radial outward)
    uint samples;           // Number of spectral samples (3 = RGB, higher = smoother)
};

/// Spectral wavelength to ACEScg color conversion
/// Based on CIE 1931 color matching functions
inline float3 wavelengthToACEScg(float wavelength) {
    // Approximate visible spectrum (380nm - 780nm) normalized to 0-1
    // Returns linear ACEScg color
    
    float x, y, z;
    
    // CIE XYZ approximation from wavelength
    float t = (wavelength - 0.5) * 2.0;  // -1 to 1 range
    
    // Gaussian approximations for CIE XYZ
    x = 1.056 * exp(-0.5 * pow((t - 0.2) / 0.2, 2.0)) +
        0.362 * exp(-0.5 * pow((t + 0.5) / 0.3, 2.0));
    y = 0.821 * exp(-0.5 * pow((t + 0.0) / 0.3, 2.0)) +
        0.286 * exp(-0.5 * pow((t + 0.5) / 0.2, 2.0));
    z = 1.217 * exp(-0.5 * pow((t + 0.7) / 0.2, 2.0));
    
    // XYZ to ACEScg (AP1) matrix
    // Using D65 adaptation
    float3x3 XYZ_TO_ACESCG = float3x3(
        float3( 1.6410234, -0.3248033, -0.2364247),
        float3(-0.6636629,  1.6153316,  0.0167563),
        float3( 0.0117219, -0.0082844,  0.9883949)
    );
    
    float3 xyz = float3(x, y, z);
    float3 acescg = XYZ_TO_ACESCG * xyz;
    
    // Normalize and clamp
    return max(acescg, float3(0.0));
}

/// Simple RGB spectral weights for faster rendering
/// Uses overlapping Gaussian-like curves to avoid color casts
inline float3 spectralWeightRGB(float wavelength) {
    // wavelength: 0 = red/long wave, 0.5 = green, 1 = blue/short wave
    float3 weights;
    
    // Use Gaussian-like curves with proper overlap
    // This prevents magenta gaps between red and blue
    float sigma = 0.25;  // Controls overlap width
    
    // Red peaks at 0, green at 0.5, blue at 1.0
    weights.r = exp(-pow(wavelength - 0.0, 2.0) / (2.0 * sigma * sigma));
    weights.g = exp(-pow(wavelength - 0.5, 2.0) / (2.0 * sigma * sigma));
    weights.b = exp(-pow(wavelength - 1.0, 2.0) / (2.0 * sigma * sigma));
    
    // Ensure weights sum to 1 (energy conservation)
    float sum = weights.r + weights.g + weights.b;
    return weights / max(sum, 0.001);
}

/// Main spectral dispersion kernel
/// This shader creates chromatic aberration by offsetting RGB channels
/// based on their "wavelength" - red shifts one way, blue the other.
/// This is more like lens chromatic aberration than a true prism.
kernel void cs_spectral_dispersion(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant SpectralDispersionParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Early out if effect is disabled
    if (params.intensity <= 0.0) {
        outTexture.write(inTexture.read(gid), gid);
        return;
    }
    
    // Calculate position relative to optical center
    float2 uv = float2(gid) / float2(width, height);
    float2 center = params.center;
    float2 delta = uv - center;
    
    // Distance from center (affects dispersion amount)
    float dist = length(delta);
    float dispersionAmount = pow(dist, params.falloff) * params.intensity;
    
    // Direction of dispersion
    float2 dir;
    if (params.angle == 0.0) {
        // Radial dispersion (outward from center)
        dir = normalize(delta + 0.0001);
    } else {
        // Angular dispersion
        dir = float2(cos(params.angle), sin(params.angle));
    }
    
    // Scale spread by resolution (reference: 1080p)
    float spreadPixels = params.spread * (float(height) / 1080.0);
    float spreadUV = spreadPixels / float(height);
    
    // Calculate offset for each color channel
    // Red = long wavelength, less refraction (shifts outward less)
    // Green = medium wavelength
    // Blue = short wavelength, more refraction (shifts outward more)
    float2 offsetR = dir * (-1.0) * spreadUV * dispersionAmount;  // Red shifts inward
    float2 offsetG = float2(0.0);                                   // Green stays centered
    float2 offsetB = dir * (1.0) * spreadUV * dispersionAmount;   // Blue shifts outward
    
    // Sample each channel at its offset position
    float2 uvR = uv + offsetR;
    float2 uvG = uv + offsetG;
    float2 uvB = uv + offsetB;
    
    // Clamp to texture bounds
    float2 posR = clamp(uvR * float2(width, height), float2(0.0), float2(width - 1, height - 1));
    float2 posG = clamp(uvG * float2(width, height), float2(0.0), float2(width - 1, height - 1));
    float2 posB = clamp(uvB * float2(width, height), float2(0.0), float2(width - 1, height - 1));
    
    // Read each channel from its position
    float r = inTexture.read(uint2(posR)).r;
    float g = inTexture.read(uint2(posG)).g;
    float b = inTexture.read(uint2(posB)).b;
    float a = inTexture.read(gid).a;
    
    // Blend with original based on intensity
    float4 original = inTexture.read(gid);
    float3 dispersed = float3(r, g, b);
    float3 final = mix(original.rgb, dispersed, params.intensity);
    
    outTexture.write(float4(final, a), gid);
}


// =============================================================================
// MARK: - Fast Chromatic Aberration (3-sample version)
// =============================================================================

/// Fast chromatic aberration - just offsets RGB channels
kernel void cs_chromatic_aberration(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float& intensity [[buffer(0)]],
    constant float2& center [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    float2 uv = float2(gid) / float2(width, height);
    float2 delta = uv - center;
    float dist = length(delta);
    float2 dir = normalize(delta + 0.0001);
    
    // Offset amount based on distance from center
    float offset = dist * intensity * 0.02;
    
    // Sample RGB at different positions
    // Red shifts outward, blue shifts inward
    float2 uvR = uv + dir * offset;
    float2 uvG = uv;
    float2 uvB = uv - dir * offset;
    
    // Convert to pixel coordinates
    float2 posR = clamp(uvR * float2(width, height), float2(0.0), float2(width - 1, height - 1));
    float2 posG = clamp(uvG * float2(width, height), float2(0.0), float2(width - 1, height - 1));
    float2 posB = clamp(uvB * float2(width, height), float2(0.0), float2(width - 1, height - 1));
    
    float r = inTexture.read(uint2(posR)).r;
    float g = inTexture.read(uint2(posG)).g;
    float b = inTexture.read(uint2(posB)).b;
    float a = inTexture.read(gid).a;
    
    outTexture.write(float4(r, g, b, a), gid);
}
