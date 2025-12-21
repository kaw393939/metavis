# Gap Analysis & Optimization Report: Sprints 21-34
**Date:** 2025-12-20

## 1. Executive Summary
A review of the "Masterpiece" Roadmap (Sprints 21-34) confirms it covers the essential pillars: Identity, Visuals, and Infrastructure. However, specific cross-sprint dependencies require optimization to prevent technical debt.

## 2. Identified Gaps

### A. Fluid Dynamics vs. Determinism (Sprint 28 vs. 30)
*   **Issue:** Sprint 28 (Fluids) creates a particle system. Sprint 30 (Determinism) mandates `FxPoint` logic.
*   **Risk:** If Sprint 28 is implemented with standard `Float32` physics on CPU, it will need a complete rewrite in Sprint 30.
*   **Optimization:** Sprint 28 must strictly use *GPU-driven* simulation (Compute Shaders) where float nondeterminism is acceptable for "visual effects", OR use `FxPoint` stubs for any CPU-side emitter logic.
*   **Action:** Update Sprint 28 PLAN to explicitly scope "GPU-Only Physics" to avoid the CPU float trap.

### B. Agent API Fragmentation (Sprint 25 vs. 32)
*   **Issue:** Sprint 25 (Cortana) defines an `AgentAction` API. Sprint 32 (Neuro-Symbolic) defines an `IntentCommand` GBNF grammar.
*   **Risk:** Creating two divergent command structures.
*   **Optimization:** The `AgentAction` enum defined in Sprint 25 *must be* the source of truth for the JSON Schema generated in Sprint 32.
*   **Action:** Explicitly link these in the spec: "The GBNF Grammar is derived from the `AgentAction` Codable struct."

### C. Transcript Timebase Drift (Sprint 21 vs. 22)
*   **Issue:** Sprint 22 (Transcript) relies on timestamps. Sprint 21 (VFR) normalizes time.
*   **Risk:** Captions generated against raw VFR audio might drift when mapped to the normalized CFR Timeline.
*   **Optimization:** Sprint 22 must depend on the `TimeMap` produced by Sprint 21. Transcripts should store `Rational` ticks (normalized), not just `Double` seconds.

## 3. Operations & Housekeeping
*   **Numbering:** Sprints 30-34 have `PLAN.md` headers that still refer to their old numbers (26-30). These need strictly cosmetic updates to avoid confusion.

## 4. The "Director's Seal" (Sprint 33 vs. 34)
*   **Optimization:** The `DirectorMode` (Sprint 34) autonomous loop should not just "finish export". It should call the `DeliverableVerifier` (Sprint 33) and only mark the job as "Success" if verification passes. This closes the loop.

## 5. Recommended Adjustments
1.  **Refine Sprint 28:** Mandate GPU-driven physics or `Int`-based limits.
2.  **Refine Sprint 32:** Link GBNF to Sprint 25's `AgentAction`.
3.  **Fix Headers:** Update PLAN.md titles for Sprints 30-34.
