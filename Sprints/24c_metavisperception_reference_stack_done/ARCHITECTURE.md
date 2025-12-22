# Sprint 24c — Architecture

## Architectural thesis
Treat perception as a **local perceptual compiler**:

- Inputs: media signals (video/audio) + deterministic devices
- Mid-layer: temporal aggregation + stability/binding
- Outputs: bounded semantics + governed confidence + provenance

LLMs are downstream advisors. They do not “see” raw pixels/tensors.

## Current architecture (as implemented)
### Deterministic sensor pipeline
- `MasterSensorIngestor` reads media (`AVFoundation`) and emits `MasterSensors`.
- `MasterSensors` contains:
  - `videoSamples` (faces + track IDs + lighting/scene metrics)
  - `audioSegments` / optional `audioFrames` / optional `audioBeats`
  - `warnings` (governed reason codes)
  - `descriptors` (LLM-friendly, but currently includes free-text `reasons`)

### Device layer
Multiple “device streams” already exist (examples):
- `TracksDevice` (Vision tracking) → `ConfidenceRecordV1`
- `MaskDevice` / `FlowDevice` / `DepthDevice` / `MobileSAMDevice` → `ConfidenceRecordV1`
- Diarization (`MetaVisPerception/Diarization/*`) produces speaker clusters

### LLM boundary (currently weak)
- `SemanticFrame` / `DetectedSubject` are placeholder-grade:
  - untyped `attributes: [String: String]`
  - no governed confidence
  - no provenance
  - no schema versioning discipline

## Target architecture (Sprint 24b)

### 1) Confidence + Provenance as shared primitives
Add a shared layer used everywhere:

- `ConfidenceLevelV1` (epistemic type): deterministic / heuristic / modelEstimated / inferred
- `ProvenanceRefV1` (or extension of `EvidenceRefV1`): signal/window/artifact/device
- `EvidencedValueV1<T>`: typed value + `ConfidenceRecordV1` + `ConfidenceLevelV1` + provenance

This is the foundation for “confidence is first-class”.

### 2) TemporalContextAggregator (new)
A deterministic aggregator that sits above raw sensors:

```
MasterSensors (samples/frames/segments)
    ↓
TemporalContextAggregator
    ↓
TemporalContextV1 (events + stability metrics)
```

Responsibilities:
- sliding-window statistics (stability/drift)
- event synthesis (speaker change, track stability, lighting transitions)
- deterministic ordering + stable IDs

### 3) Identity binding graph (new)
A deterministic, auditable binder that links modalities over time:

```
Diarization speakerId (audio)
  ↕ co-occurrence stats over windows
TrackId/personId (vision)
  ↕ optional deterministic faceprint hashes
```

Output: `IdentityBindingGraphV1`
- nodes: `speakerId`, `trackId`, `personId` (when available)
- edges: posterior/confidence + evidence windows + reasons
- events: promotions/demotions

### 4) Strengthened LLM boundary schema
Replace the current stringly-typed `SemanticFrame` with a versioned schema (e.g., `SemanticFrameV2`):

- Explicit `schema` string + versioned types
- Typed subject attributes (`EvidencedValueV1<T>` or typed union)
- No free-text confidence
- Provenance references for every attribute

### 5) Hardware-aware execution contract
Codify and test:
- device/model warm-up/cool-down lifecycles
- deterministic configuration selection (`MLModelConfiguration`, Vision request reuse)
- explicit compute-unit decisions (ANE/GPU/CPU) and logging

## Determinism & auditability rules
- No `Date()` / randomness in artifacts (unless pinned/normalized).
- Stable ordering for arrays in all JSON outputs.
- Every inferred/bound decision must record:
  - inputs used
  - window
  - governed reasons
  - policy ID (when applicable)

## Integration points
- `MetaVisLab` CLI commands should be able to emit:
  - temporal context artifact
  - identity binding artifact
  - semantic boundary artifact for LLM consumption

- `MetaVisServices` should consume only the bounded, versioned semantics.

