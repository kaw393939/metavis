# Research: SpectralDispersion.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Fast Chromatic Aberration

## 1. Math
**Model**: Radial displacement of R, G, B channels.
$$ R_{pos} = P + v \cdot k_r, \quad G_{pos} = P, \quad B_{pos} = P + v \cdot k_b $$

## 2. Technique: Texture Bandwidth
**Cost**: 3 separate texture samples (expensive).
**Optimization**:
*   If offsets are small (< 1 pixel), use **Texture Gather**? No, gather is for neighborhoods.
*   **Approximation**: Use `dfdx` to approximate color change instead of re-sampling? Too low quality.
*   **Conclusion**: 3 taps is necessary for quality.

## 3. M3 Architecture
**Cache**:
*   Since $k_r, k_b$ are small, the 3 samples are spatially very close. They will likely hit the same L1 Texture Cache line.
*   Performance impact is minimal on M3.

## Implementation Recommendation
Maintain 3-tap approach. Ensure filtering is Bicubic if possible for high quality.
