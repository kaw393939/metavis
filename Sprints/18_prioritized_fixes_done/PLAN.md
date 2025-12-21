# Sprint 18: Operation Trust (Chassis Hardening)

## Goal
Build the "Hippocratic Oath" layer. Ensure the system is safe, stable, and persistent so that future AI agents (Sprint 19+) can operate without destroying user work.

## Critical Remediation (Priority 0)
This plan’s Priority 0 items are implemented in the current codebase:

1.  **Safety (Sync)**: Multi-track ripple shifting
    - Implemented via `shiftDownstreamClipsAcrossAllTracks` used by `rippleTrimOut`, `rippleTrimIn`, and `rippleDelete`.
    - Code: `Sources/MetaVisSession/Commands/CommandExecutor.swift`.

2.  **Safety (Registry)**: Registry validation + bundle manifest validation
    - `FeatureRegistry.validateRegistry()` exists and is called as a final safety belt during registry bootstrap.
    - Bundle manifests are validated for uniqueness and referenced resource existence.
    - Code: `Sources/MetaVisSimulation/Features/FeatureRegistry.swift`, `FeatureRegistryLoader.swift`, `FeatureRegistryBootstrap.swift`.
    - Tests: `Tests/MetaVisSimulationTests/Features/RegistryLoaderTests.swift`.

3.  **Communication (Sidecars)**: Real sidecar generation
    - Deliverable export writes sidecars (captions + thumbnail + contact sheet) and records sidecar QC.
    - Code: `Sources/MetaVisSession/ProjectSession.swift`, `Sources/MetaVisExport/Deliverables/SidecarWriters.swift`.
    - Tests: `Tests/MetaVisExportTests/DeliverableE2ETests.swift`.

4.  **Memory (Persistence)**: JSON recipe loading
    - Recipes are loadable from JSON (schemaVersion=1) and writer output is deterministic.
    - Code: `Sources/MetaVisSession/RecipeLoader.swift`, `Sources/MetaVisSession/RecipeRegistry.swift`.
    - Tests: `Tests/MetaVisSessionTests/RecipeLoaderTests.swift`.

## Deliverables
-   ✅ `CommandExecutor` with sync-safe multi-track ripple logic.
-   ✅ `FeatureRegistry` with validation + manifest loader hardening.
-   ✅ Deliverable export producing sidecars and sidecar QC recording.
-   ✅ Project recipes loadable from JSON.

## Follow-ups (v2+)
- True linked-selection semantics (paired audio/video deletes).
- Project persistence beyond “recipe definition” (workspace/project files + migrations).
