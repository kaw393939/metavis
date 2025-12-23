# Shader Review: FaceEnhance.metal

**File**: `Sources/MetaVisGraphics/Resources/FaceEnhance.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Bilateral Filter (Mixed Quality)
*   **Analysis**:
    *   Uses a 4-tap Bilateral Filter for skin smoothing.
    *   **Result**: 4 taps is too few. Cross artifacts visible.
*   **M3 Optimization**:
    *   **Guided Filter**: A Guided Filter (He et al) preserves edges better and is $O(1)$ independent of radius.
    *   **MPS**: `MPSImageGuidedFilter` exists and is highly optimized.

## Action Plan
- [ ] **Replace**: Switch to `MPSImageGuidedFilter` or implement a separable high-quality Guided Filter.
