#include <metal_stdlib>
using namespace metal;

#ifndef COLOR_SPACE_METAL
#define COLOR_SPACE_METAL

// MetaVis.ColorSpace
// The single source of truth for color space definitions, encodings, and gamut transforms.
// Implements the "Superhuman" ColorSpace spec.
//
// NOTE: This file is scheduled for refactoring into Core/ColorSpace/ modules.
// For new code, prefer using Core::ColorSpace once migration is complete.

namespace Core {
namespace ColorSpace {

    // MARK: - Enums

    // Transfer Functions
    enum TransferFn {
        TF_LINEAR    = 0,
        TF_SRGB      = 1,
        TF_REC709    = 2, // Gamma 2.4
        TF_PQ        = 3, // ST.2084
        TF_HLG       = 4, // BT.2100
        TF_APPLE_LOG = 5
    };

    // Primaries
    enum Primaries {
        PRIM_ACESCG  = 0, // AP1
        PRIM_AP0     = 1, // ACES2065-1
        PRIM_SRGB    = 2, // Rec.709 primaries
        PRIM_REC709  = 2, // Alias
        PRIM_P3D65   = 3, // Display P3
        PRIM_REC2020 = 4
    };

    // MARK: - Constants (Matrices)

    // ACES AP0 (ACES2065-1) <-> XYZ (D60)
    constant float3x3 M_AP0_to_XYZ = float3x3(
        float3(0.9525523959, 0.0000000000, 0.0000936786),
        float3(0.3439664498, 0.7281660966, -0.0721325464),
        float3(0.0000000000, 0.0000000000, 1.0088251844)
    );
    constant float3x3 M_XYZ_to_AP0 = float3x3(
        float3(1.0498110175, 0.0000000000, -0.0000974845),
        float3(-0.4959030231, 1.3733130458, 0.0982400361),
        float3(0.0000000000, 0.0000000000, 0.9912520182)
    );

    // ACES AP1 (ACEScg) <-> XYZ (D60)
    constant float3x3 M_ACEScg_to_XYZ = float3x3(
        float3(0.6624541811, 0.2722287168, -0.0055746495),
        float3(0.1340042065, 0.6740817658, 0.0040607335),
        float3(0.1561876870, 0.0536895174, 1.0103391003)
    );
    constant float3x3 M_XYZ_to_ACEScg = float3x3(
        float3(1.6410233797, -0.6636628587, 0.0117216011),
        float3(-0.3248032942, 1.6153315917, -0.0082844420),
        float3(-0.2364246952, 0.0167563477, 0.9883948585)
    );

    // Rec.709 / sRGB (D65) <-> XYZ (D65)
    constant float3x3 M_Rec709_to_XYZ = float3x3(
        float3(0.4124564, 0.2126729, 0.0193339),
        float3(0.3575761, 0.7151522, 0.1191920),
        float3(0.1804375, 0.0721750, 0.9503041)
    );
    constant float3x3 M_XYZ_to_Rec709 = float3x3(
        float3(3.2404542, -0.9692660, 0.0556434),
        float3(-1.5371385, 1.8760108, -0.2040259),
        float3(-0.4985314, 0.0415560, 1.0572252)
    );

    // P3-D65 <-> XYZ (D65)
    constant float3x3 M_P3D65_to_XYZ = float3x3(
        float3(0.4865709486, 0.2289745641, 0.0000000000),
        float3(0.2656676932, 0.6917385218, 0.0451133819),
        float3(0.1982172852, 0.0792869141, 1.0439443689)
    );
    constant float3x3 M_XYZ_to_P3D65 = float3x3(
        float3(2.4934969119, -0.8294889696, 0.0358458302),
        float3(-0.9313836179, 1.7626640603, -0.0761723893),
        float3(-0.4027107845, 0.0236246858, 0.9568845240)
    );

    // Rec.2020 (D65) <-> XYZ (D65)
    constant float3x3 M_Rec2020_to_XYZ = float3x3(
        float3(0.6369580483, 0.2627002120, 0.0000000000),
        float3(0.1446169036, 0.6779980715, 0.0280726930),
        float3(0.1688809752, 0.0593017165, 1.0609850577)
    );
    constant float3x3 M_XYZ_to_Rec2020 = float3x3(
        float3(1.7166511880, -0.6666843518, 0.0176398574),
        float3(-0.3556707838, 1.6164812366, -0.0427706533),
        float3(-0.2533662814, 0.0157685458, 0.9421031206)
    );

