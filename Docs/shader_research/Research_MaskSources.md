# Research: MaskSources.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Pass-through Efficiency

## 1. Math
**Function**: Resample/Copy mask data to render target.

## 2. Technique: Sampler States
**Issue**: Masks are often binary (0 or 1). Linear filtering creates gray edges (0.5), which can be good (AA) or bad (Semantic Segmentation).
**Strategy**: Expose `MTLSamplerState` toggle for `nearest` vs `linear`.

## 3. M3 Architecture
**Bandwidth**:
*   If this shader just copies `Texture A -> Texture B`, it can likely be replaced by a **Blit Command Encoder** (`copyFromTexture`).
*   Blit engines on M3 operate asynchronously from Compute/Render pipes.

## Implementation Recommendation
Check if simple copy. If so, use `MTLBlitCommandEncoder`. If Resizing/Resampling needed, keep shader but ensure correct Sampler.
