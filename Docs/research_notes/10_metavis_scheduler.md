# Research Note: MetaVisScheduler Architecture

**Source Documents:**
- `MetaVisScheduler/Core/Scheduler.swift`
- `MetaVisScheduler/Core/JobQueue.swift`
- `MetaVisScheduler/Workers/RenderWorker.swift`

## 1. Executive Summary
`MetaVisScheduler` is a **Persistent Job Queue System** designed for robust background processing. It decouples the UI from heavy tasks (Rendering, Exporting, Ingestion) using SQLite (`GRDB`) for persistence and crash recovery.

## 2. Core Architecture

### A. The `Scheduler` Actor
-   **Role**: Orchestrator of background work.
-   **Mechanism**: A `tick()` loop that polls the `JobQueue` for `.pending` jobs.
-   **Concurrency**: Simple 1-worker-per-type model currently, but extensible.

### B. `JobQueue` (The Brain)
-   **Persistence**: Uses SQLite via `GRDB`.
-   **Dependencies**: Supports Directed Acyclic Graph (DAG) for jobs (e.g., Ingest -> Analyze -> Render).
-   **Robustness**: Jobs persist across app restarts. Blocked jobs automatically unblock when dependencies complete.

### C. `RenderWorker` (The Muscle)
-   **Integration**: This is the glue between `MetaVisTimeline` and `MetaVisSimulation`.
-   **Workflow**:
    1.  Receives a `Timeline` object in the payload.
    2.  Spins up a `SimulationEngine`.
    3.  Configures `VideoEncodingSettings` (HEVC 10-bit).
    4.  Runs the Render Loop with `ZeroCopyConverter` to pipe Metal textures to `AVAssetWriter/Muxer`.
    5.  Handles Audio extraction and muxing internally.

## 3. Key Findings
1.  **Timeline Integration Verified**: `RenderWorker.swift` contains the proof that `Timeline` drives the `SimulationEngine`.
2.  **Audio "Hack"**: Audio is currently handled by manually reading samples and appending to the muxer. This overlaps with the identified "Audio Gap" but provides a basic export capability.
3.  **LIGM Support**: Legacy "Local Image Generation" is supported as a job type.

## 4. Synthesis for MetaVisKit2
-   **Adoption**: Adopt `MetaVisScheduler` as the **Execution Layer** for all long-running tasks.
-   **Refinement**:
    -   The `RenderWorker` logic logic is the template for the `GraphCompiler` -> `RenderEngine` validation.
    -   The audio processing in `RenderWorker` should be replaced by the new `AudioSystem` once built.
