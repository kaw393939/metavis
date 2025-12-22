# Research: ClearColor.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: TBDR Efficiency

## 1. Math & Physics
**Math**: $Pixel(x,y) = Color_{const}$.

## 2. Technique: Render Pass vs Compute
**Current**: A Compute Shaders that writes a constant color to a texture.
**Inefficiency**: Requires spinning up a grid, dispatching threads, and writing via UAV (Unordered Access View). This circumvents the TBDR pipeline optimization.

## 3. M3 Architecture (TBDR)
**Load Actions**:
*   Apple Silicon GPUs are **Tile Based**.
*   The most efficient way to clear a texture is setting `MTLRenderPassDescriptor.colorAttachments[0].loadAction = .clear`.
*   **Hardware**: The tile memory is initialized to the clear color *before* any shader runs. Zero bandwidth cost (metadata clear).

## Implementation Recommendation
**Deprecate Shader**. Use `MTLLoadAction.clear` in the Render Pass.
