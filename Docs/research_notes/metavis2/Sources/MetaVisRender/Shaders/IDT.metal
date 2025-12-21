// IDT.metal
// MetaVisRender
//
// Sprint 19: Color Management
// Input Device Transform - Converts any input to Linear ACEScg

#include <metal_stdlib>
using namespace metal;

// =============================================================================
// MARK: - Transfer Function Constants
// =============================================================================

// sRGB constants
constant float SRGB_BREAKPOINT = 0.04045;
constant float SRGB_LINEAR_SCALE = 12.92;
constant float SRGB_GAMMA = 2.4;
constant float SRGB_OFFSET = 0.055;

// Rec.709 / BT.1886 constants
constant float REC709_BREAKPOINT = 0.081;
constant float REC709_LINEAR_SCALE = 4.5;
constant float REC709_GAMMA = 2.4;  // BT.1886 uses 2.4

// PQ (SMPTE ST 2084) constants
constant float PQ_M1 = 0.1593017578125;
constant float PQ_M2 = 78.84375;
constant float PQ_C1 = 0.8359375;
constant float PQ_C2 = 18.8515625;
constant float PQ_C3 = 18.6875;

// HLG (BT.2100) constants
constant float HLG_A = 0.17883277;
constant float HLG_B = 0.28466892;  // 1 - 4 * HLG_A
constant float HLG_C = 0.55991073;  // 0.5 - HLG_A * log(4 * HLG_A)

// ARRI LogC3 constants (EI 800)
constant float LOGC3_CUT = 0.010591;
constant float LOGC3_A = 5.555556;
constant float LOGC3_B = 0.052272;
constant float LOGC3_C = 0.247190;
constant float LOGC3_D = 0.385537;
constant float LOGC3_E = 5.367655;
constant float LOGC3_F = 0.092809;

// Sony S-Log3 constants
// Based on Sony S-Log3 Technical Summary Ver 1.0
constant float SLOG3_A = 0.2556207251; // 261.5 / 1023
constant float SLOG3_B = 0.4105571848; // 420 / 1023
constant float SLOG3_C = 0.01;
constant float SLOG3_D = 0.19;         // 0.18 + 0.01
constant float SLOG3_CUT = 0.1673609332; // 171.2102946929 / 1023
constant float SLOG3_LIN_SLOPE = 82488.8888888889; // (1023-95)/0.01125
constant float SLOG3_LIN_OFFSET = 95.0;

// =============================================================================
// MARK: - Color Space Enums (must match Swift ColorPrimaries/TransferFunction)
// =============================================================================

enum ColorPrimaries : uint {
    Rec709 = 0,
    P3 = 1,
    Rec2020 = 2,
    ACEScg = 3,
    ACES = 4
};

enum TransferFunction : uint {
    Linear = 0,
    SRGB = 1,
    Rec709TF = 2,
    PQ = 3,
    HLG = 4,
    LogC3 = 5,
    SLog3 = 6,
    AppleLog = 7
};


// =============================================================================
// MARK: - EOTF (Electro-Optical Transfer Functions)
// =============================================================================

/// Linearize sRGB encoded value
inline float linearize_sRGB(float x) {
    if (x <= SRGB_BREAKPOINT) {
        return x / SRGB_LINEAR_SCALE;
    } else {
        return pow((x + SRGB_OFFSET) / (1.0 + SRGB_OFFSET), SRGB_GAMMA);
    }
}

inline float3 linearize_sRGB(float3 rgb) {
    return float3(
        linearize_sRGB(rgb.r),
        linearize_sRGB(rgb.g),
        linearize_sRGB(rgb.b)
    );
}

/// Linearize Rec.709 / BT.1886 encoded value
inline float linearize_rec709(float x) {
    if (x < REC709_BREAKPOINT) {
        return x / REC709_LINEAR_SCALE;
    } else {
        return pow((x + 0.099) / 1.099, REC709_GAMMA);
    }
}

