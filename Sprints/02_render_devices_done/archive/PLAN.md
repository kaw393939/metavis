# Sprint 02 — Pluggable Render Devices / Renderer-as-Device

## Goal
Introduce a render device abstraction so rendering backends are selectable by capability, while keeping current Metal rendering behavior unchanged. This is the foundation for scaling from a single local Mac → multiple Macs on LAN (render farm) → optional cloud devices later.

Optimization reference: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`

## Acceptance criteria
- A `RenderDevice` protocol exists (capabilities + render API).
- A `MetalRenderDevice` adapter wraps current `MetalSimulationEngine`.
- `VideoExporter`/session can render via a device interface (defaulting to Metal).
- E2E test exports via `RenderDevice` and passes QC.
 - No implicit networking is introduced (local-first by default); remote/LAN devices are a future extension.

## Existing code likely touched
- `Sources/MetaVisSimulation/MetalSimulationEngine.swift`
- `Sources/MetaVisExport/VideoExporter.swift`
- `Sources/MetaVisSession/ProjectSession.swift`
- `Sources/MetaVisCore/VirtualDevice.swift` (naming/shape inspiration only)

## New code to add
- `Sources/MetaVisSimulation/Devices/RenderDevice.swift`
- `Sources/MetaVisSimulation/Devices/MetalRenderDevice.swift`
- `Sources/MetaVisSimulation/Devices/RenderDeviceCatalog.swift` (v1: just Metal; vNext: LAN discovery)

## Test strategy (no mocks)
- E2E export using the device catalog selecting Metal.
- Capability reporting test uses real objects (no mocking).

## Work breakdown
1. Define protocol + capability model.
2. Implement Metal adapter.
3. Thread device into exporter/session (default behavior unchanged).
4. Add E2E tests that exercise selection + export.

## Capability model note
- Consider including performance-oriented capability flags (e.g., shared-event sync availability, memoryless render target support, recommended working-set budgets) so higher layers can select safe defaults.
