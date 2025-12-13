# Sprint 11 — Testing: Golden Frames + Performance Budgets

## Goal
Add confidence tests that catch regressions:
- golden-frame hashes for deterministic renders
- performance budgets for key paths

Alignment: performance budgets should reflect Apple Silicon “performance moat” goals (stable, predictable throughput on M‑series devices) and should be measured through the device abstraction (Sprint 02).

Optimization reference: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`
Export reference (zero-copy pattern): `Docs/research_notes/metavis3_fits_jwst_export_autopsy.md`

## Acceptance criteria
- Golden-frame test harness exists:
  - renders one or more deterministic frames
  - computes stable hashes from downsampled pixels
  - stores expected hashes in test code/data
- Performance tests exist for:
  - rendering a frame
  - exporting a short clip (bounded)

## Additional performance invariants (recommended)
- Steady-state multi-pass runs do not perform per-frame texture allocations (instrument pool counters / allocation counts).
- Export path avoids CPU readback for standard formats (guardrails around `getBytes` usage).

## Existing code likely touched
- `Sources/MetaVisSimulation/MetalSimulationEngine.swift`
- `Sources/MetaVisQC/VideoContentQC.swift` (downsample helpers may be reusable)
- Existing simulation/export tests

## New code to add
- `Tests/MetaVisSimulationTests/Golden/GoldenFrameHashTests.swift`
- `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`
- Optional helper: `Tests/TestSupport/FrameHashing.swift`

## Deterministic generated-data strategy
- Use procedural generators (SMPTE/zone plate) and fixed seeds.
- Hash downsampled pixels (not full-res) for stability.

## Test strategy (no mocks)
- Use real metal engine.
- Store expected hashes as literals.
- Perf tests use `XCTest.measure` and set reasonable upper bounds for CI/local.