inline float3 linearize_rec709(float3 rgb) {
    return float3(
        linearize_rec709(rgb.r),
        linearize_rec709(rgb.g),
        linearize_rec709(rgb.b)
    );
}

/// Linearize PQ (SMPTE ST 2084) encoded value
/// Returns linear light in cd/m² (nits), normalized to 10000 nits peak
inline float linearize_pq(float x) {
    float Np = pow(x, 1.0 / PQ_M2);
    float num = max(Np - PQ_C1, 0.0);
    float den = PQ_C2 - PQ_C3 * Np;
    return pow(num / den, 1.0 / PQ_M1);
}

inline float3 linearize_pq(float3 rgb) {
    return float3(
        linearize_pq(rgb.r),
        linearize_pq(rgb.g),
        linearize_pq(rgb.b)
    );
}

/// Linearize HLG (Hybrid Log-Gamma) encoded value
inline float linearize_hlg(float x) {
    if (x <= 0.5) {
        return (x * x) / 3.0;
    } else {
        return (exp((x - HLG_C) / HLG_A) + HLG_B) / 12.0;
    }
}

inline float3 linearize_hlg(float3 rgb) {
    return float3(
        linearize_hlg(rgb.r),
        linearize_hlg(rgb.g),
        linearize_hlg(rgb.b)
    );
}

/// Linearize ARRI LogC3 (EI 800)
inline float linearize_logC3(float x) {
    if (x > LOGC3_E * LOGC3_CUT + LOGC3_F) {
        return (pow(10.0, (x - LOGC3_D) / LOGC3_C) - LOGC3_B) / LOGC3_A;
    } else {
        return (x - LOGC3_F) / LOGC3_E;
    }
}

inline float3 linearize_logC3(float3 rgb) {
    return float3(
        linearize_logC3(rgb.r),
        linearize_logC3(rgb.g),
        linearize_logC3(rgb.b)
    );
}

/// Linearize Sony S-Log3
inline float linearize_slog3(float x) {
    if (x >= SLOG3_CUT) {
        return pow(10.0, (x - SLOG3_B) / SLOG3_A) * SLOG3_D - SLOG3_C;
    } else {
        return (x * 1023.0 - SLOG3_LIN_OFFSET) / SLOG3_LIN_SLOPE;
    }
}

inline float3 linearize_slog3(float3 rgb) {
    return float3(
        linearize_slog3(rgb.r),
        linearize_slog3(rgb.g),
        linearize_slog3(rgb.b)
    );
}

/// Linearize Apple Log
/// Based on Apple Log Profile White Paper
inline float linearize_appleLog(float x) {
    // R0 = -0.05641088
    // Rt = 0.01
    // c = 47.28711236
    // b = 0.00964052
    // gamma = 0.65 (not used in inverse?)
    
    if (x >= 0.01) {
        return pow(2.0, (x - 0.00964052) / 0.244161) - 0.05641088;
    } else {
        return (x - 0.00964052) / 47.28711236;
    }
}

inline float3 linearize_appleLog(float3 rgb) {
    return float3(
        linearize_appleLog(rgb.r),
        linearize_appleLog(rgb.g),
        linearize_appleLog(rgb.b)
    );
}


// =============================================================================
// MARK: - Primaries Conversion Matrices
// =============================================================================
// NOTE: Metal uses COLUMN-major storage for float3x3.
// When constructing with float3x3(float3, float3, float3), each float3 is a COLUMN.
// For matrix * vector multiplication to work correctly, these matrices are TRANSPOSED
// from the standard row-major color science notation.

/// Rec.709 to ACEScg (AP1) matrix - TRANSPOSED for Metal column-major storage
/// Standard row-major: [[0.613, 0.340, 0.047], [0.070, 0.916, 0.013], [0.021, 0.110, 0.870]]
constant float3x3 REC709_TO_ACESCG = float3x3(
    float3(0.6131324224, 0.0701934641, 0.0205844026),  // Column 0
    float3(0.3395380158, 0.9163940189, 0.1095745716),  // Column 1
    float3(0.0473295618, 0.0134125170, 0.8698410258)   // Column 2
);

