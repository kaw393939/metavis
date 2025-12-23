# Shader Review: Procedural & Volumetric (Batch 3)

**Files**:
- `Procedural.metal` (Core Lib)
- `Noise.metal` (Core Lib)
- `VolumetricNebula.metal` (Heavy Raymatcher)
- `Volumetric.metal` (God Rays)
- `StarField.metal` (Generator)

**Target**: Apple Silicon M3 (Metal 3)

## 1. Volumetric Nebula (`VolumetricNebula.metal`)
**Status**: **Heavy Compute**. "Hero" shader quality.
*   **Analysis**:
    *   Raymarching loop (100+ steps) with 3D Noise (FBM+Warp) per step.
    *   This is the single most expensive shader in the library.
*   **M3 Optimizations**:
    *   **Variable Rate Shading (VRS)**: Nebulae are low-frequency gas clouds. Computing high-octane 4K raymarching is wasteful.
        *   *Recommendation*: Configure the `MTLRenderCommandEncoder` to use 2x2 or 4x4 VRS zones for the nebula pass.
    *   **Half Resolution**: Alternatively, render to a half-res texture and composite with depth-aware upsampling.
    *   **Loop Unrolling**: Ensure `maxSteps` is a compile-time constant (function constant) where possible to allow shader compiler loop unrolling optimizations.

## 2. Core Noise (`Procedural.metal` / `Noise.metal`)
**Status**: Solid ALU-heavy implementation.
*   **Analysis**:
    *   Simplex/Perlin implemented in software.
    *   **M3**: Apple Silicon ALUs are extremely wide. Calculating noise is often faster than texture bandwidth. **Keep as ALU**.
    *   **Gradient Mapping**: `mapToGradient` uses binary search/branching.
        *   *Optimize*: Use a **1D Texture LUT** (1x256 pixel texture) for gradients. Texture sampling hardware handles interpolation for free, replacing 50 lines ofalu/branch code with 1 `sample()` instruction.

## 3. Screen-Space Volumetrics (`Volumetric.metal`)
**Status**: Standard post-process.
*   **Optimization**:
    *   Uses 100 samples in a loop.
    *   *Optimize*: Use **Blue Noise dither** + **Temporal Accumulation (TAA)**. Reduce samples to 16 per frame, jitter the start position, and accumulate over time. M3 has excellent SIMD-group operations to even share samples between neighbors if needed.

## Summary Action Points
- [ ] **Nebula**: Implement VRS (Variable Rate Shading) pipeline state or Half-Res render pass.
- [ ] **Procedural**: Replace `mapToGradient` code with `texture1d` lookups (Texture Unit > ALU for LUTs).
- [ ] **Volumetric**: Reduce sample count and implement blue noise jitter.
