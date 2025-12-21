# Sprint 15 — Sensor (Master Ingest) — Gap Analysis

Date: 2025-12-16

This document compares the Sprint 15 spec in [Sprints/15_Sensor/README.md](README.md) against the current implementation in the repo.

## Executive summary

**Strong progress on the core ingest pipeline**: there is a working, local-first `MasterSensorIngestor` that produces a schema v3 `MasterSensors` object with video samples (faces, segmentation presence, luma/color/skin), audio analysis (approx LUFS/peak + VAD-ish segmentation), scene heuristics (indoor/outdoor + light source), editor warnings (video-only), suggested start, and an initial descriptor layer. The primary ingest behavior is covered by a fixture-backed test.

**Sprint 15 deliverable #1 is implemented**: `MetaVisLab sensors ingest` writes `MasterSensors` (`schemaVersion: 3`) to `sensors.json` deterministically, and there is a determinism regression test that asserts byte-stable JSON output for the same input.

**Remaining gaps**: identity (faceprints/personId), richer warning reason codes (flicker/motion blur/noise beyond the current set), expanding the descriptor vocabulary beyond the initial subset, and adding a fixture-backed multi-person test asset to validate the “>=2 people when present” acceptance criterion.

---

## What is implemented (complete)

### Master sensors schema exists and is v3
- `MasterSensors` exists, is `Codable`, and defaults to `schemaVersion = 3`.
- Includes top-level fields that match Sprint 15 intent:
  - `source`, `sampling`, `videoSamples`, `audioSegments`, `warnings`, `descriptors?`, `suggestedStart?`, `summary`.

Code:
- [Sources/MetaVisPerception/MasterSensors.swift](../../Sources/MetaVisPerception/MasterSensors.swift)

### Deterministic local-first ingest pipeline (library)
- `MasterSensorIngestor.ingest(url:)` builds a `MasterSensors` object by:
  - Sampling video frames on a fixed stride (min clamped at 0.25s).
  - Face tracking via Vision (`VNTrackObjectRequest`).
  - Person segmentation mask presence via Vision segmentation.
  - Visual analysis via `VideoAnalyzer` (mean luma derived from histogram, skin likelihood, dominant colors).
  - Audio analysis via AVAssetReader (RMS/peak) + VAD-ish segmentation on mono samples.
  - Scene context heuristics computed from dominant colors + luma.
  - Warning segments computed (video-only).
  - Suggested start computed.
  - Descriptors computed (initial subset).

Code:
- [Sources/MetaVisPerception/MasterSensorIngestor.swift](../../Sources/MetaVisPerception/MasterSensorIngestor.swift)
- [Sources/MetaVisPerception/Services/FaceDetectionService.swift](../../Sources/MetaVisPerception/Services/FaceDetectionService.swift)
- [Sources/MetaVisPerception/Services/PersonSegmentationService.swift](../../Sources/MetaVisPerception/Services/PersonSegmentationService.swift)
- [Sources/MetaVisPerception/AudioVADHeuristics.swift](../../Sources/MetaVisPerception/AudioVADHeuristics.swift)
- [Sources/MetaVisPerception/SceneContextHeuristics.swift](../../Sources/MetaVisPerception/SceneContextHeuristics.swift)

### Suggested start (auto-trim) implemented
- `AutoStartHeuristics.suggestStart(...)` exists and is used during ingest.
- Uses a speech-onset heuristic + “face centered and sufficiently sized” proxy.

Code:
- [Sources/MetaVisPerception/AutoStartHeuristics.swift](../../Sources/MetaVisPerception/AutoStartHeuristics.swift)

### Basic descriptor layer exists (LLM-friendly)
- Descriptors are generated deterministically with stable ordering and bounded ranges.
- Implemented labels today:
  - `suggested_start`, `single_subject`, `multi_person`, `no_face_detected`,
  - `continuous_speech`, `silence_gap`,
  - `safe_for_beauty`, `grade_confidence_low`, `avoid_heavy_grade`.

Code:
- [Sources/MetaVisPerception/DescriptorBuilder.swift](../../Sources/MetaVisPerception/DescriptorBuilder.swift)

### Basic editor warning system exists (video-only)
- Produces per-sample scores and coalesces them into warning segments.
- Reason codes implemented today:
  - `no_face_detected`, `multiple_faces_competing`, `face_too_small`, `underexposed_risk`, `overexposed_risk`.

Code:
- [Sources/MetaVisPerception/EditorWarningModel.swift](../../Sources/MetaVisPerception/EditorWarningModel.swift)

### Fixture-backed test covers key acceptance criteria
- `MasterSensorsIngestorTests` asserts:
  - schema version 3
  - outdoor + natural light in the fixture
  - mostly single-face detection
  - audio not silent
  - segmentation present
  - speech-like segments exist
  - suggestedStart exists
  - descriptors exist and are sorted/bounded
  - warnings not dominated by red

Test:
- [Tests/MetaVisPerceptionTests/MasterSensorsIngestorTests.swift](../../Tests/MetaVisPerceptionTests/MasterSensorsIngestorTests.swift)

---

## Partially implemented (needs expansion)

### Deterministic `sensors.json` output (implemented)
What exists:
- `MetaVisLab sensors ingest` writes `<out>/sensors.json` using `MasterSensors` (schema v3).
- A determinism regression test asserts byte-stable JSON output for repeated ingests of the same input.