/// P3-D65 to ACEScg (AP1) matrix - TRANSPOSED for Metal column-major storage
constant float3x3 P3_TO_ACESCG = float3x3(
    float3(0.7552984714, 0.0538656600, -0.0092892530),  // Column 0
    float3(0.1989753246, 0.9432320991,  0.0175662269),  // Column 1
    float3(0.0457262040, 0.0029022409,  0.9917230261)   // Column 2
);

/// Rec.2020 to ACEScg (AP1) matrix - TRANSPOSED for Metal column-major storage
constant float3x3 REC2020_TO_ACESCG = float3x3(
    float3(0.9752692986, 0.0170327418, -0.0025241304),  // Column 0
    float3(0.0193603288, 0.9777882457,  0.0037378438),  // Column 1
    float3(0.0053703726, 0.0051790125,  0.9987862866)   // Column 2
);

/// ACES AP0 to ACEScg (AP1) matrix - TRANSPOSED for Metal column-major storage
constant float3x3 ACES_TO_ACESCG = float3x3(
    float3( 1.4514393161, -0.0765537734, 0.0083161484),  // Column 0
    float3(-0.2365107469,  1.1762296998, -0.0060324498), // Column 1
    float3(-0.2149285693, -0.0996759264,  0.9977163014)  // Column 2
);


// =============================================================================
// MARK: - Main IDT Kernel
// =============================================================================

/// Input Device Transform - converts any input to Linear ACEScg
kernel void cs_idt_transform(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant uint& sourcePrimaries [[buffer(0)]],
    constant uint& sourceTransfer [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
        return;
    }
    
    // Read input pixel
    float4 pixel = inTexture.read(gid);
    float3 rgb = pixel.rgb;
    
    // Step 1: Linearize (apply EOTF)
    float3 linear;
    switch (TransferFunction(sourceTransfer)) {
        case Linear:
            linear = rgb;
            break;
        case SRGB:
            linear = linearize_sRGB(rgb);
            break;
        case Rec709TF:
            linear = linearize_rec709(rgb);
            break;
        case PQ:
            linear = linearize_pq(rgb);
            break;
        case HLG:
            linear = linearize_hlg(rgb);
            break;
        case LogC3:
            linear = linearize_logC3(rgb);
            break;
        case SLog3:
            linear = linearize_slog3(rgb);
            break;
        case AppleLog:
            linear = linearize_appleLog(rgb);
            break;
    }
    
    // Step 2: Convert primaries to ACEScg
    float3 acescg;
    switch (ColorPrimaries(sourcePrimaries)) {
        case Rec709:
            acescg = REC709_TO_ACESCG * linear;
            break;
        case P3:
            acescg = P3_TO_ACESCG * linear;
            break;
        case Rec2020:
            acescg = REC2020_TO_ACESCG * linear;
            break;
        case ACEScg:
            acescg = linear;  // Already in ACEScg
            break;
        case ACES:
            acescg = ACES_TO_ACESCG * linear;
            break;
    }
    
    // Write output (Linear ACEScg)
    outTexture.write(float4(acescg, pixel.a), gid);
}


// =============================================================================
// MARK: - ODT Kernels (Output Device Transform)
// =============================================================================

/// Apply sRGB OETF (inverse of EOTF)
inline float encode_sRGB(float x) {
    if (x <= 0.0031308) {
        return x * SRGB_LINEAR_SCALE;
    } else {
        return (1.0 + SRGB_OFFSET) * pow(x, 1.0 / SRGB_GAMMA) - SRGB_OFFSET;
    }
}

inline float3 encode_sRGB(float3 rgb) {
    return float3(
        encode_sRGB(rgb.r),
        encode_sRGB(rgb.g),
        encode_sRGB(rgb.b)
    );
}

/// Apply Rec.709 OETF
inline float encode_rec709(float x) {
    if (x < 0.018) {
        return x * REC709_LINEAR_SCALE;
    } else {
        return 1.099 * pow(x, 1.0 / REC709_GAMMA) - 0.099;
    }
}

