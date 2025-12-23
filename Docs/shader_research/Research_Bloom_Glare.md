# Research: Bloom & Glare Shaders

**Files**:
- `Bloom.metal`
- `Halation.metal`
- `Anamorphic.metal`

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Physically Based Energy Conservation

## 1. Bloom (`Bloom.metal`)
### Math & Physics
*   **Current**: Threshold -> Gaussian Blur -> Add.
*   **Problem**: Not energy conserving. Thresholding cuts off data unnaturaly. Gaussian blur is computationally expensive $O(R^2)$ for large radii.
*   **Solution**: **Dual Filtering (Kawase)**.
    *   Downsample pass (4x4 average or 13-tap)
    *   Upsample pass (3x3 or 9-tap tent)
    *   Stack multiple mips.
    *   **Energy Conservation**: $L_{out} = L_{in} + w \cdot L_{bloom}$. Ensure weights sum to < 1.0 generally, or use PBR bloom where bloom is result of scattering.

### M3 Optimization
*   **Downsampling**: Use **Bilinear Hardware Filtering** (`linear` sampler) during the downsample compute/draw.
*   **Memory**: M3 Unified Memory loves "Pyramid" approaches (downsampling) because smaller textures fit in **System Level Cache (SLC)**. Large single-pass blurs flush the cache.

## 2. Halation (`Halation.metal`)
### Math
*   **Phenomenon**: Reflection of light off the film backing (anti-halation layer). Red/Orange scattering.
*   **Technique**: Similar to Bloom but limited to Red channel and tighter radius.
*   **Optimization**:
    *   **Reuse Bloom Mips**: Do not generate a separate pyramid. Sample the *existing* Bloom Mip Level 1 or 2, tint it Red/Orange, and composite.
    *   **Cost**: Reduced from Large Blur to Single Sample.

## 3. Anamorphic (`Anamorphic.metal`)
### Math
*   **Phenomenon**: Cylindrical lens scattering (horizontal streaks).
*   **Technique**:
    *   Isolate brights (Threshold).
    *   **Separable Blur**: Blur *only* horizontally.
*   **M3 Optimization**:
    *   **SIMD Shuffle**: Use `simd_shuffle_xor` to share data horizontally between threads in a threadgroup, effectively blurring without reading global memory 50 times.
    *   **Texture**: Use `read_write` texture to accumulate horizontal passes.

## Implementation Plan
1.  **Refactor Bloom**: Switch to Dual Filter (Kawase) Pyramid.
2.  **Refactor Halation**: Sample from Bloom Pyramid (Level 1) instead of running a separate pass.
3.  **Refactor Anamorphic**: Use Scaled Horizontal Gaussian with SIMD optimizations.
