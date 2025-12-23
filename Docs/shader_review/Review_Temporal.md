# Shader Review: Temporal.metal

**File**: `Sources/MetaVisGraphics/Resources/Temporal.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Naive Blend
*   **Analysis**:
    *   Simple blend with previous frame.
    *   **Issue**: Ghosting on moving objects.
*   **M3 Optimization**:
    *   **Velocity**: Must implement Velocity Buffer reading.
    *   **Reprojection**: Sample history at `uv - velocity`.
    *   **MetalFX**: Consider `MTLFXTemporalScaler`.

## Action Plan
- [ ] **Upgrade**: Implement Velocity Buffer Reprojection to fix ghosting.
