# Shader Review: DepthOne.metal

**File**: `Sources/MetaVisGraphics/Resources/DepthOne.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Utility
*   **Analysis**:
    *   Simply writes `1.0` to the depth buffer.
*   **M3 Optimization**:
    *   **Load Action**: Using a Compute Shader to clear a buffer prevents the TBDR hardware from using its fast-clear metadata optimization.
    *   **Solution**: Use `MTLRenderPassDescriptor.depthAttachment.loadAction = .clear`.

## Action Plan
- [ ] **Deprecate**: Remove this shader usage from the engine. Use Pass Descriptors instead.
