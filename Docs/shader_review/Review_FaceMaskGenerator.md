# Shader Review: FaceMaskGenerator.metal

**File**: `Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Analytical Ellipse
*   **Analysis**:
    *   Generates an oval mask from a rect.
    *   **Quality**: Poor approximation of a face.
*   **M3 Optimization**:
    *   **NPU**: Use the **Vision Framework** (`VNGeneratePersonSegmentationRequest`). It runs on the Neural Engine (ANE) and generates a pixel-perfect mask.
    *   **Interop**: Pass the Vision mask to Metal as a texture.

## Action Plan
- [ ] **Engine**: Move segmentation logic to Vision Framework. Use shader only for debug visualization.
