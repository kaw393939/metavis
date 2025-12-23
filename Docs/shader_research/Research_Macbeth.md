# Research: Macbeth.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Colorimetric Accuracy

## 1. Math
**Data**: Predefined Spectral Reflectances (24 patches).
**Color Space**: Values must be defined in **ACEScg Linear**.
**Conversion**: RGB = Spectral_Integration(Illuminant * Reflectance * Observer).
**Optimization**: Precomputed constant array `float3[24]`.

## 2. Technique: Constant Buffer
**M3 Optimization**:
*   Store colors in `constant` address space (L1 Cache).
*   No ALU calculation needed, just array lookup.

## 3. M3 Architecture
**UV Logic**:
*   Simple grid logic `id.x / width`. Branchless logic preferred but `if/else` is fine for this debug tool.

## Implementation Recommendation
Verify `float3` values against BabelColor 2025 averages for **ACEScg**. Use `constant` memory.
