#include <metal_stdlib>
using namespace metal;

// MetaVis.ACES
// The single source of truth for color space definitions in Metal.
// Mirrors the Swift ACES struct.

namespace ACES {

    // MARK: - Matrices
    
    // ACES AP0 (ACES2065-1) <-> XYZ (D60)
    constant float3x3 AP0_to_XYZ = float3x3(
        float3(0.9525523959, 0.3439664498, 0.0000000000),
        float3(0.0000000000, 0.7281660966, 0.0000000000),
        float3(0.0000936786, -0.0721325464, 1.0088251844)
    );
    
    constant float3x3 XYZ_to_AP0 = float3x3(
        float3(1.0498110175, -0.4959030231, 0.0000000000),
        float3(0.0000000000, 1.3733130458, 0.0000000000),
        float3(-0.0000974845, 0.0982400361, 0.9912520182)
    );

    // ACES AP1 (ACEScg) <-> XYZ (D60)
    constant float3x3 ACEScg_to_XYZ = float3x3(
        float3(0.6624541811, 0.1340042065, 0.1561876870),
        float3(0.2722287168, 0.6740817658, 0.0536895174),
        float3(-0.0055746495, 0.0040607335, 1.0103391003)
    );
    
    constant float3x3 XYZ_to_ACEScg = float3x3(
        float3(1.6410233797, -0.3248032942, -0.2364246952),
        float3(-0.6636628587, 1.6153315917, 0.0167563477),
        float3(0.0117216011, -0.0082844420, 0.9883948585)
    );
    
    // Rec.709 (D65) <-> XYZ (D65)
    constant float3x3 Rec709_to_XYZ = float3x3(
        float3(0.4124564, 0.2126729, 0.0193339),
        float3(0.3575761, 0.7151522, 0.1191920),
        float3(0.1804375, 0.0721750, 0.9503041)
    );
    
    constant float3x3 XYZ_to_Rec709 = float3x3(
        float3(3.2404542, -0.9692660, 0.0556434),
        float3(-1.5371385, 1.8760108, -0.2040259),
        float3(-0.4985314, 0.0415560, 1.0572252)
    );
}
