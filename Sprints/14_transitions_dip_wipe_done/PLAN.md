# Sprint 14 — Transition Types (Dip/Wipe) + Assets Coverage

## Goal
Make transition *types* first-class at render time (not just alpha), and lock down real-media coverage using `Tests/Assets` (no mocks).

This sprint absorbs the previously out-of-scope work from Sprint 13:
- `TransitionType.dip` rendering
- `TransitionType.wipe` rendering
- Explicit E2E tests that exercise every content *type* present in `Tests/Assets/`

## Scope
### 1) Transition Rendering
- Implement transition-type compositing for two-clip overlaps in `TimelineCompiler`:
  - `crossfade` (existing)
  - `dip(color:)`
  - `wipe(direction:)`
- Keep behavior deterministic and compatible with existing overlap model:
  - adjacent clips overlap when both have transitions set
  - easing curves must affect transition progress

### 2) Metal Kernels
Add compositor kernels (working space = ACEScg):
- `compositor_dip` (A → color → B)
- `compositor_wipe` (reveal B over A in direction)

### 3) Engine Binding
Update `MetalSimulationEngine` to:
- cache the new pipelines
- bind new uniform parameters (`progress`, `dipColor`, `direction`)

### 4) Test Coverage (No Mocks)
All tests are real E2E using:
- `MetalSimulationEngine` + `VideoExporter`
- content from `Tests/Assets`

Required test suites:
1. **Transition Dip**: export with `dipToBlack` and assert the transition midpoint is near black (deterministic QC).
2. **Transition Wipe**: export with wipe and assert left/right regions differ at the midpoint.
3. **Assets Coverage**: enumerate `Tests/Assets` extensions and prove each type can be used:
   - `.mov` (file-backed video)
   - `.mp4` (file-backed video)
   - `.exr` (EXR still decode path)
   - `.fits` (FITS still decode path)
   - `.vtt` (caption sidecar discovery + emit)

## Non-Goals
- Multi-clip (3+) type-specific transitions (falls back to alpha blend)
- Audio crossfades or type-specific audio transitions
- Advanced wipes (feathered edges, shapes) beyond directional wipe

## Acceptance Criteria
- `dip` and `wipe` have observable impact in exported video.
- Test suite proves:
  - dip midpoint is near black
  - wipe midpoint produces spatially distinct left/right regions
  - every content type in `Tests/Assets` is exercised end-to-end
- No mocks used.

## Files (expected)
- Sources:
  - `Sources/MetaVisGraphics/Resources/Compositor.metal`
  - `Sources/MetaVisSimulation/TimelineCompiler.swift`
  - `Sources/MetaVisSimulation/MetalSimulationEngine.swift`
- Tests:
  - `Tests/MetaVisExportTests/TransitionDipWipeE2ETests.swift`
  - `Tests/MetaVisExportTests/AssetsCoverageE2ETests.swift`

