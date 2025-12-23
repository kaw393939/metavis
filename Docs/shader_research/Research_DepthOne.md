# Research: DepthOne.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Minimal Overhead

## 1. Math
**Function**: Set Depth = 1.0 (Far Plane).

## 2. Technique: Clear vs Compute
**Current**: Compute shader setting value.
**Optimization**:
*   Just like `ClearColor`, this is best handled by the Rasterizer's **Load Action**.
*   `MTLRenderPassDescriptor.depthAttachment.loadAction = .clear`.
*   `clearDepth = 1.0`.

## 3. M3 Architecture
**Hi-Z / Z-Buffer Compression**:
*   Setting loadAction to `.clear` allows the Tile Hardware to mark the Z-Buffer tile as "Cleared" in metadata without writing bytes to memory.
*   A Compute Shader manually writing 1.0 forces a full memory write and decompresses the buffer.

## Implementation Recommendation
**Deprecate Shader**. Use `loadAction = .clear` in the Render Pass configuration.
