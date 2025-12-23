# Shader Review: FormatConversion.metal

**File**: `Sources/MetaVisGraphics/Resources/FormatConversion.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Channel Swizzle
*   **Analysis**:
    *   Reorders channels (RGBA <-> BGRA).
*   **M3 Optimization**:
    *   **TextureView**: Metal supports `makeTextureView(pixelFormat: ...)` which can reinterpret formats or swizzle without a copy kernel.
    *   **Vectorize**: If kernel is needed, ensure `float4` read/writes (128-bit aligned).

## Action Plan
- [ ] **Engine**: Investigate replacing with `makeTextureView`.
