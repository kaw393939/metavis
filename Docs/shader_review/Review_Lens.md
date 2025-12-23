# Shader Review: Lens.metal

**File**: `Sources/MetaVisGraphics/Resources/Lens.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Standard Brown-Conrady
*   **Analysis**:
    *   Handles distortion and chromatic aberration in one kernel. Efficient.
*   **M3 Optimization**:
    *   **Latency**: The UV calculation depends on dot products, creating a "Dependent Texture Read".
    *   **Sparse Textures**: If rendering at >4K resolution, the distortion implies we only see a subset of the source image. Using Metal's **Sparse Textures** could allow us to only load the visible tiles.
    *   **FP16**: Ensure UV math uses `half` where precision allows (distortions usually need `float` to avoid wobbling).

## Action Plan
- [ ] **Precision**: Verify if `half` precision UVs cause jitter. If not, switch to `half`.
- [ ] **Sampler**: Confirm `s` is `constexpr` for compiler optimization.
