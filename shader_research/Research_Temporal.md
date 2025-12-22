# Research: Temporal.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: TAA / Denoising

## 1. Math
**Equation**: Exponential Moving Average with Rectification.
$$ C_{out} = Clamp(Hist(P - V)) \cdot \alpha + C_{in} \cdot (1 - \alpha) $$
**Components**:
*   **Motion Vectors (V)**: Critical for tracking moving objects.
*   **AABB Clamping**: Clamp history to min/max of current neighborhood to prevent ghosting.

## 2. Technique: MetalFX vs Custom
**M3 Optimization**:
*   M3 has `MTLFXTemporalScaler` hardware acceleration hook.
*   If developing custom: Use **Bicubic** sampling for history reprojection to minimize blur.

## 3. M3 Architecture
**Read-Write Textures**:
*   Temporal feedback requires reading the *previous* frame.
*   Ensure utilizing `MTLTextureUsageShaderRead` and proper fencing between frames.

## Implementation Recommendation
Implement **Velocity Reprojection**. Without it, Temporal shaders are useless for animation.
