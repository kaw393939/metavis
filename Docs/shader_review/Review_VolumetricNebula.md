# Shader Review: VolumetricNebula.metal

**File**: `Sources/MetaVisGraphics/Resources/VolumetricNebula.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Hero Shader (Heavy)
*   **Analysis**:
    *   Raymarching 3D Noise volume. Extremely expensive.
*   **M3 Optimization**:
    *   **VRS**: Enable **Variable Rate Shading** (2x2 or 4x4) via `MTLRenderPipelineDescriptor`. Clouds are soft; full 4K shading is wasted.
    *   **Loop Unrolling**: Constant-fold `MAX_STEPS`.

## Action Plan
- [ ] **VRS**: Enable Variable Rate Shading for this pass.
