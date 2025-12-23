# Research: Halation.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Efficient Red-Scatter

## 1. Math & Physics
**Physics**: Light penetrating film layers, reflecting off anti-halation backing, scattering as Red/Orange.
**Math**: Convolution (Blur) of highlights, tinted Red.

## 2. Technique: Reuse Bloom
**Optimization**:
*   Calculating a separate Blur pass for Halation is wasteful ($O(R^2)$ or multiple passes).
*   **Reuse**: Bloom already generates a Gaussian Pyramid.
*   **Strategy**: Sample Bloom Mip Level 1 or 2 (medium radius). Tint it Red in the Composite pass.

## 3. M3 Architecture
**Bandwidth**:
*   Reusing the Bloom texture saves reading/writing an entire separate 8K buffer. M3 Unified Memory bandwidth is high but finite.

## Implementation Recommendation
**Remove standalone pass**. Integrate Halation sampling into the final `Compositor` or `Bloom` merge pass by sampling the existing Bloom Mips.
