# Research: Blur.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Maximum Throughput

## 1. Math & Physics
**Math**: Convolution with a Gaussian Kernel $G(x,y) = \frac{1}{2\pi\sigma^2} e^{-(x^2+y^2)/2\sigma^2}$.
**Performance**: Separable ($X$ then $Y$) reduces $O(R^2)$ to $O(2R)$.

## 2. Technique: MPS vs Custom
**Research Finding**:
*   **MPSImageGaussianBlur**: Apple's own implementation in Metal Performance Shaders.
*   **Performance**: Tuned to the exact register pressure and cache sizes of the M3. Almost impossible to beat with custom MSL unless simplifying assumptions (like fixed radius) are made.

## 3. M3 Architecture
**NPU/ANE**:
*   While typically for ML, MPS often uses undocumented hardware paths or optimal threadgroup configurations for convolution.

## Implementation Recommendation
**Delete custom kernel**. Hook up `MPSImageGaussianBlur` in the Swift engine.
