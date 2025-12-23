# Shader Review: Volumetric.metal

**File**: `Sources/MetaVisGraphics/Resources/Volumetric.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Screen Space God Rays
*   **Analysis**:
    *   Radial blur with 100+ samples.
*   **M3 Optimization**:
    *   **Resolution**: Volumetric light is low frequency. Render at **Half Resolution**.
    *   **Jitter**: Use Blue Noise jitter + Temporal Accumulation to reduce loop count from 100 to 16.
    *   **MetalFX**: Use `MTLFXSpatialScaler` to upscale.

## Action Plan
- [ ] **Optimize**: Reduce sample count, add Jitter/TAA.
- [ ] **Engine**: Render at half-res.
