# Research: FaceEnhance.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Studio-Quality Skin Smoothing

## 1. Math & Physics
**Status**: 4-tap Bilateral Filter.
**Problem**: Low sample count leads to "posterization" or "cross" artifacts. Bilateral filters are $O(R^2)$ if exact.
**Solution**: **Guided Filter** (He et al.).
*   **Math**: Local linear model. Edge-preserving smoothing that is $O(1)$ (independent of radius).
*   Reference: `box_filter_mean` and `box_filter_covariance`.

## 2. Technique: Separable Guided Filter
**Algorithm**:
1.  Mean(I), Mean(P), Mean(I*P), Mean(I*I) using box blurs (or MPS).
2.  Calculate $a$ and $b$ coefficients.
3.  Mean(a), Mean(b).
4.  Reconstruct: $q = \bar{a} \cdot I + \bar{b}$.

## 3. M3 Architecture
**MPS**:
*   `MPSImageGuidedFilter` exists and is highly optimized.
*   If custom: Use Separable Box Blur optimization (Horizontal pass then Vertical pass).

## Implementation Recommendation
Replace manual loop with **`MPSImageGuidedFilter`** or implement a custom Separable Guided Filter.
