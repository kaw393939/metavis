# Real-Video E2E Test Matrix (No Mocks)

This document codifies expectations for the **bundled, real media fixtures** under:
- `Tests/Assets/people_talking/`
- `Tests/Assets/VideoEdit/`

The goal is to lock contracts across the full pipeline (ingest → transcript → diarize → devices → render) without synthetic inputs.

## Test gating
Some tests require external tools / heavier compute and are opt-in.

Common env vars:
- `METAVIS_RUN_WHISPERCPP_TESTS=1` (enables whisper.cpp transcript generation)
- `WHISPERCPP_BIN=...` and `WHISPERCPP_MODEL=...`
- `METAVIS_RUN_DIARIZE_TESTS=1`
- `METAVIS_DIARIZE_MODE=ecapa` (enables embedding-based diarization expectations)

Optional strictness:
- `METAVIS_DIARIZE_STRICT=1` (enables strict expectations for brief/offscreen speakers)

Optional future gates (once artifacts exist):
- `METAVIS_IDENTITY_TIMELINE_STRICT=1` (requires identity timeline + reason code fields)
- `METAVIS_CONFIDENCE_STRICT=1` (requires ConfidenceRecord grades + finite reason codes on emitted artifacts)

## Global invariants (apply to all fixtures)
These invariants operationalize the core mandate.

### Determinism
- Same inputs + same options must produce identical artifact bytes for:
	- `sensors.json`
	- `transcript.words.v1.jsonl`
	- `speaker_map.v1.json`
	- `captions.vtt`
- Where exact byte-level stability is not feasible (timestamps, `createdAt`), tests must normalize known non-deterministic fields and compare stable projections.

### Edit‑grade stability
- No identity “churn explosions” (budgeted upper bounds on speaker births / minute).
- Speaker switching should reflect real turn-taking (avoid ping-pong in silence).
- Devices must not silently degrade: instability must emit warnings/metrics.

### Explicit uncertainty
- When uncertain, the system must label uncertainty (OFFSCREEN, low confidence, reason codes), not guess.

### Confidence governance (mandate)
When `METAVIS_CONFIDENCE_STRICT=1`:
- Emitted confidence uses the shared `MetaVisCore` confidence model (conceptually `ConfidenceRecord.v1`).
- `grade` is the primary consumer-facing signal; `score` is not the sole authority.
- `reasons` are finite enums (no free-text), sorted, stable across runs.
- Confidence must not increase as evidence degrades.

When `METAVIS_IDENTITY_TIMELINE_STRICT=1`:
- The pipeline emits `identity.timeline.v1.json` as the canonical identity spine.
- The identity timeline includes cluster lifecycle, bindings, OFFSCREEN spans, and confidence records.

## Fixtures

### Test suite coverage map
Each fixture should be exercised across:
- Ingest timing/validity
- Transcript generation (whisper.cpp)
- Diarization (ECAPA mode)
- Devices (mask/tracks)
- Render integration (where applicable)

### 1) Two-scene, 3–4 speaker “dirty” clip
Fixture: `Tests/Assets/people_talking/two_scene_four_speakers.mp4`

Narrative:
- Scene 1: two men talking (two distinct speakers)
- Cut
- Scene 2: one woman talking
- Brief offscreen voice near the end

Primary expectations ("good" tests):
- Diarization produces **3–4 non-offscreen speakers** (brief offscreen may be merged/missed).
- Voice tags appear in captions (`<v T1>` etc).
- Speaker labels are contiguous (`T1..Tn`, no gaps) for non-offscreen speakers.
- Diarized transcript is non-empty and includes **speaker switching** (scene 1 is not a single-speaker blob).

Additional expectations (mandate-aligned):
- **Cut robustness**: the cut must not trigger a speaker ID reset storm (budgeted).
- **Anti-fragmentation**: cap total non-offscreen speakers (e.g., `<= 6`) to prevent regression into over-splitting.
- **OFFSCREEN readiness**: even in non-strict mode, at least one interval may be labeled OFFSCREEN or flagged as low binding confidence (once confidence fields exist).

