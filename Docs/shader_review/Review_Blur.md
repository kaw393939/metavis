# Shader Review: Blur.metal

**File**: `Sources/MetaVisGraphics/Resources/Blur.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Custom Separable Blur
*   **Analysis**:
    *   Standard Two-Pass separable Gaussian.
    *   $O(R)$ complexity. All generic implementations suffer memory bandwidth bottlenecks.
*   **M3 Optimization**:
    *   **MPS**: Apple's `MPSImageGaussianBlur` is tuned for the M3's specific cache hierarchy and NPU/GPU coop capabilities.
    *   **Performance**: Expect MPS to be 2x-5x faster than this custom kernel for $R>32$.

## Action Plan
- [ ] **Replace**: Switch Swift engine to use `MPSImageGaussianBlur` for standard blurs.
- [ ] **Keep**: Retain `Blur.metal` only for specialized "Spectral" or "Directional" blurs not supported by MPS.