    // Bradford Chromatic Adaptation Transform (D65 -> D60)
    constant float3x3 M_CAT_D65_to_D60 = float3x3(
        float3(1.0129911, 0.00767096, -0.00283398),
        float3(0.00608452, 0.99817263, 0.00467335),
        float3(-0.01492987, -0.00501791, 0.92470399)
    );

    // Bradford Chromatic Adaptation Transform (D60 -> D65)
    constant float3x3 M_CAT_D60_to_D65 = float3x3(
        float3(0.9869929, -0.0075848, 0.0030632),
        float3(-0.0060154, 1.0018102, -0.0050636),
        float3(0.0159321, 0.0054369, 1.0814380)
    );

    // Combined Matrices (Baked)
    // Note: Metal allows constant initialization from other constants.
    // We compute these to ensure exact consistency with the base definitions.
    
    // ACEScg <-> AP0
    constant float3x3 M_ACEScg_to_AP0 = M_XYZ_to_AP0 * M_ACEScg_to_XYZ;
    constant float3x3 M_AP0_to_ACEScg = M_XYZ_to_ACEScg * M_AP0_to_XYZ;

    // ACEScg <-> Rec.709 (via D60/D65 CAT)
    constant float3x3 M_Rec709_to_ACEScg = M_XYZ_to_ACEScg * M_CAT_D65_to_D60 * M_Rec709_to_XYZ;
    constant float3x3 M_ACEScg_to_Rec709 = M_XYZ_to_Rec709 * M_CAT_D60_to_D65 * M_ACEScg_to_XYZ;
    
    // ACEScg <-> P3-D65 (via D60/D65 CAT)
    constant float3x3 M_P3D65_to_ACEScg = M_XYZ_to_ACEScg * M_CAT_D65_to_D60 * M_P3D65_to_XYZ;
    constant float3x3 M_ACEScg_to_P3D65 = M_XYZ_to_P3D65 * M_CAT_D60_to_D65 * M_ACEScg_to_XYZ;
    
    // ACEScg <-> Rec.2020 (via D60/D65 CAT)
    constant float3x3 M_Rec2020_to_ACEScg = M_XYZ_to_ACEScg * M_CAT_D65_to_D60 * M_Rec2020_to_XYZ;
    constant float3x3 M_ACEScg_to_Rec2020 = M_XYZ_to_Rec2020 * M_CAT_D60_to_D65 * M_ACEScg_to_XYZ;
    
    // Standard Luminance Weights (Rec.709)
    [[maybe_unused]] constant float3 LUMA_709 = float3(0.2126, 0.7152, 0.0722);
    
    // MARK: - Transfer Functions

    // sRGB EOTF (sRGB -> Linear)
    inline float3 SRGBToLinear(float3 c) {
        float3 low  = c / 12.92f;
        float3 high = pow((c + 0.055f) / 1.055f, 2.4f);
        float3 mask = step(0.04045f, c);
        return mix(low, high, mask);
    }

    // sRGB OETF (Linear -> sRGB)
    inline float3 LinearToSRGB(float3 c) {
        float3 low  = 12.92f * c;
        float3 high = 1.055f * pow(max(c, 0.0f), 1.0f / 2.4f) - 0.055f;
        float3 mask = step(0.0031308f, c);
        return mix(low, high, mask);
    }

    // Rec.709 / Gamma 2.4 EOTF (Gamma -> Linear)
    inline float3 Rec709ToLinear(float3 v) {
        return pow(max(v, 0.0f), 2.4f);
    }

    // Rec.709 / Gamma 2.4 OETF (Linear -> Gamma)
    inline float3 LinearToRec709(float3 c) {
        return pow(max(c, 0.0f), 1.0f / 2.4f);
    }

    // Generic Gamma
    inline float3 GammaToLinear(float3 v, float gamma) {
        return pow(max(v, 0.0f), gamma);
    }

    inline float3 LinearToGamma(float3 v, float gamma) {
        return pow(max(v, 0.0f), 1.0f / gamma);
    }

    // PQ (ST.2084) Constants
    constant float PQ_m1 = 2610.0f / 16384.0f;
    constant float PQ_m2 = 2523.0f / 32.0f;
    constant float PQ_c1 = 3424.0f / 4096.0f;
    constant float PQ_c2 = 2413.0f / 128.0f;
    constant float PQ_c3 = 2392.0f / 128.0f;

    // PQ EOTF (PQ Code -> Linear Nits)
    // Input: 0-1 PQ code
    // Output: 0-10000 nits
    inline float3 PQToLinearNits(float3 pq) {
        float3 N = pow(max(pq, 0.0f), 1.0f / PQ_m2);
        float3 num = max(N - PQ_c1, 0.0f);
        float3 den = PQ_c2 - PQ_c3 * N;
        float3 L = pow(num / den, 1.0f / PQ_m1);
        return L * 10000.0f;
    }

