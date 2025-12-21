# MetaVisKit2 — System Record (As of 2025-12-13)

This document is a snapshot of what the MetaVisKit2 system is, what exists in the codebase today, and what has been implemented during the current stabilization + architecture-gap-closure initiative.

## Scope and sources

- Repo: `MetaVisKit2` SwiftPM workspace (macOS 14 / iOS 17 targets)
- Architecture references in this repo:
  - `IDEAL_ARCHITECTURE.md`, `REFINED_ARCHITECTURE.md`, `SYSTEM_CRITIQUE.md`
  - `CONCEPT_*` documents (governance, quality, pluggable renderers, renderer-as-device, autonomy tiers, etc.)
  - `TDD_STRATEGY.md`, `TDD_FEATURE_REGISTRY.md`

## Package / module map (from `Package.swift`)

- `MetaVisCore`: primitive types, governance types, device abstractions, render request structs.
- `MetaVisTimeline`: timeline model (tracks/clips), typed track kinds.
- `MetaVisGraphics`: Metal shader library + processed resources bundle.
- `MetaVisSimulation`: Metal simulation/render engine and feature system.
- `MetaVisIngest`: hardware/IO devices (e.g. `LIGMDevice`).
- `MetaVisAudio`: audio generation + timeline audio rendering.
- `MetaVisExport`: movie export (AVFoundation writer) and export governance checks.
- `MetaVisQC`: deterministic QC (video/audio checks) + optional Gemini “content gate”.
- `MetaVisServices`: AI/device services (Gemini client/device), intent parsing.
- `MetaVisPerception`: perception layer (CV hooks; still evolving).
- `MetaVisSession`: orchestration “brain” (state, entitlements, intent parsing, export orchestration).
- `MetaVisKit`: UI/agent layer (thin, depends on `MetaVisSession`).
- `MetaVisLab` (executable): CLI runner demonstrating a full end-to-end flow.

## Current end-to-end “happy path”

### Lab workflow (CLI)

- Entry: `Sources/MetaVisLab/main.swift`
- Steps:
  - Create a `ProjectSession` with a `ProjectLicense`.
  - Use `LIGMDevice` to “generate” an asset (returns `assetId` + `sourceUrl`).
  - Build a simple timeline (track + clip) by dispatching session actions.
  - Export via session-governed export:
    - `ProjectSession.exportMovie(using:to:quality:frameRate:codec:audioPolicy:)`
    - Uses `VideoExporter` + `MetalSimulationEngine`.

### Export orchestration (session → exporter → engine)

- Session API: `Sources/MetaVisSession/ProjectSession.swift`
  - Constructs `ExportGovernance` based on:
    - `EntitlementManager.currentPlan` (user plan)
    - `ProjectLicense` (per-project constraints)
    - Auto-injects watermark spec when license requires it.
- Exporter: `Sources/MetaVisExport/VideoExporter.swift`
  - Validates governance and quality (`validateExport`).
  - Drives rendering frames via `MetalSimulationEngine`.
  - Includes audio per `AudioPolicy` and timeline track kinds.
