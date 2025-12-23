# Shader Review: FilmGrain.metal

**File**: `Sources/MetaVisGraphics/Resources/FilmGrain.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Physically Plausible
*   **Analysis**:
    *   Uses Box-Muller or Hash noise.
    *   Correctly applies luminance-dependent gain (less grain in highlights).
*   **M3 Optimization**:
    *   **ALU**: M3 has massive ALU throughput. Generating noise on the fly is often better than eating Texture Bandwidth.
    *   **Half**: Ensure all calculations use `half`. Noise doesn't need 32-bit precision.

## Action Plan
- [ ] **Maintain**: Current implementation is good.
- [ ] **Optional**: Switch to 3D Blue Noise Texture if "organic" quality needs improvement.
