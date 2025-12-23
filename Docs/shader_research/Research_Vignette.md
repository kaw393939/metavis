# Research: Vignette.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Natural Falloff

## 1. Math
**Function**: $\cos^4(\theta)$ or simple Radial polynomial $1 - kr^2$.
**Space**: Screen Space UV.

## 2. Technique: Pass Integration
**Optimization**:
*   Running a full-screen pass *just* for Vignette is wasteful (Bandwidth).
*   **Solution**: Inline the Vignette multiplication into the **Vignette + ToneMap + Dither** final pass.
*   Combine these lightweight ALUs into one shader.

## 3. M3 Architecture
**Bandwidth Limited**:
*   8K composition is memory bound. Reducing pass count by fusing shaders (Uber-shader approach) is strictly better.

## Implementation Recommendation
Fuse `Vignette` logic into `ToneMapping` kernel.
