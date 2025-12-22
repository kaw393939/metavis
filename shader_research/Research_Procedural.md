# Research: Procedural.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: SDF Efficiency

## 1. Math
**Function**: SDF (Signed Distance Fields) for shapes (Circles, Rects).
**Math**: `length(p) - r`.

## 2. Technique: Antialiasing
**Standard**: `smoothstep(-k, k, dist)`.
**Optimization**: Ensure `k` is calculated based on screen-space derivatives `fwidth(dist)` (OES extension on mobile, but standard in Metal).
*   `float aa = fwidth(dist);`
*   `alpha = 1.0 - smoothstep(-aa, aa, dist);`

## 3. M3 Architecture
**Derivatives**:
*   M3 handles `dfdx` / `dfdy` efficiently in 2x2 quad locks.
*   Using `fwidth` enables perfectly crisp, anti-aliased procedural shapes at any resolution (8K).

## Implementation Recommendation
Update all shape functions to use **Derivative-based Anti-Aliasing**.
