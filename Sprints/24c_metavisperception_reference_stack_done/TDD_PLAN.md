# Sprint 24c — TDD Plan

**Status (2025-12-22):** DONE (tests implemented across MetaVisCore/MetaVisPerception/MetaVisLab).

## Testing philosophy
- Prefer deterministic, generated data where possible.
- Use real-asset E2E tests behind env gates for integration points (Vision/CoreML/whisper).
- Every new artifact must have:
  - encode/decode tests
  - determinism contract tests (byte-identical outputs)

## 1) Confidence ontology
### Unit tests
- `ConfidenceLevelV1` encode/decode stability.
- `EvidencedValueV1<T>` encode/decode for representative types (`Bool`, `Double`, `String`, small enums).

### Contract tests
- Ensure stable JSON key ordering and stable arrays ordering (sorted reasons/sources).

## 2) Provenance
### Unit tests
- `ProvenanceRefV1` / `EvidenceRefV1` extensions encode/decode.
- Interval and metric evidence refs serialize deterministically.

## 3) TemporalContextAggregator
### Unit tests (deterministic synthetic)
- Feed a synthetic sequence of `videoSamples` with known face track continuity and verify:
  - stable track events (duration thresholds)
  - drift detection (rect movement thresholds)
- Feed synthetic `audioFrames` with a known energy/voicing pattern and verify:
  - continuous speech segments
  - silence gaps

### Golden tests (repo fixtures)
- Generate `temporal.context.v1.json` from:
  - `Tests/Assets/people_talking/A_man_and_woman_talking.mp4`
  - `Tests/Assets/people_talking/Two_men_talking_202512192152_8bc18.mp4`
  - `Tests/Assets/people_talking/two_scene_four_speakers.mp4`
  - `Tests/Assets/VideoEdit/keith_talk.mov`

Validate:
- deterministic byte-for-byte outputs on rerun
- event counts within expected ranges (avoid brittle exact timestamps unless necessary)

## 4) Identity binding graph
### Unit tests
- Co-occurrence matrix accumulation logic is deterministic.
- Promotion thresholding works and records reasons.
- Demotion logic works (evidence weakens) and records reasons.
- No bindings emitted when evidence is insufficient.

### Integration tests (gated)
- Using existing diarization outputs + sensors.json, generate `identity.bindings.v1.json` and validate:
  - stable outputs across reruns
  - bindings only when the scene makes sense (e.g., man+woman fixture should produce two dominant bindings or explicit ambiguity, depending on visibility)

## 5) SemanticFrame contract hardening
### Unit tests
- `SemanticFrameV2` encode/decode.
- Schema version guard: decoding rejects unknown/unsupported schema strings.

### Integration tests
- A pipeline adapter test that constructs `SemanticFrameV2` from `MasterSensors` + optional binding graph.
- Ensure no untyped attribute dictionaries are used.

## 6) Hardware lifecycle / determinism
### Integration tests (gated)
- Warm-up/cool-down sequences for CoreML/Vision devices do not crash and do not leak state across runs.
- Determinism contract tests explicitly assert:
  - stable timestamps
  - stable sorting
  - no random UUID generation inside outputs (unless derived from stable content hashes)

## Environment gating (expected)
- Use env vars similar to Sprint 24 diarization tests:
  - `METAVIS_RUN_PERCEPTION_TESTS=1`
  - `METAVIS_RUN_VISION_TESTS=1`
  - `METAVIS_RUN_COREML_TESTS=1`
  - (Optional) reuse whisper gates where diarization is required

