# Shader Review: MaskSources.metal

**File**: `Sources/MetaVisGraphics/Resources/MaskSources.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Copy/Resample
*   **Analysis**:
    *   Copies source texture to destination (mask).
*   **M3 Optimization**:
    *   **Blit Engine**: Use `MTLBlitCommandEncoder.copyFromTexture` if dimensions match. This is faster than a compute/render pass.
    *   **Sampler**: Ensure correct sampler (Linker vs Nearest) for mask semantics.

## Action Plan
- [ ] **Engine**: Use Blit Encoder where possible.
