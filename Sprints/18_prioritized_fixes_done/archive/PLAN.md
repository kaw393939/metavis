# Sprint 18 — Comprehensive Remediation Plan (Post-Audit)

## Goal
Close the highest-impact gaps identified across Sprint 01–17 audits by hardening the editing core, deliverables/QC contract, governance/privacy enforcement, and determinism/performance guardrails.

Sprint 18 is intentionally “finish what we started”:
- Fix correctness issues that break basic NLE semantics.
- Turn existing *types/contracts* into enforced behavior.
- Add missing glue/orchestration so the system is end-to-end usable without hand-wiring.

## Scope (What Sprint 18 Covers)
This plan is derived from the concrete gaps in:
- Recipes + governance wiring (Sprint 01, 03)
- Render devices selection (Sprint 02)
- Multi-pass feature execution + registry validation (Sprint 04, 10)
- Deliverables packaging + QC expansion (Sprint 05, 06)
- AI usage governance/redaction + model version capture (Sprint 07)
- Typed command surface + targeting + traces (Sprint 08, 13)
- Audio hardening follow-ons (Sprint 09, 17)
- Golden/perf budget tightening and coverage (Sprint 11)
- iPhone/VFR risk surfaced in backlog (Sprint 12)
- Sensor identity + editorial-unit outputs (Sprint 15)
- Auto enhancements + feedback loop orchestration (Sprint 16, 17)

## Priority 0 (Blockers): Editing Correctness + Time Mapping
These items unblock “basic NLE correctness” and de-risk almost everything downstream (probes, auto-enhance, QA).

1) **Procedural clip-local time mapping**
- Fix `TimelineCompiler.createSourceNode` so procedural sources receive *clip-local* time:
	- `localTime = (time - clip.startTime) + clip.offset`
	- apply `localTime` consistently for all procedural generators that are time-varying (zone plate, counters, etc.).

2) **Edit operations as typed commands (minimum viable FCP basics)**
- Extend typed commands + executor to support:
	- move clip (`startTime`)
	- trim out (`duration`)
	- trim in / slip (`offset`)
	- blade/split (one clip -> two)
	- ripple trim-out (shift downstream clips)

3) **Command targeting (stop hardcoding “first clip”)**
- Implement a minimal targeting mechanism:
	- v1: by `clipId` and fallback `firstClip` (explicit)
	- keep all targeting deterministic; no perception/LLM-based targeting in Sprint 18.

## Priority 1: Deliverables + QC Contract Completion
These items harden the “deliverable bundle” as the canonical artifact.

1) **Sidecar generation (not just schema support)**
- Implement at least one real sidecar writer (recommended first: thumbnails/contact sheet).
- Ensure `ProjectSession.exportDeliverable(... sidecars:)` actually generates sidecars and records them in `deliverable.json`.

2) **Sidecar QC integration**
- Add a `DeliverableSidecarQCReport` generation step in export that verifies:
	- declared sidecars exist on disk
	- basic validity (e.g., non-empty files; JSON decodes when applicable).

3) **QC policy enforcement beyond container checks**
- Add policy-driven checks for *metadata* and/or *content* where safe and deterministic.
	- Example: `expectedCodecFourCC`, `requireHDR`, `requireColorPrimariesPresent`.
	- Keep defaults conservative to avoid breaking existing exports.

4) **Batch deliverable export (optional, if time permits)**
- Add a single API to export multiple deliverables in one run with stable ordering, producing multiple bundles.

## Priority 2: Governance + Privacy Enforcement “Make It Real”

1) **ProjectType -> Recipe mapping**
- Add a deterministic mapping from `ProjectType` to default recipe IDs.

2) **Recipe registry (lookup by ID)**
- Implement a `RecipeRegistry` (static registration is fine) so:
	- recipes can be discovered/selected deterministically
	- tests can refer to recipes by id.

3) **Policy persistence / library (minimal)**
- Implement a `PolicyLibrary` concept (named bundles) so projects can reference a stable policy id.
	- v1 can be local JSON in a known folder (no UI).

4) **AI redaction enforcement**
- Implement redaction logic per `AIUsagePolicy.RedactionPolicy`:
	- remove file paths
	- remove stable identifiers (UUIDs) where relevant
	- ensure redaction happens *before* any network request.

5) **Model version capture**
- Ensure AI QC outputs include model identifier/version/config in traces and/or deliverable manifest.

## Priority 3: Registry + Multi-Pass Hardening

1) **Registry validation**
- Add `FeatureRegistry.validateRegistry()` that asserts:
	- id uniqueness
	- schema/domain consistency
	- resource references resolve (LUTs/textures) via a small `ResourceResolver`.

2) **Multi-input passes (remove arity limitation)**
- Expand `MultiPassFeatureCompiler` to support >1 inputs per pass.
	- This is required for mask/blend-class features and aligns with Sprint 10 “ports/usage-context” intent.

## Priority 4: Performance + Determinism Guardrails

1) **Performance budgets: tighten + broaden**
- Tighten `RenderPerfTests` default budgets (still env-overridable).
- Add an export performance budget test (bounded duration, includes QC).

2) **Memory footprint instrumentation (minimal)**
- Add a peak memory metric to diagnostics (or a proxy metric such as pooled texture bytes) and assert it in a targeted test.

3) **QC sampling strategy**
- Keep existing p10/p50/p90, but add a deterministic option to include scene-boundary-adjacent sampling when available (future-friendly, still deterministic).

## Priority 5: Sensor/Auto Enhancements “Close the Loop”
This is targeted glue work, not expanding scope.

1) **Face identity MVP**
- Implement faceprint extraction + stable matching to support “Person A vs Person B” across segments.

2) **Bite map integration**
- Add deterministic `bites.json` generation or embed bites into `MasterSensors` output.

3) **Feedback loop orchestration**
- Add a `FeedbackLoopOrchestrator` that runs:
	- propose -> evidence selection -> QA (optional/env gated) -> bounded edits
	- handles `requestedEvidenceEscalation` deterministically.

4) **Auto color/audio: small, testable upgrades**
- Color: add highlight protection using existing luma/histogram signals.
- Audio: use `audioFrames` to add one extra deterministic rule (e.g., muffled detection -> mild high-shelf).

## Priority 6: Render Device Selection
Not remote rendering; just make the abstraction used.

- Implement a deterministic `DeviceSelector` that picks a `RenderDevice` from `RenderDeviceCatalog` based on `QualityProfile` (resolution cap, watermark support).

## Acceptance Criteria (Sprint 18 Definition of Done)
- Editing correctness:
	- procedural sources honor clip-local time
	- typed commands support move/trim-in/trim-out/blade/ripple
	- targeting supports explicit `clipId`
- Deliverables:
	- at least one sidecar is generated and recorded
	- sidecar QC report is present when sidecars are requested
	- metadata/content QC can enforce at least one policy gate
- Governance/privacy:
	- `ProjectType` maps to recipes deterministically
	- AI redaction is applied before any Gemini/network path
	- model id/version is recorded in deliverable/traces when AI runs
- Registry/multipass:
	- registry validates id uniqueness + resource layout
	- multi-pass compiler supports multi-input passes
- Perf/determinism:
	- render + export perf budgets exist and are env-configurable
	- at least one memory/working-set guardrail is asserted in tests

