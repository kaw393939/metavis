# Research: MaskedBlur.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Variable Blur without O(R^2) cost

## 1. Math
**Problem**: We need a blur radius $r$ that changes *per pixel* based on a Mask Texture.
**Naive**: `for x in -r...r` where `r` comes from mask. Warp Divergence hell. $O(R^2)$.

## 2. Technique: Mipmap Interpolation ($O(1)$)
**Solution**:
1.  **Generate Mip Pyramid** of the source image.
2.  **Sample**:
    *   `float maskVal = maskTex.sample(s, uv).r;`
    *   `float lod = maskVal * MAX_LOD;`
    *   `color = sourceTex.sample(s, uv, level(lod));`
**Result**: Hardware trilinear interpolation blends between Mip levels (Blur radii). Cost is constant (1 fetch).

## 3. M3 Architecture
**Texture Units**:
*   M3 has dedicated hardware for Mip LOD blending.
*   This is the single biggest optimization possible in the review.

## Implementation Recommendation
**Total Rewrite**. Use `level()` sampler based on mask value.
