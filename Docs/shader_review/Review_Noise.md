# Shader Review: Noise.metal

**File**: `Sources/MetaVisGraphics/Resources/Noise.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: ALU implementation
*   **Analysis**:
    *   Simplex/Perlin noise in software.
    *   **Gradient Mapping**: `mapToGradient` uses binary search logic.
*   **M3 Optimization**:
    *   **LUT**: Replace Gradient mapping with a **1D Texture** lookup.
    *   **3D Noise**: For heavy FBM, consider using a **3D Noise Texture** instead of calculating Simplex 8 times/pixel. M3 L1 Cache makes texture fetches very cheap compared to 400 ALU ops.

## Action Plan
- [ ] **Optimize**: Replace `mapToGradient` with Texture lookup.
