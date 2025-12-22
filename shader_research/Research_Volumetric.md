# Research: Volumetric.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Screen-Space Godrays

## 1. Math
**Technique**: Radial Blur from light source position.
**Sampling**: 50-100 taps along vector to Light.

## 2. Technique: Downsampling
**Optimization**:
*   Volumetric lighting is low frequency.
*   Render at 1/2 or 1/4 resolution.
*   Upscale using Bicubic or MetalFX.
*   **Performance**: 16x fewer pixels to shade.

## 3. M3 Architecture
**Tile Memory**:
*   If doing full-res, it's expensive.
*   If using M3, `MTLFXSpatialScaler` is dedicated silicon for upscaling. Use it.

## Implementation Recommendation
Render at **Half-Res**. Upscale via MetalFX.
