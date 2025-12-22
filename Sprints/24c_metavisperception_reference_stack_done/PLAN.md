# Sprint 24c — Plan

## Goal
Elevate `MetaVisPerception` into a **reference-grade, deterministic perception stack** by hardening contracts, formalizing confidence/provenance, adding temporal aggregation, and enabling auditable cross-signal identity binding.

This sprint is explicitly **not** about adding new perception features indiscriminately. It is about formalization and trust.

## Invariants (non-negotiable)
- **Determinism first:** if a result can be computed via signal processing/geometry/statistics/heuristics/hashes/temporal continuity, it must not be delegated to probabilistic models.
- **Confidence is first-class:** every output must include governed confidence and rationale; ambiguity is represented explicitly.
- **Temporal coherence > single-frame brilliance:** prefer stable, windowed reasoning.
- **Hardware awareness is design:** CoreML/Vision/Accelerate/Metal lifecycle and deterministic execution are explicit.

## Current state (repo reality)
- Deterministic sensor pipeline exists: `MasterSensorIngestor` emits `MasterSensors` (schemaVersion 4) with video samples, audio segments/frames, warnings, descriptors.
- Governed confidence exists: `ConfidenceRecordV1` + finite `ReasonCodeV1` + `EvidenceRefV1`.
- Diarization pipeline exists (Sprint 24) and now emits a governed attribution sidecar.
## Status
DONE (2025-12-22): confidence/provenance primitives, temporal aggregation, identity binding, and `SemanticFrameV2` are implemented and covered by tests.

## Scope
### 1) Formal confidence ontology (mandatory)
Introduce a shared, codified notion of *epistemic type* for confidence:
- deterministic (math/hashes/geometry)
- heuristic (thresholds/rules)
- modelEstimated (ML output)
- inferred (cross-signal reasoning)

Integrate into perception-facing schemas without relying on free-text fields.

Deliverables:
- A versioned, shared type (e.g., `ConfidenceLevelV1`) and/or a wrapper type (e.g., `EvidencedValueV1<T>`).
- Migration plan for existing perception outputs that currently expose `Double confidence` + free-text `reasons`.

Acceptance:
- All LLM-facing semantics include an explicit epistemic level.
- No new free-text confidence reasons introduced.

### 2) Deterministic TemporalContextAggregator (critical)
Add a new deterministic layer above per-frame semantics:
- Sliding window aggregation over `MasterSensors.videoSamples` / `audioFrames` / diarization segments.
- Emits higher-order events + stability metrics.

Examples:
- “Track UUID stable for 7.8s”
- “Speaker changed at t=84.2s”
- “Lighting shifted low-key → high-key between t=12.0–14.0”

Deliverables:
- `TemporalContextAggregator` implementation and a versioned output schema.
- Integration point: `MasterSensors` → temporal context → LLM boundary.

Acceptance:
- Output is deterministic and byte-stable on identical inputs.
- Event generation is testable with unit tests and golden fixtures.

### 3) Audio↔Visual identity binding over time (auditable)
Bind diarization speaker clusters to visual tracks using co-occurrence statistics over time windows.

Key requirements:
- Probabilistic is allowed **only** if auditable.
- Promotion/demotion must be explicit and explainable.
- Must never claim binding when evidence is insufficient.

Deliverables:
- `IdentityBindingGraphV1` (speakerId ↔ trackId/personId edges with posterior/confidence, evidence windows, and reasons).
- Updates to diarization/attribution outputs to optionally include bindings when confidence is strong.

Acceptance:
- Binding can be reproduced deterministically from stored artifacts.
- Confidence/rationale explains promotion/demotion events.

### 4) Provenance everywhere (compiler-like debug symbols)
Every perceptual proposal and attribute must reference:
- which signal(s) triggered it
- time window
- confidence level
- governed reasons/evidence refs

Deliverables:
- A consistent provenance schema (`ProvenanceRefV1` / extended `EvidenceRefV1`) used across perception outputs.
- Replace free-text reasons in `MasterSensors.DescriptorSegment` with governed reasons where appropriate.

Acceptance:
- Consumers can trace any attribute back to underlying sensors/devices/time windows.

### 5) Strengthen SemanticFrame contract (LLM boundary)
`SemanticFrame` becomes a strictly versioned, stable schema.

Deliverables:
- `SemanticFrameV2` (or similar) with:
  - schema/version
  - bounded typed fields
  - per-attribute confidence (record + epistemic level)
  - provenance references
- Deprecation plan for `SemanticFrame` / `DetectedSubject` stringly-typed attributes.

Acceptance:
- LLM sees only bounded semantics; no raw pixels/tensors.
- Schema is stable and tested (encode/decode + compatibility tests).

## Out of scope
- Any generative vision model integration.
- Moving deterministic perception logic into an LLM.
- New UI/UX.

## Implementation milestones (suggested)
1. Contracts first: confidence ontology + provenance types + schema versions.
2. TemporalContextAggregator with deterministic tests + golden outputs.
3. IdentityBindingGraphV1 + integration with diarization artifacts.
4. SemanticFrameV2 + migration adapter from existing sensors to new schema.

## Test strategy (overview)
- Unit tests: ontology mapping, event generation, binding math, deterministic ordering.
- Contract tests: encode/decode schemas; byte-identical outputs across reruns.
- Real-asset E2E (gated): reuse the existing fixture suite used for diarization + sensors.

