# Research: Anamorphic.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Efficient Cylindrical Lens Simulation

## 1. Math & Physics
**Physics**: Astigmatism/Cylindrical lens Scattering. Light spreads primarily along the axis perpendicular to the lens cylinder.
**Math**: 1D Gaussian (or Exponential) Blur along the X-axis only, applied to thresholded highlights.

## 2. Technique: Dual Filtering vs Separable
**Current**: Likely a high-radius sampler loop.
**Optimized**:
*   **Separable**: Since it is *only* horizontal, it is already separated.
*   **Kawase**: Not appropriate here; we want a streak, not a box/tent blur.
*   **Importance Sampling**: Focus samples near the center; falloff exponentially.

## 3. M3 Architecture
**Threadgroup Memory (LDS)**:
*   A "Horizontal Blur" is perfect for Threadgroup optimization.
    1.  Load row of pixels into `threadgroup` array.
    2.  `threadgroup_barrier()`.
    3.  Blur using shared memory reads (L1 Speed) instead of VRAM reads (Global Speed).
**SIMD Shuffle**:
*   For small radii (<32), use `simd_shuffle_xor` to share data between threads in the SIMD group.

## Implementation Recommendation
Rewrite to use **Threadgroup Shared Memory** for the horizontal streak pass to minimize VRAM bandwidth.
