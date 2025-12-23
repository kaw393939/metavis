# Shader Review: MaskedBlur.metal

**File**: `Sources/MetaVisGraphics/Resources/MaskedBlur.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: CRITICAL PERFORMANCE RISK
*   **Analysis**:
    *   Single-pass 2D Loop with variable radius.
    *   **Complexity**: $O(R^2)$. At 64px radius, this reads 16,000 texels per pixel.
    *   **Result**: Will cause GPU Timeout (TDR) at 4K resolution.
*   **M3 Optimization**:
    *   **Mipmap Interpolation**: Generate Mips of the source image. Sample `source.sample(s, uv, level(maskVal * maxLOD))`.
    *   **Cost**: $O(1)$. One single trilinear fetch.

## Action Plan
- [ ] **REWRITE**: Immediately replace loop with Mipmap Level Sampling.
