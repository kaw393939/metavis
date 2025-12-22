# Research: QC Fingerprint

**File**: `QCFingerprint.metal`
**Target**: Apple Silicon M3 (Metal 3)

## 1. Mathematical Model (Parallel Reduction)
### Current State
Global Atomic Add per pixel.
*   **Contention**: Massive. 8 million threads fighting for 1 memory address.

### The Solution (Multi-Stage Reduction)
Implement standard GPU reduction.
1.  **Wave Level**: `simd_sum()` (sum 32 threads in registers).
2.  **group Level**: `threadgroup_barrier()` + shared memory sum (sum 1024 threads in L1).
3.  **Global Level**: 1 Atomic Add per Threadgroup.
*   **Reduction Factor**: 1024x fewer global atomics.

## 2. M3 Architecture
*   **SIMD Scoped Ops**: M3 has highly efficient `simd_sum`, `simd_max` instructions.
*   **Threadgroup Memory**: Fast on-chip memory (Imageblock memory) can be reused for compute threadgroup storage.

## Implementation Plan
1.  **Rewrite** `qc_fingerprint_accumulate` to use `simd_sum` + `threadgroup` accumulation.
