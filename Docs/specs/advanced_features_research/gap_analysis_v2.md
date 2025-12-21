# Gap Analysis V2: MetaVisKit2 Audit

**Date:** 2025-12-20
**Comparison:** Current "Rock Solid Base" vs. "Masterpiece Vision (2025)"

## 1. Executive Summary
The current `metaviskit2` is a **clean, functional, but standard** non-linear editing (NLE) engine. It has a solid foundation (Metal renderer, ACES color, Struct-based Timeline), but it completely lacks the "Masterpiece" architectural primitives (Determinism, CRDTs, Neuro-Symbolic DSL).

## 2. Component Analysis

### A. The Engine (`MetaVisSimulation`)
*   **Current State:**
    *   Standard `MTLCommandQueue` execution.
    *   Uses "Hardcoded" or Bundle-based Metal library loading.
    *   No explicit "Fast-Math" control (likely enabled by default).
*   **The Gap (Masterpiece):**
    *   **Missing Determinism:** No fixed-point math implementation. Simulating on different chips will behave differently.
    *   **Missing Dual-Mode:** No distinction between "UI Renderer" (Fast) and "Simulation Renderer" (Deterministic).

### B. The Timeline (`MetaVisTimeline`)
*   **Current State:**
    *   `Timeline`, `Track`, `Clip` are standard Swift `structs` (`Codable`).
    *   State changes require replacing the entire struct (or large chunks).
*   **The Gap (Masterpiece):**
    *   **Not a CRDT:** Simultaneous edits by "Human" and "Ghost User" (AI) will cause race conditions/data loss.
    *   **No Granularity:** Cannot sync "Change Clip Name" without resending the Track. Need a Tree-CRDT.

### C. The Script (`MetaVisCore` / `MetaVisScript`)
*   **Current State:**
    *   `RenderGraph` exists as a passive DAG for executing a frame.
    *   No high-level scripting language exists.
*   **The Gap (Masterpiece):**
    *   **Missing DSL:** No `MetaVisScript` compiler.
    *   **Missing Grammar:** No mechanism to constrain an LLM to valid operations.

### D. Audio (`MetaVisAudio`)
*   **Current State:**
    *   `AudioGraphBuilder` uses `AVAudioEngine` for real-time playback.
    *   Basic graph construction.
*   **The Gap (Masterpiece):**
    *   **Missing PHASE:** No integration with Apple's `PHASE` engine for 3D simulation scenes.
    *   **Missing ANE Separation:** No integration with Neural Engine for source separation.

### E. Graphics (`MetaVisGraphics`)
*   **Current State:**
    *   Good collection of `.metal` shaders (ACES, Bloom, Volumetric Nebula).
*   **The Gap (Masterpiece):**
    *   **Missing Mesh Shaders:** Still using legacy vertex/fragment pipelines.
    *   **Missing Fluid Sim:** No Compute-based FLIP solver.

## 3. Plan of Action (The Bridge)
To get from **Base** to **Masterpiece**, we must:
1.  **Refactor Timeline:** Replace `struct Timeline` with a Class-based `TimelineCRDT` that emits atomic Delta operations.
2.  **Fork Renderer:** subclass `MetalSimulationEngine` into `DeterministicSimulationEngine` which forces a specific Compute-only pipeline.
3.  **Build the Brain:** Create a new module `MetaVisNeuro` to handle the DSL Compiler and LLM Constraints.
