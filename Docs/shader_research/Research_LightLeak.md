# Research: LightLeak.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Organic Overlay

## 1. Math
**Technique**: Additive color overlays (gradients, blobs).
**Procedural**: Generating gradients on the fly.

## 2. Technique: Low-Res Generation
**Optimization**:
*   Light leaks are by definition out-of-focus and low frequency.
*   **Strategy**: Generate the Light Leak on a tiny texture (e.g., 512x512) or even 256x256.
*   **Composite**: Upscale linearly during the add pass.

## 3. M3 Architecture
**ALU Utilization**:
*   Generating procedural gradients for 33 million pixels (8K) is a waste of ALU.
*   Generating for 0.2 million pixels (512p) is instant.

## Implementation Recommendation
Render Light Leak to a **Small Intermediate Texture**, then composite.
