# Sprint 07: Continuous QC Sampling

## 1. Objective
Improve `MetaVisQC` to support "Continuous" or "Dense" sampling. Currently, it only checks p10, p50, p90.

## 2. Scope
*   **Target Modules**: `MetaVisQC`
*   **Key Files**: `VideoContentQC.swift`

## 3. Acceptance Criteria
1.  **Dense Mode**: Ability to scan *every* frame (stride 1) for a short clip.
2.  **Scene Mode**: Ability to scan 1 frame *after* every detected scene change (using `VideoTimingProbe` or similar).

## 4. Implementation Strategy
*   Refactor `VideoContentQC.run()` to accept a `SamplingStrategy` enum (sparse, dense, adaptive).

## 5. Artifacts
*   [TDD Plan](./tdd_plan.md)
