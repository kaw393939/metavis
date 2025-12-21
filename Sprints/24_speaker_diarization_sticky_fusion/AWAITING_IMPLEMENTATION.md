# Sprint 24: Speaker Diarization + Sticky Fusion (ECAPA‑TDNN)

## Architectural Mandate (Non‑Negotiable)
Everything Sprint 24 produces must be:
1. **Deterministic** — identical inputs produce identical outputs.
2. **Edit‑Grade Stable** — no flicker, churn, or surprise identity flips.
3. **Explicit About Uncertainty** — ambiguity is surfaced, labeled, and carried downstream.

If a result is uncertain, we label the uncertainty. We do not silently guess.

## Goal
Generate speaker-labeled, word-level transcripts suitable for interviews/podcasts by fusing:
- Whisper word timings
- existing MetaVis sensor data (face tracks)
- **on-device speaker embeddings** (ECAPA‑TDNN → clustering)

This pivots Sprint 24 from a purely heuristic “sticky fusion” approach to an **audio-first diarization backbone** that can correctly separate speakers even when faces are ambiguous.

## Status (as of 2025-12-21)
- A Sticky Fusion heuristic diarizer exists and remains a useful deterministic fallback.
- ECAPA‑TDNN (CoreML) embedding extraction + diarization clustering exists in code and is the primary signal when enabled.
- Remaining Sprint 24 work is now about making the results **edit-grade** and **first-class** in system contracts:
	- stable speaker segments (less over-splitting)
	- explicit `OFFSCREEN` handling
	- robust face/audio fusion hooks
	- acceptance fixtures that prevent regressions

## Newly available foundations (from Sprint 24a closure)
- Governed confidence is now implemented system-wide in `MetaVisCore`:
	- `ConfidenceRecordV1` + `ConfidenceGradeV1` + `ConfidenceSourceV1` + `ReasonCodeV1` live in `Sources/MetaVisCore/Confidence/ConfidenceRecordV1.swift`.
	- Reasons are a finite enum and are sorted deterministically by the type.
- Sensors ingest already emits deterministic warnings and governed reason codes (no silent degrade).
- Face track identity is already deterministic across runs (stable `trackId` mapping derived from `(sourceKey, stableIndex)` during ingest).

## What Already Exists (in Sources)
- Captions already support speaker tags in both formats:
	- WebVTT: writes `<v Speaker>` and parses it back.
	- SRT: writes `[Speaker] ` and parses it back.
	- Implementation: `Sources/MetaVisExport/Deliverables/SidecarWriters.swift` (`CaptionSidecarWriter`).
- The transcript pipeline already has fields for speaker attribution at the word level:
	- `transcript.word.v1` records include `speakerId` and `speakerLabel`.
	- Current behavior: these fields are emitted as `nil`.
	- Implementation: `Sources/MetaVisLab/TranscriptCommand.swift` (`writeWordsJSONL`).
- Sensors already contain the identity primitives Sprint 24 will fuse against:
	- Face detections: `MasterSensors.Face(trackId: UUID, rect: CGRect, personId: String?)`.
	- Audio segmentation: `audioSegments` with `.speechLike | .silence | ...`.
	- Optional audioFrames: `voicingScore`, `pitchHz`, and deltas.
	- Schema: `Sources/MetaVisPerception/MasterSensors.swift`.
- Deterministic face identity mapping is already implemented during ingest:
	- Vision tracking UUIDs are remapped into deterministic UUIDs derived from `(sourceKey, stableIndex)`.
	- `personId` is currently `"P\(idx)"` for the stable index.
	- Implementation: `Sources/MetaVisPerception/MasterSensorIngestor.swift`.
- Face tracking itself is stateful and exposed as a service:
	- `trackFaces(in:) -> [UUID: CGRect]` using Vision tracking.
	- Implementation: `Sources/MetaVisPerception/Services/FaceDetectionService.swift`.
- There is already one downstream consumer that treats `personId` as the only attribution signal:
	- Bite map builder explicitly states it does *not* do diarization beyond sensors’ `personId`.
	- Implementation: `Sources/MetaVisPerception/Bites/BiteMapBuilder.swift`.

## Gaps & Missing Features
- Captions support speaker tags, but we do not yet produce robust speaker attribution for multi-speaker clips.
- The embedding-backed diarizer still needs **edit-grade stability**:
	- reduce over-splitting in hard audio conditions
	- improve deterministic merges/cleanup rules
	- harden thresholds/defaults with fixture-backed acceptance tests
