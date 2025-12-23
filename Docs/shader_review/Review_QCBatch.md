# Shader Review: QC Fingerprint (`MetaVisQC`)

**File**: `QCFingerprint.metal`
**Target**: Apple Silicon M3 (Metal 3)

## 1. Fingerprint Accumulation (`qc_fingerprint_accumulate_bgra8`)
**Status**: **CRITICAL PERFORMANCE RISK**.
*   **Issue**: Global Atomics for every pixel.
    *   Code: `atomic_fetch_add_explicit(&out->sumR, ri...)` per pixel.
    *   Impact: Massive serialization. On a 4K frame (8M pixels), this causes 8 million atomic collisions on the same memory address. This will stall the GPU execution units completely.
*   **M3 Optimization**:
    *   **Phase 1 (SIMD)**: Use `simd_sum()` to aggregate values within a wave (32 threads).
    *   **Phase 2 (Threadgroup)**: Use `threadgroup` memory to aggregate SIMD results.
    *   **Phase 3 (Global)**: Perform *one* atomic add per threadgroup (e.g., 1 atomic per 1024 pixels instead of 1 per pixel).
    *   *Expected Gain*: 100x+ performance improvement.

## 2. Histogram Generation
**Status**: High Contention.
*   **Issue**: 256-bin histogram using global atomics.
    *   Impact: Standard "histogram atomic" problem.
*   **Optimization**: Use `threadgroup` local histograms, then merge to global.

## Summary Action Points
- [ ] **QC Fingerprint**: **REWRITE REQUIRED**. Implement standard Parallel Reduction (SIMD -> Threadgroup -> Global).
