# Research: FaceMaskGenerator.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Accurate Face Segmentation

## 1. Math
**Current**: Analytical Ellipse Mask based on Rects.
**Problem**: A simple ellipse (oval) is a poor mask for a human face (hairline, jawline, neck).

## 2. Technique: Vision Framework / CoreML
**Optimization**:
*   Procedural generation of a mask from a rect is a last-resort fallback.
*   **Solution**: Use `VNGeneratePersonSegmentationRequest` (Vision Framework) on the NPU (Neural Engine).
*   **Pipeline**: Run Vision Request -> Get mask `CVPixelBuffer` -> Import to Metal -> Blur Edges.

## 3. M3 Architecture
**NPU**:
*   M3 Neural Engine handles segmentation efficiently. Offloads GPU/CPU.
*   **Interops**: Metal-Vision interop is zero-copy if using `IOSurface` backed textures.

## Implementation Recommendation
Move segmentation logic to **Vision Framework** (Swift). Keep this shader only as a debug visualizer for Face Rects.