- Face/audio fusion still needs to be tightened:
	- explicit `OFFSCREEN` labeling when face binding is not confident
	- stronger binding confidence outputs (for downstream QC and edit-safety)
- Face identity churn remains a risk when Vision tracking drops and resumes; this needs stability + stickiness rules at the fusion layer.

## Required Upgrades (Sprint 24 “World‑Class”)

### 1) Speaker cluster lifecycle (critical)
Clusters must stop behaving like anonymous buckets.

Required lifecycle fields (conceptual):
- `bornAt`
- `lastActiveAt`
- `confidence`
- `mergeCandidates`
- `frozen` (after a deterministic stabilization window)

Rules:
- Clusters must not endlessly fragment.
- Merges must be deterministic and explainable.
- Once a cluster is frozen, it must not change identity retroactively.

### 2) `OFFSCREEN` is a first‑class speaker
`OFFSCREEN` is a semantic identity state, not a fallback string.

Requirements:
- `OFFSCREEN` has a stable `speakerId`.
- `OFFSCREEN` spans are contiguous and stable (no oscillation within an utterance).
- `OFFSCREEN` is emitted explicitly when:
  - no face binding exceeds threshold, or
  - binding confidence decays mid‑utterance.
- No silent reassignment.

### 3) Confidence surfaces (mandatory)
Every word-level speaker assignment must surface uncertainty.

#### 3.1 Canonical Confidence model (MetaVisCore)
Sprint 24 must not invent ad-hoc confidence.

Use the shared, versioned confidence type that now exists in `MetaVisCore` (`ConfidenceRecordV1`).

Remaining doc/code work:
- The current transcript JSONL record (`TranscriptWordV1`) does not yet carry `attributionConfidence`.
- To meet the mandate, we should either:
	- bump the transcript word schema (e.g. `transcript.word.v2`) to add `attributionConfidence: ConfidenceRecordV1`, or
	- emit a separate, versioned attribution sidecar keyed by `wordId`.

Required properties (conceptual; exact shape owned by `MetaVisCore`):
- `score` (0.0–1.0)
- `grade` (discrete; primary consumer signal)
- `sources` (audio / vision / fused)
- `reasons` (finite enum; sorted; stable across runs)
- `evidenceRefs` (links to evidence intervals/metrics)
- optional `policyId` (decision-layer only)

#### 3.2 Three confidence layers (enforced)
Sprint 24 produces and consumes distinct confidence types:
- **EvidenceConfidence**: reliability of the raw signal (e.g. ECAPA window quality, face track stability)
- **AttributionConfidence**: how sure we are that evidence X belongs to entity Y (word→speaker, speaker→face/person)
- **DecisionConfidence**: produced later by Scene State using policy logic (not produced by Sprint 24)

#### 3.3 Where confidence must surface
As versioned, deterministic outputs:
- `transcript.words.v1.jsonl`: today includes `speakerId` and `speakerLabel`.
- To add `attributionConfidence`, we will need a schema bump or a dedicated sidecar (see 3.1).
- Reasons must be **closed enums** (no free-text), sorted, and stable.

These fields are required inputs for Scene State (Edit Safety), automated QC, and later UI overlays.

### 4) Identity Timeline (new required artifact)
Create a canonical internal artifact that becomes the identity spine.

Conceptually: `identity.timeline.v1.json` containing:
- speaker clusters (+ lifecycle)
- face bindings
- `OFFSCREEN` spans
- confidence records (cluster + binding + attribution)
- reason codes (finite enum, sorted)

This artifact becomes the spine for:
- EditSafety
- AutoCut
- Expert Review
- future overlays

## Non-goals (this sprint)
- No full EvidencePack / Gemini edit plan.
- No network diarization models.

## How Sprint 24 plugs into the “Scene State” layer
Sprint 24 is not just a transcript feature. It produces an identity-aligned evidence stream that higher-level systems can trust.

**Scene State consumers** (examples):
- `EditSafety.safeDialogueEdit`: avoid edits where speaker identity is ambiguous.
- `SpeakerBindingTimeline`: bind speaker clusters to visual identities when possible, otherwise mark `OFFSCREEN`.
- `AutoCutPlanner`: prefer cut points that do not swap speaker attribution within the cut window.

See `Docs/specs/SCENE_STATE_DATA_DICTIONARY.md` for the intended derived outputs.

