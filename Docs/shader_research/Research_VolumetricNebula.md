# Research: VolumetricNebula.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: 60fps 4K Clouds

## 1. Math
**Technique**: Raymarching 3D Noise (FBM).
**Cost**: Steps * NoiseOctaves. Extremely Expensive.

## 2. Technique: Variable Rate Shading (VRS)
**M3 Optimization**:
*   Clouds do not have high-frequency edges.
*   **VRS**: Configure Raster pipeline to shade 2x2 or 4x4 pixel blocks as one fragment.
*   **Gain**: 4x-16x Speedup.

## 3. Technique: Early Ray Termination
**Logic**:
*   Accumulate density `alpha`.
*   `if (alpha >= 0.99) break;`
*   Reduces overdraw within the volume.

## Implementation Recommendation
Enable **Variable Rate Shading (VRS)** on the Nebula render pipeline.
