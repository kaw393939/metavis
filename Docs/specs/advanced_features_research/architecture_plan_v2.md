# Architecture Plan V2: The Additive Masterpiece

**Date:** 2025-12-20
**Objective:** Add Determinism, CRDTs, and Neuro-Symbolic capabilities to `metaviskit2` without breaking the rock-solid base.

## 1. Core Principle: Additive Extension
We will not rewrite the core `MetaVisSimulation` or `MetaVisTimeline` modules immediately. Instead, we will build **Extension Modules** that wrap or inherit from the base system.

`Legacy App` -> `MetaVisKit2 Base` -> `MetaVisMasterpiece Extensions`

## 2. The Deterministic Engine (Render Layer)
**Strategy:** Subclass & Compute-Only.
*   **Existing:** `MetalSimulationEngine` (Standard Float32, Raster/Compute mix).
*   **New:** `DeterministicSimulationEngine` (Subclass).
    *   **Override:** Overrides `render(request:)` to strictly use a **Compute-Only Pipeline**.
    *   **Implementation:** It forces the use of a new shader library (`FixedPoint.metal`) instead of the standard library.
    *   **Benefit:** The UI uses the base engine (Fast). The Expert User switches to "Simulation Mode" which swaps the actor instance to the Deterministic Engine.

## 3. The Collaborative Timeline (Data Layer)
**Strategy:** The CRDT Sidecar.
*   **Existing:** `Timeline` (Struct, Snapshot).
*   **New:** `TimelineCRDTManager` (Class).
    *   **Function:** Holds a robust Tree-CRDT (LSEQ/Fugue) in memory.
    *   **Sync:** When the CRDT changes (via Ghost User or Network), it *projects* a snapshot into a standard `Timeline` struct and injects it into the app state.
    *   **Benefit:** The rest of the app (Renderer, UI) continues to consume the simple `Timeline` struct, unaware of the complex CRDT logic managing it.

## 4. The Neuro-Symbolic Brain (Logic Layer)
**Strategy:** The Compiler Middleware.
*   **Existing:** No Logic Layer.
*   **New:** `MetaVisNeuro` (Module).
    *   **DSL:** Define `MetaVisScript` (Swift formatting style).
    *   **Compiler:** A Swift-based parser/lexer that converts `MetaVisScript` string -> `Timeline` struct update commands.
    *   **LLM Integration:** A wrapper around local LLM calls (e.g., `MLX` or `Ollama`) that injects the Grammar Constraints.

## 5. Module Structure Updates
We will introduce new directories (`Sources/...`) to keep the base clean:

| Module | New Component | Purpose |
| :--- | :--- | :--- |
| `MetaVisSimulation` | `Deterministic/` | Contains `FixedPoint.metal` and `DeterministicEngine.swift`. |
| `MetaVisTimeline` | `CRDT/` | Contains the Tree-CRDT logic. |
| `MetaVisNeuro` | *(New Module)* | Contains DSL Parser and LLM Client. |

## 6. Verification Plan
1.  **Determinism Test:** Render a noise frame on CPU (Reference) and GPU (FixedPoint). Assert `bit_exact_match`.
2.  **CRDT Fuzz Test:** Spawn 2 "Ghost Users" making random edits. Assert convergence to identical `Timeline` struct.
3.  **Round-Trip Script:** `Timeline` -> `MetaVisScript` -> `Timeline`. Assert equality.
