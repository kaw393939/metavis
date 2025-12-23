# Research: MaskedColorGrade.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Efficient Selective Color

## 1. Math
**Model**: Hue-Saturation selection (Color Key).
**Math**: Distance in Cylinder space (HSL/HSV).
**Improved**: **HCV (Hue-Chroma-Value)**. A purely branchless model compared to HSL.

## 2. Technique: Branchless Color Keying
**M3 Optimization**:
*   Avoid `rgb2hsl` which has many `if` checks.
*   Use analytical distance: $Dist = length(vec2(Cb, Cr) - Target(Cb, Cr))$.

## 3. M3 Architecture
**SIMD**:
*   Branchless logic keeps SIMD utilization at 100%.
*   Use `mix()` for blending the graded result with original based on mask alpha.

## Implementation Recommendation
Switch color space math to **HCV** or **Lab** (more perceptual) using branchless GLSL-ported implementations.
