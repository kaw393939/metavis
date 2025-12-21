# Implemented Features

## Status: Implemented (Priority 0)

## What’s actually implemented in code

### Safety (Sync): multi-track ripple shifting
- Ripple edits shift downstream clips across *all* tracks via a shared helper.
- Implemented commands: `rippleTrimOut`, `rippleTrimIn`, `rippleDelete`.
- Implementation: `Sources/MetaVisSession/Commands/CommandExecutor.swift`.

### Safety (Registry): validation + startup safety belt
- Registry validation exists (`validateRegistry`) and is invoked after standard feature bootstrap.
- Bundle manifest loader validates uniqueness + referenced resources deterministically.
- Implementation: `Sources/MetaVisSimulation/Features/FeatureRegistry.swift`, `FeatureRegistryLoader.swift`, `FeatureRegistryBootstrap.swift`.
- Tests: `Tests/MetaVisSimulationTests/Features/RegistryLoaderTests.swift`.

### Communication (Sidecars): real sidecar writing
- Deliverable export writes sidecars (captions VTT/SRT, thumbnail JPEG, contact sheet JPEG) and records them in the deliverable manifest + sidecar QC report.
- Implementation: `Sources/MetaVisSession/ProjectSession.swift`, `Sources/MetaVisExport/Deliverables/SidecarWriters.swift`.
- Tests: `Tests/MetaVisExportTests/DeliverableE2ETests.swift`.

### Memory (Persistence): JSON recipe loading
- Project recipes can be loaded from JSON (schemaVersion=1) with deterministic encoding.
- `ProjectSession` supports init from a recipe URL.
- Implementation: `Sources/MetaVisSession/RecipeLoader.swift`, `Sources/MetaVisSession/RecipeRegistry.swift`.
- Tests: `Tests/MetaVisSessionTests/RecipeLoaderTests.swift`.
