# Research: FormatConversion.metal

**Target**: Apple Silicon M3 (Metal 3)
**Goal**: Bandwidth Saturation

## 1. Math
**Operation**: RGBA -> BGRA or similar channel swizzles.

## 2. Technique: Vectorized Loads
**Code**:
```metal
// Good
float4 px = tex.read(gid);
out.write(px.bgra, gid);
```
**Architecture**:
*   M3 Load/Store units are optimized for 128-bit aligned access.
*   Ensure texture formats are 16-bit (`half4`) or 32-bit (`float4`) aligned to maximize throughput.

## 3. M3 Architecture
**TextureView**:
*   Metal supports `makeTextureView(pixelFormat: .bgra8Unorm)` on an `rgba8Unorm` texture.
*   **Zero Cost**: This allows the hardware to swizzle on the fly during the sample/write, requiring **no compute shader at all**.

## Implementation Recommendation
Check if `MTLTexture.makeTextureView` can solve the conversion. If not, use vectorized compute.
