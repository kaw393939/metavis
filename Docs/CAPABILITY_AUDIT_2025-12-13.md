# MetaVisKit2 — Big Picture Capability Audit (As of 2025-12-13)

This audit summarizes what the system can do today, what evidence exists in the repo, and what the highest-leverage gaps are relative to the architecture intent expressed in `IDEAL_ARCHITECTURE.md`, `REFINED_ARCHITECTURE.md`, and the `CONCEPT_*` documents.

## Legend

- **State**: `Implemented`, `Partial`, `Stub/Scaffold`, `Missing`
- **Evidence**: concrete code + tests + runnable path.

## Capability matrix (current state)

| Area | Capability | State | Evidence (examples) | Primary gaps / risks | Recommended next step |
|---|---|---:|---|---|---|
| Core | Governance primitives (plan/license/types) | Implemented | `Sources/MetaVisCore/GovernanceTypes.swift` | Governance not yet generalized into “policy bundles” for all ops | Add a `GovernancePolicy` bundle and apply to ingest/render/export uniformly |
| Session | Orchestration + state + intent hooks | Partial | `Sources/MetaVisSession/ProjectSession.swift`, `EntitlementManager.swift` | Intent→actions still shallow; persistence scope unclear | Add intent-to-command registry + persistence boundaries |
| Timeline | Track/clip model + typed track kinds | Implemented | `Sources/MetaVisTimeline/Timeline.swift` (`TrackKind`) | Editing ops may be thin (no advanced trimming/transitions) | Add recipe-driven timeline construction + basic edit ops |
| Ingest | Device abstraction + LIGM device | Partial | `Sources/MetaVisIngest/LIGMDevice.swift` | Hardware “device knowledge base” + device selection policy not wired | Introduce device catalog + selection policy |
| Simulation | Metal engine and render execution | Implemented | `Sources/MetaVisSimulation/MetalSimulationEngine.swift` | Pluggable render backends not implemented | Define `RenderDevice` protocol + adapters |
| Graphics | Shader library, processed resources bundle | Implemented | `Sources/MetaVisGraphics/Resources/*.metal` | Feature pipelines (multi-pass) not fully expressed | Add multi-pass feature execution model |
| Export | Video export (AVFoundation writer) | Implemented | `Sources/MetaVisExport/VideoExporter.swift` | Export presets + packaging pipeline (EDL, sidecars) not present | Add export “deliverable” packaging layer |
| Export | Export governance enforcement | Implemented | `ExportGovernance.swift`, `VideoExporter.validateExport`, tests | Needs more policy types (e.g. codec caps) | Expand governance validation surface |
| Export | Watermarking | Implemented | `WatermarkSpec`, `Watermark.metal`, engine application | Only one watermark style; limited controls | Add a second style only if required; otherwise parameterize current |
| Audio | Timeline audio rendering | Partial | `AudioTimelineRenderer.swift` | Uses `!` for `AVAudioFormat`; mixing is simplistic | Remove unsafe unwrap; add deterministic mix/downmix rules |
| QC | Deterministic QC (video/audio) | Implemented | `Sources/MetaVisQC/VideoQC.swift` | QC coverage breadth (color checks, HDR metadata) limited | Extend QC checks per `CONCEPT_QUALITY_GOVERNANCE.md` |
| QC | Optional Gemini content gate | Implemented | `Sources/MetaVisQC/GeminiQC.swift` | Prompt governance and privacy policy not formalized | Add “AI usage governance” policy + structured prompts |
| Services | Gemini client/device + intent parser | Partial | `Sources/MetaVisServices/Gemini/*`, `IntentParser.swift` | Tooling/agent loop is early; observability limited | Add structured tool protocol + logging/telemetry |
| Features | Feature registry model | Implemented | `FeatureManifest.swift`, `FeatureRegistry.swift` | Lifecycle/versioning/validation incomplete | Add manifest schema versioning + validation |
| Features | Bundle manifest loading | Implemented | `FeatureRegistryLoader.swift`, `RegistryLoaderTests` | SwiftPM resource flattening is a known gotcha | Document resource layout + add a loader assertion test |
| Tooling | CLI lab runner end-to-end | Implemented | `Sources/MetaVisLab/main.swift` | Needs “recipes” to avoid bespoke setup code | Add recipe-based lab scenarios |
| Testing | Unit tests across modules | Implemented | `Tests/**` and `swift test` | No explicit performance tests; no golden image suite | Add perf budgets + snapshot/golden harness |

## Highest-leverage architecture gaps (prioritized)

1. **Project Types as Recipes** (from `REFINED_ARCHITECTURE.md` / governance concepts)
   - Goal: a project type chooses a “recipe” (timeline template, render graph template, default governance + QC).
   - Why now: reduces bespoke setup logic (CLI/tests), makes governance predictable, enables repeatable scenarios.

2. **Pluggable Render Devices / Renderer-as-Device** (from `CONCEPT_PLUGGABLE_RENDERERS.md`, `CONCEPT_RENDERER_AS_DEVICE.md`)
   - Goal: treat render backends as selectable devices with capabilities (Metal local, remote, cloud, headless).
   - Why now: unlocks hybrid layers and future scaling without rewriting export.

3. **Quality Governance as Policy Bundles** (from `CONCEPT_QUALITY_GOVERNANCE.md`, `CONCEPT_QUALITY_DISTRIBUTION.md`)
   - Goal: unify export constraints, QC requirements, and AI-gate requirements as explicit policies.

4. **Feature pipeline semantics (multi-pass, dependencies, scheduling)**
   - Evidence: `StandardFeatures.swift` already notes multi-pass needs.
   - Goal: feature graph → passes → render graph execution.

5. **Observability + determinism hardening**
   - Remove remaining unsafe unwrap(s) and document deterministic fallbacks.
   - Add structured traces around export/QC/AI-gate for reproducibility.

## Proposed next implementation sequence (small vertical slices)

These are ordered to maximize reuse and minimize risk.

1. **Recipes v1 (data-only)**
   - Add `ProjectRecipe` that can generate: timeline tracks + default quality profile + default governance.
   - Add tests that a recipe produces a deterministic timeline and respects plan/license.

2. **Render device catalog v1 (single backend)**
   - Introduce `RenderDevice` protocol and a `MetalRenderDevice` adapter around `MetalSimulationEngine`.
   - Keep behavior identical; add tests for selection and capability reporting.

3. **Policy bundle v1 (export + QC)**
   - Add a single struct that bundles `ExportGovernance` + QC requirements.
   - Make session compute and pass it through.

4. **Feature execution v1 (multi-pass support)**
   - Minimal pass scheduler for a small subset of features that need two passes.

## Notes / known risks

- SwiftPM resources: processed resources may be flattened inside the built bundle; do not assume subfolders exist at runtime.
- Audio: `AudioTimelineRenderer` currently uses a forced unwrap for `AVAudioFormat`; this should be eliminated for robustness.

## Related docs

- `SYSTEM_RECORD_2025-12-13.md` (snapshot record)
- `TDD_FEATURE_REGISTRY.md` (feature registry plan)
- `CONCEPT_QUALITY_GOVERNANCE.md` (quality policy intent)
- `CONCEPT_PLUGGABLE_RENDERERS.md` / `CONCEPT_RENDERER_AS_DEVICE.md` (device abstraction intent)
