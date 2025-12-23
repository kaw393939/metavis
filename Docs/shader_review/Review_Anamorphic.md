# Shader Review: Anamorphic.metal

**File**: `Sources/MetaVisGraphics/Resources/Anamorphic.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Two-pass Streak Generation
*   **Analysis**:
    *   Currently performs a redundant "Threshold" pass to isolate brights.
    *   This logic likely duplicates the pre-filter of `Bloom.metal`.
*   **M3 Optimization**:
    *   **Memory Bandwidth**: Reading the scene twice (once for Bloom threshold, once for Anamorphic threshold) is wasteful.
    *   **Horizontal SIMD**: The horizontal blur pass can be optimized using Threadgroup memory or SIMD shuffle instructions to avoid VRAM reads.

## Action Plan
- [ ] **Consolidate**: Merge the threshold pass with `fx_bloom_prefilter`.
- [ ] **Optimize**: Usage of `half` precision is recommended for the streak accumulation.
