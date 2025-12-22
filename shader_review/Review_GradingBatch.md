# Shader Review: Grading & Enhance (Batch 4)

**Files**:
- `ColorGrading.metal`
- `MaskedColorGrade.metal`
- `FaceEnhance.metal`
- `FaceMaskGenerator.metal`

**Target**: Apple Silicon M3 (Metal 3)

## 1. Color Grading (`ColorGrading.metal`)
**Status**: Standard 3D LUT + Turbo Map.
*   **Critique**:
    *   `ApplyLUT` performs `Linear -> ACEScct (Log2) -> ACEScct -> Linear (Exp2)` per pixel.
    *   **Optimization**: This logic is correct for cinema grading (LUTs expect Log).
    *   **M3 Optimization**: Precompute a **1D Shaper LUT** (Linear->Log) and pass it as a texture. `sample()` is often faster than `log2()` on some architectures, but on M3 arithmetic is very fast.
    *   *Result*: Keep ALU for now. M3 has massive ALU throughput.
*   **False Color**: Uses a massive polynomial.
    *   *Optimization*: Use a 1D Texture Ramp instead of calculating the 5th-order polynomial per pixel. Saves 50+ FLOPS per pixel.

## 2. Masked Grading (`MaskedColorGrade.metal`)
**Status**: HSL-based selection and modification.
*   **Critique**: Color space conversions (`rgbToHsl`, `hslToRgb`) are expensive branch-heavy functions.
*   **M3 Optimization**: Use **HCV (Hue-Chroma-Value)** model which is branchless and GPU-friendly, instead of HSL.

## 3. Face Enhance (`FaceEnhance.metal`)
**Status**: **Mixed Reliability**.
*   **Issues**:
    *   **Quality**: `bilateralFilter` uses 4 taps. This gives "cross" artifacts and insufficient denoising.
    *   **Architecture**: Filter is applied *inside* the enhancing kernel.
*   **Fix**:
    *   Move skin smoothing to a **Separable Guided Filter** (Edge-Preserving Smooth). Guided Filter is $O(1)$ (independent of radius) and high quality.
    *   Alternatively, use `MPSImageGuidedFilter`.

## Summary Action Points
- [ ] **False Color**: Replace Turbo Polynomial with 1D Texture LUT.
- [ ] **Masked Grade**: Replace HSL with HCV (Hue-Chroma-Value) branchless math.
- [ ] **Face Enhance**: **REPLACE** 4-tap bilateral with `MPSImageGuidedFilter` or a custom Guided Filter kernel.