## Optional but high-leverage: Audio↔Lips sync confidence
When a face is visible, a lightweight A/V sync estimator can provide an additional fusion signal:
- Visual: mouth motion energy curve (from landmarks + ROI delta/flow)
- Audio: speech energy/VAD curve
- Alignment: cross-correlation peak → (offset, confidence)

This does not replace diarization; it improves **who-is-speaking** binding when multiple faces are present.

## References (reuse; avoid drift)
- Sensors ingest entrypoint: `Sources/MetaVisLab/SensorsCommand.swift`
- Sensors schema: `Sources/MetaVisPerception/MasterSensors.swift`
- Deterministic face `trackId` / `personId` mapping: `Sources/MetaVisPerception/MasterSensorIngestor.swift`
- Vision face tracking service (stateful): `Sources/MetaVisPerception/Services/FaceDetectionService.swift`
- Speech-like segmentation + optional audioFrames: `Sources/MetaVisPerception/AudioVADHeuristics.swift`
- Caption speaker tags: `Sources/MetaVisExport/Deliverables/SidecarWriters.swift`
- Transcript word records (speaker fields exist, currently unset): `Sources/MetaVisLab/TranscriptCommand.swift`

## Start here
- Sprint plan: `archive/PLAN.md`
- TDD plan: `archive/TDD_PLAN.md`
- Spec: `archive/SPEC.md`

## Updated Technical Plan (Research-Backed)

### Phase 0 — Keep the baseline (done)
Keep the existing Sticky Fusion heuristic as a fallback / baseline for clips where embeddings are unavailable.

### Phase 1 — Audio embedding pipeline (ANE)
- **Model:** `ECAPA‑TDNN` converted to CoreML.
	- Prefer Int8 (or FP16) if it reliably runs on ANE.
	- Static input shape only.
- **Input:** Fixed-length mono audio window (e.g. 2.0–3.0s @ 16kHz). Pad/trim to exact length.
- **Output:** Speaker embedding vector (e.g. 192‑dim).
- **Execution:** Must be ANE-friendly (no dynamic control flow; warmup at startup).

Deliverable:
- `SpeakerEmbeddingModel` wrapper (CoreML inference) under `MetaVisPerception`.

### Phase 2 — Online clustering (CPU)
- Compute cosine similarity using `Accelerate` (`vDSP`).
- Maintain online clusters with deterministic assignment:
	- assign to best cluster if similarity >= threshold
	- otherwise create a new cluster

Deliverable:
- `AudioSpeakerClusterer` (deterministic) that outputs time ranges and cluster IDs.

### Phase 3 — Fusion to faces (Late fusion)
- Build co-occurrence statistics between audio clusters and face tracks:
	- e.g. $P(\text{face} \mid \text{cluster})$ measured over time.
- Assign a face track to a cluster when co-occurrence exceeds a threshold (e.g. 0.8), otherwise label cluster as `OFFSCREEN`.
- Apply stickiness at the word level to avoid flip-flopping.

Deliverable:
- `SpeakerDiarizer` upgraded to use: (cluster label at time t) + (faces near t) → speakerId/speakerLabel.

## Acceptance criteria
- On multi-speaker “people talking” fixtures, the pipeline emits >1 non-offscreen speaker where appropriate.
- Deterministic outputs for identical inputs.
- Keeps current artifacts stable:
	- `transcript.words.v1.jsonl`
	- `captions.vtt` with `<v T#>`
	- `speaker_map.v1.json`
	- (new) `identity.timeline.v1.json` (internal)

Additional required acceptance:
- Word-level speaker attribution exposes explicit uncertainty via governed confidence (`attributionConfidence: ConfidenceRecord.v1`).
- `OFFSCREEN` is explicitly emitted under defined failure/decay conditions.
- Identity stability is budgeted and test-asserted (no churn explosions).

### Test requirements (do not regress)
- Golden fixtures include:
	- multi-speaker overlap windows
	- single-speaker monologue
	- offscreen narration over B-roll
- Contract tests assert:
	- speaker segments are stable under small timing jitter
	- speaker IDs are deterministic
	- `OFFSCREEN` is emitted when no face co-occurrence exceeds threshold
	- cluster lifecycle rules (born/lastActive/freeze) are deterministic
	- explainability: confidence grades + finite reason codes exist and are stable (sorted)
	- anti-fragmentation budgets (upper bounds on cluster births / minute)
