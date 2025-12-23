# Shader Review: ColorGrading.metal

**File**: `Sources/MetaVisGraphics/Resources/ColorGrading.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: 3D LUT + Turbo Map
*   **Analysis**:
    *   Applies log-space 3D LUT.
    *   **Math**: `Linear -> ACEScct -> 3D LUT -> Linear`.
*   **M3 Optimization**:
    *   **ALU**: Current math is fine. M3 handles `log2/exp2` quickly.
    *   **Precision**: `half` precision is mandatory here for performance, but ensure it doesn't band in the blacks.
    *   **False Color**: The polynomial map for false color is expensive (5th order). Replace with a 1D Texture Lookup (256px).

## Action Plan
- [ ] **False Color**: Replace math with 1D Texture LUT.
- [ ] **1D Shaper**: Consider passing a precomputed Shaper LUT for the log transform if ALU becomes a bottleneck.
