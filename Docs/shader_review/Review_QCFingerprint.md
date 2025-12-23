# Shader Review: QCFingerprint.metal

**File**: `Sources/MetaVisQC/Resources/QCFingerprint.metal`
**Target**: Apple Silicon M3 (Metal 3)

## Status: Critical Contention
*   **Analysis**:
    *   Uses Global Atomics for every pixel.
    *   **Result**: Massive stalling.
*   **M3 Optimization**:
    *   **Reduction**:
        1.  SIMD Sum (`simd_sum`).
        2.  Threadgroup Sum (`threadgroup memory`).
        3.  Device Sum (1 atomic per 1024 pixels).

## Action Plan
- [ ] **REWRITE**: Implement multi-stage Parallel Reduction.
