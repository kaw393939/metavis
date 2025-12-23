# Shader Review: Bloom.metal

**File**: `Sources/MetaVisGraphics/Resources/Bloom.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Strong Implementation
*   **Analysis**:
    *   Dual Filter downsample / Golden Angle upsample is a high-quality choice.
    *   Energy conservation logic appears plausible.
*   **M3 Optimization**:
    *   **Tile Memory**: The final composition (`fx_bloom_composite`) reads source + bloom and writes dest. This is a classic "Additive Blend" scenario.
    *   It should be implemented as a **Fragment Shader** with **Programmable Blending** enabled to avoid reading the Destination texture from VRAM.

## Action Plan
- [ ] **Refactor**: Move Composite pass to Raster Pipeline (Programmable Blending).
- [ ] **Bandwidth**: Ensure intermediate pyramid textures use `private` storage mode if possible, or at least compressed formats.
