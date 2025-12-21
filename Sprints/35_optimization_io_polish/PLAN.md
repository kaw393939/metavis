# Sprint 35: Optimization & Polish (I/O + Edits)

## Goal
Address the technical debt and optimization gaps identified during the "Masterpiece" development, specifically focusing on High-Performance I/O for VFR/8K sources and robust editing support for complex timeline operations.

## Context
Use this sprint to implement the "Gaps" deferred from Sprint 21 (VFR).

## Deliverables

### 1. High-Performance I/O (The "DispatchIO" Path)
*   **Objective:** Eliminate UI lag during ingest of large files.
*   **Implementation:** Replace the `AVAssetReader` probe backend with a low-level `DispatchIO` + `F_NOCACHE` implementation.
*   **Metric:** Parsing an 8K ProRes file should not evict the UI texture cache.

### 2. Complex Edit Sync Contract
*   **Objective:** Verify VFR sync robustness for non-trivial edits.
*   **Tests:** Add E2E tests for:
    *   **Split + Reorder:** Cutting a VFR clip and swapping the halves.
    *   **Gap + Overlap:** Managing sync across timeline gaps.
    *   **Retime:** (Optional) Verify behavior when speeding up/slowing down VFR footage.

### 3. Remote Source Normalization
*   **Objective:** Support `http/https` URLs in `ClipReader`.
*   **Implementation:** Ensure network-backed assets go through the same determinism quantization logic as local files.

## Sources
- Deferred from: `Sprints/21_vfr_normalization_sync`
- Optimization Strategy: `Docs/specs/advanced_features_research/apple_silicon_optimization_strategy.md`