- Engine: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`
  - Renders frames into `CVPixelBuffer`.
  - Applies watermark (if present) via a Metal compute kernel.

## Governance (implemented + enforced)

- Types: `Sources/MetaVisCore/GovernanceTypes.swift`
  - `UserPlan` (e.g. `.free`, `.pro`)
  - `ProjectLicense` (e.g. `maxExportResolution`, `requiresWatermark`, etc.)
  - `WatermarkSpec` (currently `.diagonalStripes` + tunables)
- Session enforcement:
  - `Sources/MetaVisSession/EntitlementManager.swift`
  - `Sources/MetaVisSession/ProjectSession.swift` (builds and forwards `ExportGovernance`)
- Export enforcement:
  - `Sources/MetaVisExport/ExportGovernance.swift`
  - `Sources/MetaVisExport/VideoExporter.swift` (`validateExport` checks resolution caps + watermark requirements)
- Tests:
  - `Tests/MetaVisExportTests/ExportGovernanceTests.swift`
  - `Tests/MetaVisSessionTests/ExportGovernanceWiringTests.swift`

## Watermarking (implemented)

- Shader:
  - `Sources/MetaVisGraphics/Resources/Watermark.metal` (`watermark_diagonal_stripes`)
- Data model:
  - `Sources/MetaVisCore/GovernanceTypes.swift` (`WatermarkSpec`)
- Application point:
  - `Sources/MetaVisSimulation/MetalSimulationEngine.swift` applies watermark in-place on the export pixel buffer’s Metal texture.
- Enforcement behavior:
  - If `ProjectLicense.requiresWatermark == true` and no watermark is provided, export fails with `ExportGovernanceError.watermarkRequired`.
  - Session currently auto-provides `.diagonalStripesDefault` when a license requires watermarking.

## Feature Registry (implemented loader + bundle manifest example)

- Feature architecture:
  - `Sources/MetaVisSimulation/Features/FeatureManifest.swift`
  - `Sources/MetaVisSimulation/Features/FeatureRegistry.swift`
  - `Sources/MetaVisSimulation/Features/FeatureRegistryLoader.swift`
- Bundled manifest example (graphics bundle resource):
  - `Sources/MetaVisGraphics/Resources/Manifests/com.metavis.fx.smpte_bars.json`
- Tests:
  - `Tests/MetaVisSimulationTests/Features/RegistryLoaderTests.swift`
- Operational note:
  - SwiftPM processed resources may be flattened into the bundle root; loader defaults to searching bundle root (subdirectory `nil`).

## Quality control (QC) and AI “gate” (implemented)

- Deterministic checks (existence, track presence, duration, fps, resolution, sample counts, audio non-silence):
  - `Sources/MetaVisQC/VideoQC.swift`
- Deterministic “content-ish” checks:
  - `Sources/MetaVisQC/VideoContentQC.swift` (fast + deterministic downsample-based checks)
- Optional AI acceptance gate (Gemini), designed to be additive not a replacement:
  - `Sources/MetaVisQC/GeminiQC.swift`
  - Uses env vars like `GEMINI_API_KEY` / `API__GOOGLE_API_KEY`.

## Audio export (implemented)

- Policy:
  - `Sources/MetaVisExport/AudioPolicy.swift`
- Rendering:
  - `Sources/MetaVisAudio/AudioTimelineRenderer.swift`
- Integration:
  - `Sources/MetaVisExport/VideoExporter.swift` uses `AudioTimelineRenderer` and includes audio based on `AudioPolicy` and timeline `TrackKind`.

## Test status (as observed in this workspace)

- `swift test` is green (most recent run reported 59 tests, 0 failures).

## Known constraints / gotchas

- Resource packaging: SwiftPM processed resources can appear flattened in the built `.bundle`; avoid assuming nested subdirectory layout.
- Watermark kernel assumes the export frame is accessible as an RGBA 16-bit float texture.
- Audio: `AudioTimelineRenderer` currently force-unwraps an `AVAudioFormat` (`!`); worth hardening.

## Work log (what has been done during this initiative)

This list is written as a “capabilities added + stabilized” log, not as a git-commit ledger.

- Stabilized the export pipeline around a Metal-rendered → AVFoundation-writer movie export workflow.
- Added deterministic QC checks and an optional Gemini-based acceptance gate.
- Ensured audio can be included in exports (policy-driven) and validated for non-silence in QC.
- Reduced tech-debt in timeline typing (track kinds) and policy typing (audio policy), keeping tests green.
- Implemented export governance enforcement (plan/license caps) with unit tests.
- Wired governance end-to-end via `ProjectSession` so export is always session-governed.
- Implemented watermark support (Metal compute overlay) and integrated it through governance/session/exporter/engine.
- Updated `MetaVisLab` to export via the session path (not by bypassing governance).
- Implemented feature-manifest bundle loading (Feature Registry loader) and tests, including a real bundled JSON manifest.

## Planned work (what we intend to do next)

This is the near-term roadmap to continue closing architecture gaps using small, tested vertical slices.

- Big-picture capability audit (matrix + gaps + priorities): see `CAPABILITY_AUDIT_2025-12-13.md`.
- “Project Types as Recipes”:
  - Define recipe objects/templates that generate timelines + render graphs + default governance.
- “Pluggable Render Devices / Renderer-as-Device”:
  - Select render backends/devices via a catalog and explicit selection policy.
- Quality governance expansion:
  - Make quality profiles + governance more composable (distribution tiers, policy bundles).
- Feature registry expansion:
  - Multiple manifests, versioning, validation, and mapping manifests → render nodes.
- Determinism hardening:
  - Eliminate remaining unsafe unwraps; document deterministic fallbacks in the engine.

## How to run

```zsh
swift test

# Run the CLI lab runner
swift run MetaVisLab
```