    // PQ OETF (Linear Nits -> PQ Code)
    // Input: 0-10000 nits
    // Output: 0-1 PQ code
    inline float3 LinearNitsToPQ(float3 nits) {
        float3 Y = nits / 10000.0f;
        float3 L = pow(max(Y, 0.0f), PQ_m1);
        float3 num = PQ_c1 + PQ_c2 * L;
        float3 den = 1.0f + PQ_c3 * L;
        return pow(num / den, PQ_m2);
    }

    // HLG (ARIB STD-B67) Constants
    constant float HLG_a = 0.17883277f;
    constant float HLG_b = 0.28466892f;
    constant float HLG_c = 0.55991073f;

    // HLG EOTF (HLG Code -> Linear)
    // Note: This is the inverse OETF (scene-referred).
    // Display EOTF requires system gamma which is not applied here.
    inline float3 HLGToLinear(float3 hlg) {
        float3 linear;
        for (int i = 0; i < 3; i++) {
            float x = hlg[i];
            if (x <= 0.5f) {
                linear[i] = (x * x) / 3.0f;
            } else {
                linear[i] = (exp((x - HLG_c) / HLG_a) + HLG_b) / 12.0f;
            }
        }
        return linear;
    }

    // HLG OETF (Linear -> HLG Code)
    inline float3 LinearToHLG(float3 linear) {
        float3 hlg;
        for (int i = 0; i < 3; i++) {
            float x = linear[i];
            if (x <= 1.0f/12.0f) {
                hlg[i] = sqrt(3.0f * x);
            } else {
                hlg[i] = HLG_a * log(12.0f * x - HLG_b) + HLG_c;
            }
        }
        return hlg;
    }

    // Apple Log (Placeholder / Approx)
    inline float3 AppleLogToLinear(float3 logv) {
        // R0 = -0.05641088, Rt = 0.01, c = 47.28711236, b = 0.00964052, gamma = 0.65
        float3 linear;
        for(int i=0; i<3; i++) {
            float x = logv[i];
            if (x >= 0.01f) {
                linear[i] = pow(2.0f, (x - 0.00964052f) / 0.244161f) - 0.05641088f;
            } else {
                linear[i] = (x - 0.00964052f) / 47.28711236f;
            }
            linear[i] = max(0.0f, linear[i]);
        }
        return linear;
    }

    inline float3 LinearToAppleLog(float3 linear) {
        // Inverse of above (Approx)
        float3 logv;
        for(int i=0; i<3; i++) {
            float x = linear[i];
            if (x >= 0.0f) { // TODO: Exact threshold
                 logv[i] = 0.244161f * log2(x + 0.05641088f) + 0.00964052f;
            } else {
                 logv[i] = 47.28711236f * x + 0.00964052f;
            }
        }
        return logv;
    }

    // MARK: - Gamut Transforms

    inline float3 applyMatrix(constant float3x3 &m, float3 c) {
        return float3(
            dot(m[0], c),
            dot(m[1], c),
            dot(m[2], c)
        );
    }

    // ACEScg <-> AP0
    inline float3 ACEScgToAP0(float3 acescg) { return applyMatrix(M_ACEScg_to_AP0, acescg); }
    inline float3 AP0ToACEScg(float3 ap0)    { return applyMatrix(M_AP0_to_ACEScg, ap0); }
    
    // ACEScg <-> sRGB / Rec.709
    inline float3 SRGBToACEScg(float3 srgb)   { return applyMatrix(M_Rec709_to_ACEScg, srgb); }
    inline float3 ACEScgToSRGB(float3 acescg) { return applyMatrix(M_ACEScg_to_Rec709, acescg); }
    inline float3 Rec709ToACEScg(float3 r709) { return applyMatrix(M_Rec709_to_ACEScg, r709); }
    inline float3 ACEScgToRec709(float3 acescg){ return applyMatrix(M_ACEScg_to_Rec709, acescg); }
    
    // ACEScg <-> P3-D65
    inline float3 P3D65ToACEScg(float3 p3)    { return applyMatrix(M_P3D65_to_ACEScg, p3); }
    inline float3 ACEScgToP3D65(float3 acescg){ return applyMatrix(M_ACEScg_to_P3D65, acescg); }
    
    // ACEScg <-> Rec.2020
    inline float3 Rec2020ToACEScg(float3 r2020){ return applyMatrix(M_Rec2020_to_ACEScg, r2020); }
    inline float3 ACEScgToRec2020(float3 acescg){ return applyMatrix(M_ACEScg_to_Rec2020, acescg); }
    
