# Research: Utility Shaders

**Files**:
- `FormatConversion.metal`
- `Watermark.metal`
- `MaskSources.metal`

**Target**: Apple Silicon M3 (Metal 3)

## 1. Format Conversion (`FormatConversion.metal`)
### Optimization
*   **Vector IO**: Use `float4` / `simd` types.
*   **M3**: Unified memory means "Copies" are really just cache flushes if not careful. Ensure this shader is only used when layout *changes* (swizzling), not just deep copying.

## 2. Watermark (`Watermark.metal`)
### Optimization
*   **Branching**: Current has `if (inStripe)`.
*   **M3**: Use `select()` or math: `color *= (1.0 - stride_mask * opacity)`.
*   **Status**: Low priority but easy M3 fix for clarity/pipelining.

## Implementation Plan
1.  **No major changes** needed for correctness.
2.  **Refactor** Watermark to branchless if touching it for other reasons.