Strict expectations ("dirty" tests, opt-in):
- Offscreen voice is detected as a distinct `OFFSCREEN` speaker (or equivalent).

Thorough E2E expectations (by stage):

Ingest (`sensors.json`):
- Deterministic video sampling (same stride → same sample timestamps).
- Face tracks exist for scene 1 and scene 2; track reacquisition across the cut is allowed but must be deterministic.

Transcript (`transcript.words.v1.jsonl`):
- Non-empty words, monotonic timeline ticks, no negative/retrograde time.

Diarize (`transcript.words.v1.jsonl` + `speaker_map.v1.json` + `captions.vtt`):
- Anti-fragmentation budget: non-offscreen speaker count <= 6.
- Switch budget sanity: at least 2 switches; not ping-ponging every word (cap extreme switching).

Confidence (strict-gated):
- Word-level `attributionConfidence` is present with sorted finite reasons.
- OFFSCREEN words (if present) are `WEAK`/`INVALID` with explicit reason such as `offscreen_forced`.

Identity timeline (strict-gated):
- Clusters include lifecycle (`bornAt`, `lastActiveAt`, `frozen`) and deterministic merges.
- Bindings include confidence + reasons near the cut and near any offscreen span.

Device expectations:
- `TracksDevice` does not crash across the cut; reset/reacquire is allowed if deterministic.
- If tracking stability drops below threshold around cut/reacquire, a warning must be emitted (no silent degrade).

### 2) Two-person conversation (man + woman)
Fixture: `Tests/Assets/people_talking/A_man_and_woman_talking.mp4`

Expectations:
- Diarization produces exactly **2 non-offscreen speakers** in `ecapa` mode.
- Captions contain voice tags.

Additional expectations:
- Speaker distribution is balanced enough to prove turn-taking (avoid "all words assigned to one speaker").
- Contiguous label sanity: `T1..T2` (no gaps).
- `TracksDevice` produces at least one stable face track.

Thorough E2E expectations (by stage):

Ingest:
- At least one face track present for most sampled frames.

Transcript:
- Non-empty, monotonic ticks.

Diarize:
- Exactly 2 non-offscreen speakers in `ecapa` mode.
- Speaker IDs deterministic across runs.

Confidence (strict-gated):
- Each word carries `attributionConfidence` with finite, sorted reasons.
- When face binding is strong, reasons should not include offscreen-related codes.

### 3) Two-person conversation (two men)
Fixture: `Tests/Assets/people_talking/Two_men_talking_202512192152_8bc18.mp4`

Expectations:
- Diarization produces exactly **2 non-offscreen speakers** in `ecapa` mode.
- Tracks device produces at least one face/person track and does not error.

Additional expectations:
- Speaker switching exists (not a single-speaker blob).
- (Future, mandate) if identity timeline exists, face↔speaker binding confidence is exported with reason codes.

Thorough E2E expectations (by stage):

Devices:
- `TracksDevice` produces >= 1 stable track; reacquisition events (if any) are surfaced deterministically.

Confidence (strict-gated):
- Track reacquisition downgrades device EvidenceConfidence with reason `track_reacquired` when it happens.

### 4) Long monologue / stress clip
Fixture: `Tests/Assets/VideoEdit/keith_talk.mov`

Expectations:
- Deterministic ingest timing probes succeed.
- Devices (mask + tracks) run without pixel format regressions.
- Diarization produces **1–2 non-offscreen speakers**.
- Render integration (person mask path) runs end-to-end.

Additional expectations:
- Diarization stability: avoid spurious extra speakers over time (anti-fragmentation cap).
- Mask stability metrics remain above threshold for a representative window, or emit explicit warnings.
- (Future, mandate) identity timeline exports confidence + reason codes suitable for Edit Safety.

Thorough E2E expectations (by stage):

Ingest:
- Timing probe passes; sampled timestamps monotonic.

Devices:
- `MaskDevice` output pixel format is `kCVPixelFormatType_OneComponent8`.
- Stability metrics computed over a window and warnings surfaced deterministically when unstable.

Render integration:
- Person-mask render path completes without GPU binding errors and produces deterministic output hashes for a sampled frame set.
