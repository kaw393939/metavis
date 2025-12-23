# Shader Architecture (MetaVisKit2)

This folder is the canonical, *shipping* shader documentation set for MetaVisKit2.

Scope:
- Active Metal shaders under `Sources/MetaVisGraphics/Resources/*.metal`.
- QC Metal shaders under `Sources/MetaVisQC/Resources/*.metal`.
- How shaders are loaded, named, and bound by the production engine (`Sources/MetaVisSimulation/MetalSimulationEngine.swift`) and compiler (`Sources/MetaVisSimulation/TimelineCompiler.swift`).

Start here:
- `ARCHITECTURE.md` — overall shader system architecture + layering plan.
- `BINDINGS.md` — **actual** runtime binding conventions (textures/buffers) as encoded today.
- `M3_OPTIMIZATION.md` — Apple M3+ performance checklist and priorities.
- `SHADERS.md` — index of shader files and their entrypoints.

Per-shader specs live in `specs/`.
