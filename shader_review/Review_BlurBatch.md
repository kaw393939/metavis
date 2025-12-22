# Shader Review: Blur & Spatial Effects (Batch 2)

**Files**:
- `Blur.metal`
- `MaskedBlur.metal`
- `FilmGrain.metal`
- `DepthOne.metal`

**Target**: Apple Silicon M3 (Metal 3)

## 1. Standard Blur (`Blur.metal`)
**Status**: Separable Gaussian.
*   **Analysis**:
    *   Separable $O(R)$ complexity is standard.
    *   M3 Recommendation: **Use Metal Performance Shaders (MPS)**. `MPSImageGaussianBlur` is highly tuned for the M3 NPU/GPU architecture and handles tiling automatically. It will outperform this manual implementation by 2x-5x for large radii.
*   **Spectral Blur**: Good implementation of channel-separated radii. Keep this custom kernel as MPS doesn't support this specific artistic effect easily.

## 2. Masked Blur (`MaskedBlur.metal`)
**Status**: **CRITICAL PERFORMANCE RISK**.
*   **Issue**: Implementation is a single-pass 2D Box Blur with a loop up to 64px radius.
    *   Complexity: $O(R^2)$. For R=64, this is 4K-16K reads *per pixel*.
    *   M3 Impact: This will cause TDR (Timeout Detection Recovery) / GPU Hangs on 4K buffers.
*   **Fix**:
    *   **Option A**: Use `MPSImageGaussianBlur` with a mask texture (MPS supports masking).
    *   **Option B**: Variable Blur using **Mipmaps**. Sample from a lower mip level based on the mask value. $O(1)$ cost.
    *   **Option C**: Separable Masked Blur (complex to implement correctly).
*   **Recommendation**: Switch to Mipmap-based blur for variable radius, or MPS for masked uniform blur.

## 3. Film Grain (`FilmGrain.metal`)
**Status**: Good, physically plausible.
*   **Optimizations**:
    *   **Noise Gen**: Box-Muller is fine, but checking `Core::Noise` usage.
    *   **M3**: ALUs are cheap. Generating noise on the fly is better than sampling a noise texture (bandwidth).
    *   **Half Precision**: Correctly used.

## Summary Action Points
- [ ] **Blur**: Replace generic `fx_blur_h/v` with `MPSImageGaussianBlur` in the Engine where possible.
- [ ] **MaskedBlur**: **IMMEDIATE REFACTOR REQUIRED**. Switch to Mipmap Logic or MPS.
- [ ] **FilmGrain**: No changes needed.