Code:
- [Sources/MetaVisLab/SensorsCommand.swift](../../Sources/MetaVisLab/SensorsCommand.swift)
- [Tests/MetaVisPerceptionTests/MasterSensorsDeterminismTests.swift](../../Tests/MetaVisPerceptionTests/MasterSensorsDeterminismTests.swift)

### Audio sensors: partially implemented
What exists:
- Approx loudness (RMS-based) + peak.
- VAD-ish segmentation: `.speechLike`, `.silence`, `.unknown`.
- FFT-derived features are now emitted on `summary.audio`:
  - `dominantFrequencyHz`
  - `spectralCentroidHz`

What’s missing vs spec:
- Music-like segments (`musicLike`) are defined in the enum but never produced.
- Segment-level heuristics for `musicLikeSegments` beyond placeholder.

Code:
- [Sources/MetaVisPerception/MasterSensorIngestor.swift](../../Sources/MetaVisPerception/MasterSensorIngestor.swift)
- [Sources/MetaVisPerception/AudioVADHeuristics.swift](../../Sources/MetaVisPerception/AudioVADHeuristics.swift)

### Scene context sensors: partially implemented
What exists:
- `scene.indoorOutdoor` + `scene.lightSource` with confidence.

What’s missing vs spec:
- `scene.whiteBalanceHint`, `scene.timeOfDayHint`, and any explicit recording of model identifiers if Vision classification is added.

Code:
- [Sources/MetaVisPerception/SceneContextHeuristics.swift](../../Sources/MetaVisPerception/SceneContextHeuristics.swift)

### Video sensors: partially implemented
What exists:
- Per-sample `meanLuma`, `skinLikelihood`, `dominantColors`, `faces`, `personMaskPresence`, `peopleCountEstimate`.

What’s missing vs spec:
- Luma histogram output (kept internally in `VideoAnalyzer`, not stored).
- Exposure risk, flicker risk, motion blur proxies, stability metrics (as explicit fields).
- Mask artifacts/ref paths (spec says optional; current implementation uses presence only).

---

## Not implemented (or effectively stubbed)

### Identity / faceprints / re-identification
Sprint 15 requires stable `personId` across discontinuities via faceprint matching.

What exists:
- `FaceIdentityService` actor exists but is a stub (uses face-rectangle detection request due to API availability constraints).
- `MasterSensors.Face` only has `trackId: UUID` (tracker UUID), no `personId`.

What’s missing:
- Actual face embedding generation + gallery matching.
- Data contract decisions around embedding storage vs hashed IDs + cache path.

Code:
- [Sources/MetaVisPerception/Services/FaceIdentityService.swift](../../Sources/MetaVisPerception/Services/FaceIdentityService.swift)

### Audio-derived warnings
Spec includes audio warnings (`audio_silence`, `audio_clip_risk`, `audio_noise_risk`, cut stability warnings).

What exists:
- Audio-derived warning segments are now added alongside video warnings with stable reason codes:
  - `audio_silence`
  - `audio_clip_risk`
  - `audio_noise_risk`

What’s missing:
- Cut-point warnings (e.g. jump cut / interrupted speech) and more granular audio warning semantics.
- Score breakdown persisted under `sampling.detectors` (spec requirement).

Code:
- [Sources/MetaVisPerception/EditorWarningModel.swift](../../Sources/MetaVisPerception/EditorWarningModel.swift)

### Descriptor vocabulary breadth
Spec defines many descriptor labels and segment coalescing rules.

What exists:
- Descriptor system exists but currently emits only *full-span* descriptors (0..analyzedSeconds) for a small subset.

What’s missing:
- Most labels: `face_tracking_unstable`, `face_small_risk` (descriptor form), `subject_occluded_risk`, `interrupted_speech`, `broadband_noise_risk`, `outdoor_*` tags, `safe_for_subject_mask`, etc.
- Segment-level descriptors (not just whole-range) and coalescing identical to warnings.

Code:
- [Sources/MetaVisPerception/MasterSensors.swift](../../Sources/MetaVisPerception/MasterSensors.swift)
- [Sources/MetaVisPerception/DescriptorBuilder.swift](../../Sources/MetaVisPerception/DescriptorBuilder.swift)

### Toolchain beyond ingest (bites/dedupe/edl/verify/broll)
Sprint 15’s README outlines a larger deterministic toolchain contract.

What exists:
- Some editing/transcript tooling exists elsewhere in the repo, but Sprint 15’s specific toolchain outputs (`bites.json`, `dedupe.json`, `edit_map.json`, `edl.json`, `broll_plan.json`, `verification.json`) are not implemented as part of this sprint work yet.

---

## Risks / determinism concerns

1) **Tracking UUID stability**: `trackId` must be stable across repeated ingests and across machines/paths. The implementation should continue to derive stable IDs from source content identity (e.g. content hash) + stable indexing, not from Vision-provided UUIDs.

2) **JSON determinism**: this is now guarded by a regression test that asserts byte-stable JSON for repeated ingests of the same fixture.

3) **Segmentation performance**: segmentation is run at the same stride as video sampling. The spec suggests decimating segmentation (e.g., 1.0s) and keeping artifacts optional.

---

## Recommended next steps (in sprint-priority order)

1) **Identity**: implement real `personId` re-identification (faceprints) once the Vision API is available, with a deterministic fallback when unavailable.

2) **Audio features + warnings**: add FFT-derived features (dominant frequency / centroid) to output and introduce audio-derived warning reasons.

3) **Expand warnings + descriptors**: broaden reason codes and descriptor vocabulary toward the spec, and move toward segment-level descriptors with coalescing.
