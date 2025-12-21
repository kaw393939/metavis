# Sprint 10 — Feature Registry Hardening (Schema + Validation)

## Goal
Make feature manifests reliable for long-term evolution:
- schema versioning
- validation (required fields, ranges, ports)
- loader assertions around resource layout

Alignment: manifests are the basis for a future marketplace of templates (titles/intros), looks/LUTs, and audio chains.

## Context (from recent work)
We now use feature IDs as a cross-cutting contract across the system:
- Video effects/features registered via manifests (e.g. `com.metavis.fx.*`).
- Audio processing presets referenced by timelines (e.g. `audio.dialogCleanwater.v1`).
- Timeline-intrinsic operations represented as effect IDs (e.g. `mv.retime`, `mv.colorGrade`).

Sprint 10 hardens the registry + manifest layer so these IDs are:
- stable and governable,
- validated early with actionable errors,
- observable via tracing (Sprint 08),
- deterministic (ordering, error surfaces).

## ID taxonomy + policy
- `com.metavis.fx.*`: registry-backed video features described by manifests.
- `audio.*`: audio presets/chains referenced by timelines (manifest representable even if execution plumbing is deferred).
- `mv.*`: reserved timeline-intrinsic IDs; either allowlisted as intrinsic or made manifest-backed explicitly.

Policy requirement: unknown IDs referenced by a timeline must either be resolvable via registry, or explicitly allowlisted as intrinsic; otherwise validation fails with a typed, actionable error.

## Acceptance criteria
- `FeatureManifest` has an explicit `schemaVersion` and supports forward-compat checks.
- Manifests can represent multiple domains via an explicit discriminator (at minimum: `video`, `audio`, `intrinsic`).
- Validation runs on load and rejects invalid manifests with typed, actionable errors that include enough context to debug (at minimum: file, featureId, and a stable error code).
- Validation checks structural compatibility between declared ports and usage-context expectations to prevent late runtime failures:
  - video clip effects: either (a) one image input named `source` or (b) declared as a generator with zero inputs.
  - audio features: declares audio ports/layout compatible with our deterministic audio working format assumptions.
- Loader behavior is deterministic:
  - stable discovery ordering,
  - stable validation ordering,
  - stable error ordering.
- Observability: registry load/validate/register emits trace events via `TraceSink` with stable event names and fields.
- Tests cover:
  - valid manifests load
  - invalid manifests fail validation (typed + actionable)
  - resource layout assumption is documented/validated (bundle flattening)
  - deterministic ordering
  - trace emission on success and failure

## Existing code likely touched
- `Sources/MetaVisSimulation/Features/FeatureManifest.swift`
- `Sources/MetaVisSimulation/Features/FeatureRegistryLoader.swift`
- `Sources/MetaVisGraphics/Resources/Manifests/*.json`
- `Tests/MetaVisSimulationTests/Features/RegistryLoaderTests.swift`

Related (integration expectations)
- `Sources/MetaVisTimeline/FeatureApplication.swift` (feature IDs referenced by timelines)
- `Sources/MetaVisSimulation/TimelineCompiler.swift` (current runtime port/contract assumptions)
- `Sources/MetaVisCore/Tracing/Trace.swift` (Sprint 08 tracing)

## New code to add
- `Sources/MetaVisSimulation/Features/FeatureManifestValidation.swift`
- Add at least one intentionally-invalid manifest resource for tests.

## Non-goals
- Implementing full audio “execution” via the registry in this sprint; Sprint 10 only ensures audio presets/chains are representable and validated.
- Implementing the full Sprint 13 editing engine; Sprint 10 only hardens the ID/manifest/validation contract that those edits will rely on.

## Deterministic generated-data strategy
- Use bundled JSON manifests as “generated data”; keep them deterministic.

## Test strategy (no mocks)
- Use real bundle resources.
- Validation is pure + deterministic.

## Observability strategy (no mocks)
- Use `InMemoryTraceSink` to assert registry load/validate/register traces are emitted with stable fields.
