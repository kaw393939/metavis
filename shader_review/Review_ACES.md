# Shader Review: ACES.metal

**File**: `Sources/MetaVisGraphics/Resources/ACES.metal`  
**Reviewer**: Antigravity  
**Target Hardware**: Apple Silicon M3 (Metal 3)  
**Context**: Core Color Management & HDR Tone Mapping

## Overview
This file serves as the central hub for ACES (Academy Color Encoding System) implementation. It currently contains placeholders for RRT (Reference Rendering Transform) sweeteners and simplified ODTs (Output Device Transforms).

## ACES Compliance Gaps
1.  **Sweeteners Missing**: `ACES_glow` and `ACES_red_mod` are placeholders.
    *   *Standard*: ACES 1.x requires specific saturation rolloffs and red-hue modification to prevent "nuclear" colors (especially red/orange) handling.
2.  **HDR ODT Incorrect**: `ACEScg_to_Rec2020_PQ` uses a Reinhard-style curve.
    *   *Standard*: Must use the SSTS (Single Stage Tone Scale) or the segmented spline defined in ACES 1.3 `ODT.Academy.Rec2020_1000nits_15nits_ST2084.ctl`.
3.  **OOTF / RRT Curve**: Uses Stephen Hill's approximation.
    *   *Verdict*: Good for SDR games, but insufficient for "Studio Grade" decoupling of RRT and ODT in HDR workflows.

## Apple Silicon M3 Optimizations

### 1. Vectorized Transfer Functions (SIMD-Friendly)
*   **Current**: `Linear_to_ACEScct` uses `for` loops with `if` branching.
*   **M3 Impact**: Divergent flow control reduces SIMD efficiency.
*   **Fix**: Use `select` or `mix`.
    ```cpp
    // Example: Linear to ACEScct
    // X_BRK = 0.0078125
    float3 is_toe = step(lin, ACEScct_X_BRK);
    float3 toe_seg = ACEScct_A * lin + ACEScct_B;
    float3 log_seg = (log2(lin) + 9.72) / 17.52;
    return mix(log_seg, toe_seg, is_toe); // Branchless
    ```

### 2. Float16 (Half) Usage
*   **Analysis**: `ACEScct` transforms use `half`.
    *   `log2` on `half` has reduced precision. In the darks (ACEScct TOE), this granularity might cause banding when grading.
*   **Recommendation**:
    *   **Compute in Float**: Perform the log math in `float`.
    *   **Store in Half**: Convert to `half` only when writing to the texture.
    *   M3 has dedicated FP32 units that are very fast; saving register pressure with `half` is good, but NOT at the cost of visual artifacting in darks.

### 3. Fused Kernels
*   **Usage**: Functions here are called by `ToneMapping.metal`. All logic is inlined. This is good (compiler optimization).

## Usage in Simulation
*   **Critical Dependencies**: `fx_tonemap_aces`, `fx_apply_lut` (often works in ACEScct).
*   **Refactor Risk**: High. Changing specific curves will alter the look of all existing projects. **Versioned shaders** might be needed if backward compatibility is required.

## Action Plan
- [ ] Implement `ACES_red_mod` (analytical version).
- [ ] Implement `SSD` (Segmented Spline) helper for HDR ODTs.
- [ ] Replace `Rec2020_PQ` tone mapper with the correct spline.
- [ ] Vectorize ACEScct functions.
