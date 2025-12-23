# Shader Review: ClearColor.metal

**File**: `Sources/MetaVisGraphics/Resources/ClearColor.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Utility
*   **Analysis**:
    *   Computes a constant color fill.
*   **M3 Optimization**:
    *   **TBDR**: Writing every pixel prevents the Tile Hardware from using its fast-clear metadata optimization.
    *   **Load Action**: Use `MTLRenderPassDescriptor.colorAttachments[0].loadAction = .clear`. This is zero-bandwidth.

## Action Plan
- [ ] **Deprecate**: Remove shader. Use Render Pass configuration.
