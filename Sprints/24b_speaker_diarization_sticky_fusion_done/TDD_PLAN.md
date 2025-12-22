# Sprint 24 — TDD Plan (Speaker Diarization + Sticky Fusion)
**Status:** In-progress (contract hardening)
**Last updated:** 2025-12-21

## Test Philosophy
- Deterministic by default: unit tests use synthetic fixtures.
- Env-gated integration tests for model availability and expensive assets.
- Assert stable contracts (outputs + ordering + labels), not model-perfect diarization.

## Contract Tests (fast, deterministic)

### 1) Word attribution baseline
**Test:** `SpeakerDiarizerContractTests.test_populates_speaker_fields_for_single_visible_speaker()`
- Sensors: one face track present over a speech-like interval.
- Transcript: words inside that interval.
- Assert:
  - all words get the same non-nil `speakerId`
  - `speakerLabel == "T1"`

### 2) OFFSCREEN gating
**Test:** `SpeakerDiarizerContractTests.test_offscreen_is_emitted_when_no_faces_present()`
- Sensors: speech-like interval, zero faces.
- Assert: words in speech-like windows get `speakerId == "OFFSCREEN"` and `speakerLabel == "OFFSCREEN"` (or a deterministic mapping).

### 3) No hallucination outside speech-like
**Test:** `SpeakerDiarizerContractTests.test_words_outside_speechLike_are_left_unassigned_or_explicitly_none()`
- Sensors: intervals that are not speech-like.
- Assert: diarizer does not assign speakers outside the allowed windows.

### 4) Stickiness/hysteresis stability
**Test:** `SpeakerDiarizerContractTests.test_stickiness_prevents_flip_flopping()`
- Sensors: two faces with small dominance oscillations.
- Transcript: continuous words.
- Assert:
  - speaker identity does not change more frequently than a small threshold
  - ties break deterministically

### 5) Determinism & stable labels
**Test:** `SpeakerDiarizerContractTests.test_determinism_same_input_same_output_bytes()`
- Run diarizer twice with the same fixtures.
- Assert outputs are identical (including label assignment `T1/T2/...`).

### 6) Speaker map determinism
**Test:** `SpeakerMapTests.test_label_assignment_is_stable_by_first_seen_then_id()`
- Two speakers with tie conditions.
- Assert stable ordering and labels.

## Model-backed tests (env-gated)
These tests should be skipped unless the embedding model is available/configured.

### 7) Embedding pipeline smoke
**Test:** `EmbeddingDiarizationSmokeTests.test_ecapa_path_runs_and_produces_clusters_or_skip()`
- Assert: runs without throwing and produces at least one cluster in a speech-like segment.

### 8) Clusterer determinism
**Test:** `AudioClustererTests.test_cluster_assignment_is_deterministic_or_skip()`
- Same audio windows twice.
- Assert identical cluster IDs and ordering.

## CLI contract tests
### 9) `MetaVisLab diarize` outputs
**Test:** `DiarizeCommandContractTests.test_emits_transcript_vtt_and_speaker_map()`
- Inputs: a small fixture sensors + transcript.
- Assert it writes:
  - `transcript.words.v1.jsonl`
  - `captions.vtt` (contains voice tags)
  - `speaker_map.v1.json`

## Confidence attachment (to be added)
Once Sprint 24 chooses a mechanism:
- transcript schema bump (v2), or
- attribution sidecar (`transcript.attribution.v1.jsonl`)

Add tests asserting:
- `ConfidenceRecordV1.reasons` are finite + sorted
- confidence never increases as evidence degrades
- OFFSCREEN assignments carry explicit reasons
