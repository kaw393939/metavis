# Shader Review: SpectralDispersion.metal

**File**: `Sources/MetaVisGraphics/Resources/SpectralDispersion.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: 3-Tap Separation
*   **Analysis**:
    *   Offsets Red and Blue channels.
*   **Optimization**:
    *   **Texture Gather**: Not applicable here as offsets are > 1 pixel.
    *   **3 Taps**: Necessary cost.
*   **M3 Optimization**:
    *   Ensure the texture sampler uses **Bicubic** filtering if quality is paramount, otherwise Linear is fast.
    *   M3 Texture Cache handles spatially close samples (small dispersion) very well.

## Action Plan
- [ ] **No Changes**: Current implementation is optimal for this effect.