inline float3 encode_rec709(float3 rgb) {
    return float3(
        encode_rec709(rgb.r),
        encode_rec709(rgb.g),
        encode_rec709(rgb.b)
    );
}

/// Apply PQ OETF
inline float encode_pq(float x) {
    float Lm = pow(x, PQ_M1);
    return pow((PQ_C1 + PQ_C2 * Lm) / (1.0 + PQ_C3 * Lm), PQ_M2);
}

inline float3 encode_pq(float3 rgb) {
    return float3(
        encode_pq(rgb.r),
        encode_pq(rgb.g),
        encode_pq(rgb.b)
    );
}

/// ACEScg (AP1) to Rec.709 matrix - TRANSPOSED for Metal column-major storage
/// Standard row-major: [[1.705, -0.622, -0.083], [-0.130, 1.141, -0.011], [-0.024, -0.129, 1.153]]
constant float3x3 ACESCG_TO_REC709 = float3x3(
    float3( 1.7050509310, -0.1302564950, -0.0240033570),  // Column 0
    float3(-0.6217921210,  1.1408047740, -0.1289689740),  // Column 1
    float3(-0.0832588100, -0.0105482790,  1.1529723310)   // Column 2
);

/// ACEScg (AP1) to P3-D65 matrix - TRANSPOSED for Metal column-major storage
constant float3x3 ACESCG_TO_P3 = float3x3(
    float3(1.3434094292, -0.0653203441,  0.0028161583),  // Column 0
    float3(-0.2820294141, 1.0757827759, -0.0195617718),  // Column 1
    float3(-0.0613800152, -0.0104624318, 1.0167456135)   // Column 2
);

/// ACEScg (AP1) to Rec.2020 matrix - TRANSPOSED for Metal column-major storage
constant float3x3 ACESCG_TO_REC2020 = float3x3(
    float3(1.0258246660, -0.0178571150,  0.0025862681),  // Column 0
    float3(-0.0200052287, 1.0228070989, -0.0038143971),  // Column 1
    float3(-0.0058194373, -0.0049499839, 1.0012281290)   // Column 2
);


/// Output Device Transform - converts Linear ACEScg to display space
kernel void cs_odt_transform(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant uint& destPrimaries [[buffer(0)]],
    constant uint& destTransfer [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Bounds check
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) {
        return;
    }
    
    // Read input (Linear ACEScg)
    float4 pixel = inTexture.read(gid);
    float3 acescg = pixel.rgb;
    
    // Step 1: Convert primaries from ACEScg
    float3 linear;
    switch (ColorPrimaries(destPrimaries)) {
        case Rec709:
            linear = ACESCG_TO_REC709 * acescg;
            break;
        case P3:
            linear = ACESCG_TO_P3 * acescg;
            break;
        case Rec2020:
            linear = ACESCG_TO_REC2020 * acescg;
            break;
        case ACEScg:
            linear = acescg;
            break;
        case ACES:
            // Inverse of ACES_TO_ACESCG (not commonly used for output)
            linear = acescg;
            break;
    }
    
    // Clamp to valid range before encoding (prevents NaN from negative values)
    linear = max(linear, float3(0.0));
    
    // Step 2: Apply OETF
    float3 encoded;
    switch (TransferFunction(destTransfer)) {
        case Linear:
            encoded = linear;
            break;
        case SRGB:
            encoded = encode_sRGB(linear);
            break;
        case Rec709TF:
            encoded = encode_rec709(linear);
            break;
        case PQ:
            encoded = encode_pq(linear);
            break;
        case HLG:
            // Simplified HLG encode
            encoded = pow(linear, float3(1.0 / 1.2));  // Approximate
            break;
        default:
            encoded = linear;
            break;
    }
    
    // Clamp to 0-1 for display
    encoded = saturate(encoded);
    
    // Write output
    outTexture.write(float4(encoded, pixel.a), gid);
}
