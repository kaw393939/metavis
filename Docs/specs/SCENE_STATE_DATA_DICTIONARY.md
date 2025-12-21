# Scene State: Data Dictionary & Contracts

## Purpose
"Scene State" is the derived, higher-level summary layer that converts dense evidence streams (sensors, devices, audio analysis) into stable, testable signals for:
- edit planning (human or agent)
- compilation (timeline -> render graph)
- verification / QC gates ("AI has no eyes" defenses)

Scene State is designed to be:
- deterministic for identical inputs
- explainable (every output has reasons/provenance)
- compact (intervals/events rather than per-frame blobs)

## Layering

### 1) Raw Inputs (Evidence)
These are time-indexed, low-level measurements.
- MasterSensors (`sensors.json`) (metadata)
- transcript words (`transcript.words.v1.jsonl`) (word-level timings)
- diarization outputs (speaker segments + maps)
- device streams (mask/track/flow/depth) (GPU-friendly)

### 2) Scene State (Derived Summaries)
These are time ranges and events that can drive editing decisions.
- Shot segments
- People timeline (who is present)
- Speaker binding (who is speaking)
- Edit safety ratings (safe/caution/unsafe)
- Optional: A/V sync confidence

### 3) Compilation + Render
Scene State is consumed to:
- select safe edit points
- bind targets (person IDs, masks, depth) to render features

## Core Concepts

### Time Domain
All time is represented in `MetaVisCore.Time`.
- Every record uses a start time and a duration (or end time).
- All derived summaries must be stable under small timestamp jitter.

### Identity
Scene State expresses identity with stable IDs.
- `personId`: stable visual identity (e.g., `P1`, `P2`, ...)
- `speakerId`: stable audio identity (e.g., `S1`, `S2`, ...)
- `OFFSCREEN`: explicit speaker identity when no face binding is confident

## Proposed Schema (Conceptual)
This is an intended shape for a future `scene_state.v1.json` (or as an extension of sensors output). The exact file packaging is a separate decision.

### `SceneStateV1`
- `version`: string (`scene_state.v1`)
- `sourceKey`: string (hash/key of media identity)
- `timebase`: object (fps/scale or tick rate metadata)
- `shotSegments`: `[ShotSegmentV1]`
- `peopleTimeline`: `[PeopleSegmentV1]`
- `speakerTimeline`: `[SpeakerSegmentV1]`
- `speakerBindings`: `[SpeakerBindingSegmentV1]`
- `editSafety`: `[EditSafetySegmentV1]`
- `avSync`: optional `[AVSyncSegmentV1]`

### `ShotSegmentV1`
- `range`: {`start`, `end`}
- `confidence`: 0..1
- `reasonCodes`: [string]

### `SpeakerSegmentV1`
- `range`
- `speakerId`: string
- `confidence`: 0..1

### `SpeakerBindingSegmentV1`
- `range`
- `speakerId`: string
- `personId`: string | `OFFSCREEN`
- `confidence`: 0..1
- `evidence`: { optional stats like co-occurrence }

## Edit Safety Rating
Edit safety is operation-specific.

### `EditSafetySegmentV1`
- `range`
- `operation`: one of
  - `cut`
  - `reframe`
  - `maskFx`
  - `dialogueEdit`
- `label`: `safe` | `caution` | `unsafe`
- `score`: 0..1
- `reasons`: `[ReasonCodeV1]`
- `targets`: optional (`personId`, `speakerId`)

### Reason codes (starter set)
- `no_face_detected`
- `multiple_faces_ambiguous`
- `face_too_small`
- `occlusion_risk`
- `framing_jump_risk`
- `mask_unstable`
- `flow_unstable`
- `depth_missing`
- `depth_noisy`
- `speaker_overlap`
- `speaker_low_confidence`
- `av_sync_low_confidence`

## Notes on Computation (Deterministic)
- Prefer interval aggregation (e.g., 2–5 fps sampling) + propagation to avoid per-frame compute.
- Every Scene State producer should record provenance (what evidence and thresholds were used) to keep outputs explainable.

## Test Requirements
- Contract tests must assert stable outputs for the same inputs.
- Golden fixtures must include:
  - talking-head interview (single speaker)
  - two-person dialogue with turn-taking
  - offscreen narration over B-roll
  - fast camera motion / occlusions

Related sprint docs:
- `Sprints/24_speaker_diarization_sticky_fusion/*`
- `Sprints/24a_upgraded_sensors_done/*`