    // MARK: - High-Level API

    // Decode texture sample to ACEScg scene-linear
    inline float3 DecodeToACEScg(float3 encodedRGB, int transferFn, int primaries) {
        // 1. Decode transfer function to source linear
        float3 srcLinear;
        switch (transferFn) {
            case TF_SRGB:      srcLinear = SRGBToLinear(encodedRGB); break;
            case TF_REC709:    srcLinear = Rec709ToLinear(encodedRGB); break;
            case TF_PQ:        srcLinear = PQToLinearNits(encodedRGB) / 100.0f; /* 1.0 = 100 nits default scale */ break;
            case TF_HLG:       srcLinear = HLGToLinear(encodedRGB); break;
            case TF_APPLE_LOG: srcLinear = AppleLogToLinear(encodedRGB); break;
            case TF_LINEAR:
            default:           srcLinear = encodedRGB; break;
        }

        // 2. Gamut transform -> ACEScg
        float3 acescg;
        switch (primaries) {
            case PRIM_SRGB:    acescg = Rec709ToACEScg(srcLinear); break;
            // case PRIM_REC709:  acescg = Rec709ToACEScg(srcLinear); break; // Duplicate of PRIM_SRGB
            case PRIM_P3D65:   acescg = P3D65ToACEScg(srcLinear); break;
            case PRIM_REC2020: acescg = Rec2020ToACEScg(srcLinear); break;
            case PRIM_ACESCG:  acescg = srcLinear; break;
            case PRIM_AP0:     acescg = AP0ToACEScg(srcLinear); break;
            default:           acescg = srcLinear; break;
        }

        return acescg;
    }

    // Encode ACEScg scene-linear to display-encoded
    inline float3 EncodeFromACEScg(float3 acescg, int primaries, int transferFn) {
        // 1. Gamut transform from ACEScg to linear destination space
        float3 dstLinear;
        switch (primaries) {
            case PRIM_SRGB:    dstLinear = ACEScgToRec709(acescg); break;
            // case PRIM_REC709:  dstLinear = ACEScgToRec709(acescg); break; // Duplicate of PRIM_SRGB
            case PRIM_P3D65:   dstLinear = ACEScgToP3D65(acescg); break;
            case PRIM_REC2020: dstLinear = ACEScgToRec2020(acescg); break;
            case PRIM_ACESCG:  dstLinear = acescg; break;
            case PRIM_AP0:     dstLinear = ACEScgToAP0(acescg); break;
            default:           dstLinear = acescg; break;
        }

        // 2. Apply transfer function
        float3 encoded;
        switch (transferFn) {
            case TF_SRGB:      encoded = LinearToSRGB(dstLinear); break;
            case TF_REC709:    encoded = LinearToRec709(dstLinear); break;
            case TF_PQ: {
                float3 nits = dstLinear * 100.0f; // 1.0 = 100 nits default
                encoded = LinearNitsToPQ(nits);
                break;
            }
            case TF_HLG:       encoded = LinearToHLG(dstLinear); break;
            case TF_APPLE_LOG: encoded = LinearToAppleLog(dstLinear); break;
            case TF_LINEAR:
            default:           encoded = dstLinear; break;
        }

        return encoded;
    }
    
    // Legacy / Helper aliases for compatibility
    inline float3 srgb_to_linear(float3 srgb) { return SRGBToLinear(srgb); }
    inline float3 linear_to_srgb(float3 linear) { return LinearToSRGB(linear); }
    inline float3 linear_to_pq(float3 linearNits, float maxNits) { return LinearNitsToPQ(linearNits); } // Note: maxNits ignored in new API, assumes input is nits
    inline float3 pq_to_linear(float3 pq, float maxNits) { return PQToLinearNits(pq); }
    inline float3 acescg_to_xyz(float3 acescg) { return applyMatrix(M_ACEScg_to_XYZ, acescg); }
    inline float3 xyz_to_acescg(float3 xyz) { return applyMatrix(M_XYZ_to_ACEScg, xyz); }
    inline float3 xyz_to_rgb(float3 xyz, int standard) {
        if (standard == PRIM_REC709) return applyMatrix(M_XYZ_to_Rec709, xyz);
        if (standard == PRIM_P3D65) return applyMatrix(M_XYZ_to_P3D65, xyz);
        if (standard == PRIM_REC2020) return applyMatrix(M_XYZ_to_Rec2020, xyz);
        return xyz;
    }

} // namespace ColorSpace
} // namespace Core

// Legacy namespace alias for backward compatibility
namespace ColorSpace = Core::ColorSpace;

#endif // COLOR_SPACE_METAL
